#!/usr/bin/env bash

show_usage() {
	echo "Usage: dot [command] [args]"
	echo "Commands:"
	echo "  init          Initialize new dotfiles repository"
	echo "  add [path]    Copy file at [path] to dotfiles"
	echo "  rm [path]     Remove the copy of [path] from dotfiles"
	echo "  cd            Open a shell in the dotfiles directory"
	echo "  sync          Sync with remote and check for missing files"
	echo "  env           Output shell configuration"
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
		echo "$@"
	fi
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

get_paths() {
	local file_path="$1"
	if [[ -z "$file_path" ]]; then
		error "Please specify a path"
	fi

	src_path=$(realpath "$file_path")
	if [[ ! -e "$src_path" ]]; then
		error "$file_path does not exist"
	fi

	rel_path=$(realpath --relative-to="$HOME" "$src_path")
	target_path="$DOT_DIR/$rel_path"
	target_dir=$(dirname "$target_path")
}

# Basic directory navigation without sync
_enter_raw() {
	pushd "$DOT_DIR" &>/dev/null || error "Failed to enter $DOT_DIR"
}

_exit_raw() {
	popd &>/dev/null
}

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

"add")
	if [[ -z "$2" ]]; then
		error "Please specify a path to add"
	fi

	# Get all paths
	get_paths "$2"

	# Create directory structure if it doesn't exist
	mkdir -p "$target_dir"

	# Copy file to dotfiles repo
	cp -r "$src_path" "$target_path"

	# Add to git
	_enter
	git add "$rel_path"
	echo "Added '$rel_path' to dotfiles"
	_exit
	;;

"rm")
	if [[ -z "$2" ]]; then
		error "Please specify a path to remove"
	fi

	# Get all paths
	get_paths "$2"

	if [[ ! -e "$target_path" ]]; then
		error "$2 is not managed by dot"
	fi

	# Remove file from dotfiles repo
	_enter
	git rm --cached "$rel_path"
	rm -r "$target_path"
	echo "Removed '$rel_path' from dotfiles"
	_exit
	;;

"sync")
	_enter
	git pull
	# Check if source files still exist
	find "$DOT_DIR" -type f -not -path '*/.git/*' | while read -r file; do
		rel_path="${file#$DOT_DIR/}"
		src_path="$HOME/$rel_path"
		if [[ ! -e "$src_path" ]]; then
			echo "Warning: original file missing for $rel_path"
		fi
	done
	_exit
	;;

*)
	# Pass through all other commands to git in the dotfiles directory
	_enter
	git "$@"
	_exit
	;;
esac
