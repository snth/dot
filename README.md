# dot - Simple Git-Based Dotfiles Manager

`dot` is a minimalist dotfiles manager that leverages git for version control while keeping your configuration files in their original locations. It works by maintaining a separate dotfiles repository and automatically syncing tracked files between their original locations and the repository.

The main philosophy is to delegate as much functionality as possible to git while providing a thin convenience layer for tracking and syncing files.

## Features

- Simple, bash-based implementation
- Uses git for version control
- Keeps files in their original locations
- Automatic syncing of tracked files
- Supports any git command
- Verbose output options for debugging

## Quickstart

1. Download `dot.sh` and make it executable:
```bash
curl -o ~/.local/bin/dot https://raw.githubusercontent.com/snth/dot/main/dot.sh
chmod +x ~/.local/bin/dot
```

2. Set up your shell environment:
```bash
# Add to your .bashrc or .zshrc
eval "$(dot env)"
```

3. Initialize your dotfiles repository:
```bash
dot init
```

## Usage

```bash
dot [options] [command] [args]

Options:
  -v           Enable verbose output
  -vv          Enable debug output

Commands:
  init          Initialize new dotfiles repository
  track [path]  Start tracking file at [path] in dotfiles
  cd            Open a shell in the dotfiles directory
  env           Output shell configuration
  [git-cmd]     Any git command (executed in dotfiles directory)
```

## Example Session

Here's a typical workflow for managing your dotfiles:

```bash
# Initialize a new dotfiles repository
dot init

# Start tracking some config files
dot track ~/.bashrc

# Check status of your dotfiles
dot status

# Make some changes to .bashrc
echo -e '# dot for dotfiles management\neval "$(dot env)"' >> ~/.bashrc

# Review and commit changes
dot diff
dot commit -am "Added dot to ~/.bashrc"

# Push to a remote repository
dot remote add origin git@github.com:${GITHUB_USER}/dotfiles.git
dot push -u origin main

# Later, on another machine
git clone git@github.com:${GITHUB_USER}/dotfiles.git ~/.config/dotfiles
# Copy files to their correct locations
dot checkout main
```

## How It Works

1. When you run `dot track <file>`, the file is copied to your dotfiles repository (default: `~/.config/dotfiles`) while maintaining its relative path structure from your home directory.

2. When you run `dot cd`, the script:
   - Syncs any changes from your home directory to the repository
   - Opens a shell in the repository directory
   - When you exit, syncs any changes back to your home directory

3. All other commands are passed directly to git, with paths automatically translated relative to your home directory.

## Environment Variables

- `DOT_DIR`: Override the default dotfiles location (`~/.config/dotfiles`)
