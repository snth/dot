#!/usr/bin/env bash

show_usage() {
  echo "Usage: dot [options] [command] [args]"
  echo
  echo "Options:"
  echo "  -v           Enable verbose output"
  echo "  -vv          Enable debug output"
  echo
  echo "Commands:"
  echo "  init          Initialize new dotfiles repository"
  echo "  track [path]  Start tracking file at [path] in dotfiles"
  echo "  cd            Open a shell in the dotfiles directory"
  echo "  env           Output shell configuration"
  echo "  [git-cmd]     Any git command (executed in dotfiles directory)"
  exit 1
}

# Show usage if no arguments provided
if [ $# -eq 0 ]; then
  show_usage
fi

# Default dotfiles location, can be overridden by setting DOT_DIR
if [ -z "$DOT_DIR" ]; then
  DOT_DIR="$HOME/.config/dotfiles"
fi

# Verbosity level
VERBOSITY=0

# Function to check if verbosity level is met
meets_verbosity() {
  local required_level=$1
  [[ $VERBOSITY -ge $required_level ]]
}

# Function to print based on verbosity level
vecho() {
  local level=$1
  shift
  if meets_verbosity "$level"; then
    echo "$@" >&2
  fi
}

error() {
  echo "Error: $1" >&2
  exit 1
}

ensure_git_repo() {
  if [[ ! -d "$DOT_DIR/.git" ]]; then
    error "dotfiles repository not initialized. Run 'dot init' first."
  fi
}

# Ensure we're in a git repository or handling init/env/cd for subsequent commands
if [[ "$1" != "init" && "$1" != "env" && "$1" != "cd" ]]; then
  ensure_git_repo
fi

# Function to safely copy preserving attributes
safe_copy() {
  local src="$1"
  local dst="$2"

  if [[ -d "$src" ]]; then
    # Create the target directory
    mkdir -p "$dst"

    # Iterate through source directory contents
    local item
    for item in "$src"/*; do
      [[ -e "$item" ]] || continue # Handle empty directories

      # Skip .git directories
      if [[ "$(basename "$item")" == ".git" ]]; then
        vecho 2 "Skipping .git directory: $item"
        continue
      fi

      # If it's a directory, recurse
      if [[ -d "$item" ]]; then
        safe_copy "$item" "$dst/$(basename "$item")"
      else
        cp -p "$item" "$dst/"
      fi
    done

    # Also copy hidden files (except .git)
    for item in "$src"/.*; do
      [[ -e "$item" ]] || continue # Handle no hidden files case
      local base
      base=$(basename "$item")
      if [[ "$base" != "." && "$base" != ".." && "$base" != ".git" ]]; then
        if [[ -d "$item" ]]; then
          safe_copy "$item" "$dst/$base"
        else
          cp -p "$item" "$dst/"
        fi
      fi
    done
  else
    cp -p "$src" "$dst"
  fi
}

# Basic directory navigation without sync
_enter_raw() {
  pushd "$DOT_DIR" &>/dev/null || error "Failed to enter $DOT_DIR"
}

_exit_raw() {
  popd &>/dev/null
}

# Function to get list of tracked files by git
get_tracked_files() {
  _enter_raw
  git ls-files
  _exit_raw
}

# Sync files before entering dotfiles directory
_enter() {
  vecho 1 "Syncing files to dotfiles directory..."
  _enter_raw
}

# Sync modified files back to original locations
_exit() {
  local exit_status=$?
  _exit_raw
  return $exit_status
}

# Function to translate a path to be relative to current directory
translate_path() {
  local arg="$1"

  vecho 2 "Translating path: $arg"

  # Skip if the argument doesn't exist as a file or directory
  if [[ ! -e "$arg" ]]; then
    vecho 2 "Path does not exist, keeping unchanged: $arg"
    echo "$arg"
    return
  fi

  # Get the absolute path
  local abs_path
  abs_path=$(realpath "$arg")
  vecho 2 "Absolute path: $abs_path"

  # Get path relative to home directory
  if [[ "$abs_path" == "$HOME"/* ]]; then
    local rel_path
    rel_path=${abs_path#"$HOME/"}
    vecho 2 "Translated to path relative to HOME: $rel_path"
    echo "$rel_path"
  else
    # For paths not under HOME, preserve the full path structure from current location
    local pwd_rel_to_home
    pwd_rel_to_home=${PWD#"$HOME/"}
    local rel_to_pwd
    rel_to_pwd=$(realpath --relative-to="$PWD" "$abs_path")
    local rel_path="$pwd_rel_to_home/$rel_to_pwd"
    vecho 2 "Translated to full relative path: $rel_path"
    echo "$rel_path"
  fi
}

# Parse verbosity options before other arguments
while [[ $1 == -* ]]; do
  case "$1" in
  -v)
    VERBOSITY=1
    shift
    ;;
  -vv)
    VERBOSITY=2
    shift
    ;;
  *)
    break
    ;;
  esac
done

# Convert relative script path to absolute for alias generation
SCRIPT_PATH=$(realpath "$0")

case "$1" in
"env")
  echo "# Add this to your shell configuration file (.bashrc, .zshrc, etc.):"
  echo "export DOT_DIR=\"\$HOME/.config/dotfiles\""
  echo "alias dot='$SCRIPT_PATH'"
  exit 0
  ;;

"cd")
  if [[ ! -d "$DOT_DIR" ]]; then
    error "$DOT_DIR does not exist"
  fi
  _enter
  $SHELL
  _exit
  exit 0
  ;;

"init")
  if [[ -d "$DOT_DIR" ]]; then
    error "$DOT_DIR already exists"
  fi

  mkdir -p "$DOT_DIR"
  _enter_raw
  git init
  if [[ $? -eq 0 ]]; then
    echo "Initialized empty dotfiles repository in $DOT_DIR"
  fi
  _exit_raw
  ;;

"track")
  if [[ -z "$2" ]]; then
    error "Please specify a path to track"
  fi

  # Get absolute path of source
  src_path="$(realpath "$2")"

  # Verify source exists
  if [[ ! -e "$src_path" ]]; then
    error "Source path does not exist: $src_path"
  fi

  # Check if we're trying to track a .git directory
  if [[ "$src_path" == */.git || "$src_path" == */.git/* ]]; then
    error "Cannot track .git directories or files"
  fi

  # Get the full relative path preserving directory structure
  rel_path=$(translate_path "$2")
  target_path="$DOT_DIR/$rel_path"
  target_dir=$(dirname "$target_path")

  vecho 2 "Source path: $src_path"
  vecho 2 "Relative path: $rel_path"
  vecho 2 "Target path: $target_path"

  # Create directory structure if it doesn't exist
  mkdir -p "$target_dir"

  # Copy file or directory to dotfiles repo
  if [[ -d "$src_path" ]]; then
    safe_copy "$src_path" "$target_dir/$(basename "$src_path")" || error "Failed to copy directory to dotfiles"
  else
    safe_copy "$src_path" "$target_dir/" || error "Failed to copy file to dotfiles"
  fi

  # Add to git
  _enter
  git add "$rel_path"
  echo "Started tracking: $rel_path"
  _exit
  ;;

*)
  # Pass through all other commands to git in the dotfiles directory
  # but first translate any file/directory arguments
  cmd="$1"
  shift
  translated_args=()

  vecho 2 "Processing git command: $cmd"
  for arg in "$@"; do
    vecho 2 "Processing argument: $arg"
    translated_args+=("$(translate_path "$arg")")
  done

  _enter
  git "$cmd" "${translated_args[@]}"
  _exit
  ;;
esac
