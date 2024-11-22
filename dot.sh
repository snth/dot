#!/usr/bin/env bash

# Convert relative script path to absolute for alias generation
SCRIPT_PATH=$(realpath "$0")

# Default dotfiles location, can be overridden by setting DOT_DIR
if [ -z "$DOT_DIR" ]; then
	DOT_DIR="$HOME/.config/dotfiles"
fi

# Show usage if no arguments provided
if [ $# -eq 0 ]; then
	echo "Usage: dot [command] [args]"
	echo "Commands:"
	echo "  init          Initialize new dotfiles repository"
	echo "  add [path]    Add a file to dotfiles"
	echo "  rm [path]     Remove a file from dotfiles"
	echo "  status        Show git status"
	echo "  sync          Sync with remote and update symlinks"
	echo "  env           Output shell configuration"
	exit 1
fi

# Ensure we're in a git repository or handling init/env for subsequent commands
if [[ "$1" != "init" && "$1" != "env" ]]; then
	if [[ ! -d "$DOT_DIR/.git" ]]; then
		echo "Error: dotfiles repository not initialized. Run 'dot init' first."
		exit 1
	fi
fi

case "$1" in
"env")
	echo "# Add this to your shell configuration file (.bashrc, .zshrc, etc.):"
	echo "export DOT_DIR=\"\$HOME/.config/dotfiles\""
	echo "alias dot='$SCRIPT_PATH'"
	exit 0
	;;

"init")
	if [[ -d "$DOT_DIR" ]]; then
		echo "Error: $DOT_DIR already exists"
		exit 1
	fi

	mkdir -p "$DOT_DIR"
	pushd "$DOT_DIR" &>/dev/null || {
		echo "Failed to pushd to $DOT_DIR"
		exit 1
	}
	git init
	if [[ $? -eq 0 ]]; then
		echo "Initialized empty dotfiles repository in $DOT_DIR"
	fi
	popd &>/dev/null
	;;

"add")
	if [[ -z "$2" ]]; then
		echo "Error: Please specify a path to add"
		exit 1
	fi

	# Get absolute paths
	src_path=$(realpath "$2")

	if [[ ! -e "$src_path" ]]; then
		echo "Error: $2 does not exist"
		exit 1
	fi

	# Create relative path structure in dotfiles repo
	rel_path=$(realpath --relative-to="$HOME" "$src_path")
	target_path="$DOT_DIR/$rel_path"
	target_dir=$(dirname "$target_path")

	# Create directory structure if it doesn't exist
	mkdir -p "$target_dir"

	# Create symlink in dotfiles repo pointing to original file
	ln -s "$src_path" "$target_path"

	# Add to git
	pushd "$DOT_DIR" &>/dev/null || {
		echo "Failed to pushd to $DOT_DIR"
		exit 1
	}
	git add "$rel_path"
	echo "Added '$rel_path' to dotfiles"
	popd &>/dev/null
	;;

"rm")
	if [[ -z "$2" ]]; then
		echo "Error: Please specify a path to remove"
		exit 1
	fi

	# Get absolute paths
	src_path=$(realpath "$2")
	rel_path=$(realpath --relative-to="$HOME" "$src_path")
	target_path="$DOT_DIR/$rel_path"

	if [[ ! -L "$target_path" ]]; then
		echo "Error: $2 is not managed by dot"
		exit 1
	fi

	# Remove symlink from dotfiles repo
	pushd "$DOT_DIR" &>/dev/null || {
		echo "Failed to pushd to $DOT_DIR"
		exit 1
	}
	git rm --cached "$rel_path"
	rm "$target_path"
	echo "Removed '$rel_path' from dotfiles"
	popd &>/dev/null
	;;

"status")
	pushd "$DOT_DIR" &>/dev/null || {
		echo "Failed to pushd to $DOT_DIR"
		exit 1
	}
	git status
	popd &>/dev/null
	;;

"sync")
	pushd "$DOT_DIR" &>/dev/null || {
		echo "Failed to pushd to $DOT_DIR"
		exit 1
	}
	git pull
	# Verify symlinks point to existing files
	find "$DOT_DIR" -type l | while read -r link; do
		rel_path="${link#$DOT_DIR/}"
		target=$(readlink "$link")
		if [[ ! -e "$target" ]]; then
			echo "Warning: broken symlink for $rel_path (target: $target)"
		fi
	done
	popd &>/dev/null
	;;

*)
	# Pass through all other commands to git in the dotfiles directory
	pushd "$DOT_DIR" &>/dev/null || {
		echo "Failed to pushd to $DOT_DIR"
		exit 1
	}
	git "$@"
	popd &>/dev/null
	;;
esac
