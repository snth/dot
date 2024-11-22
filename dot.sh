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

# Function to get list of tracked files relative to home
get_tracked_files() {
	local files=()
	local IFS=$'\n'

	_enter_raw
	# Collect all tracked files in an array
	mapfile -t files < <(git ls-files)
	_exit_raw

	# Output full paths
	for file in "${files[@]}"; do
		echo "$HOME/$file"
	done
}

# Basic directory navigation without sync
_enter_raw() {
	pushd "$DOT_DIR" &>/dev/null || error "Failed to enter $DOT_DIR"
}

_exit_raw() {
	popd &>/dev/null
}

# Sync files before entering dotfiles directory
_enter() {
	vecho 1 "Syncing files to dotfiles directory..."

	# Get list of tracked files and process them
	local file_list
	file_list=$(get_tracked_files)

	if [[ -z "$file_list" ]]; then
		vecho 2 "No tracked files found"
		_enter_raw
		return
	fi

	echo "$file_list" | while read -r src_file; do
		# Debug output
		vecho 2 "Processing: $src_file"

		# Skip if source doesn't exist
		[[ ! -f "$src_file" ]] && {
			vecho 2 "Skipping non-existent file: $src_file"
			continue
		}

		# Calculate paths
		rel_path=$(realpath --relative-to="$HOME" "$src_file")
		dot_file="$DOT_DIR/$rel_path"

		# Debug output
		vecho 2 "Relative path: $rel_path"
		vecho 2 "Destination: $dot_file"

		# Ensure target directory exists
		mkdir -p "$(dirname "$dot_file")"

		# Copy file if it exists and is newer
		if [[ "$src_file" -nt "$dot_file" ]]; then
			vecho 2 "Copying newer file: $src_file -> $dot_file"
			cp -p "$src_file" "$dot_file" || error "Failed to copy $src_file to dotfiles"
			vecho 1 "Updated: $rel_path"
		else
			vecho 2 "File up to date: $rel_path"
		fi
	done

	# Enter directory after sync
	_enter_raw
}

# Sync modified files back to original locations
_exit() {
	local exit_status=$?

	vecho 1 "Syncing changes back to home directory..."

	# Get list of modified files in git repo
	local modified_files
	modified_files=$(git diff --name-only)

	# For each modified file, copy back to home directory
	for rel_path in $modified_files; do
		src_file="$DOT_DIR/$rel_path"
		dst_file="$HOME/$rel_path"

		# Skip if source doesn't exist
		[[ ! -f "$src_file" ]] && {
			vecho 2 "Skipping non-existent file: $src_file"
			continue
		}

		# Ensure target directory exists
		mkdir -p "$(dirname "$dst_file")"

		# Copy file back
		if cp -p "$src_file" "$dst_file"; then
			vecho 1 "Synced: $rel_path"
		else
			echo "Warning: Failed to sync $rel_path" >&2
		fi
	done

	# Exit directory
	_exit_raw

	# Preserve original exit status
	return $exit_status
}

# Function to translate a path to be relative to HOME if it's a file or directory
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

	# Check if the path is under HOME
	if [[ "$abs_path" == "$HOME"/* ]]; then
		# Get path relative to HOME
		local rel_path
		rel_path=$(realpath --relative-to="$HOME" "$abs_path")
		vecho 2 "Translated to path relative to HOME: $rel_path"
		echo "$rel_path"
	else
		vecho 2 "Path not under HOME, keeping unchanged: $arg"
		echo "$arg"
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
	_enter
	git init
	if [[ $? -eq 0 ]]; then
		echo "Initialized empty dotfiles repository in $DOT_DIR"
	fi
	_exit
	;;

"track")
	if [[ -z "$2" ]]; then
		error "Please specify a path to track"
	fi

	# Get translated path and store it
	rel_path=$(translate_path "$2")
	src_path="$(realpath "$2")"
	target_path="$DOT_DIR/$rel_path"
	target_dir=$(dirname "$target_path")

	# Verify source exists
	if [[ ! -f "$src_path" ]]; then
		error "Source file does not exist: $src_path"
	fi

	vecho 2 "Source path: $src_path"
	vecho 2 "Target path: $target_path"

	# Create directory structure if it doesn't exist
	mkdir -p "$target_dir"

	# Copy file to dotfiles repo
	cp -p "$src_path" "$target_path" || error "Failed to copy file to dotfiles"

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
