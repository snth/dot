dot() {
  # Ensure we're in a git repository or handling init
  if [[ "$1" != "init" ]]; then
    local repo_root
    repo_root=$(git rev-parse --show-toplevel 2>/dev/null)
    if [[ $? -ne 0 ]]; then
      echo "Error: not in a git repository"
      return 1
    fi
  fi

  case "$1" in
  "init")
    git init
    if [[ $? -eq 0 ]]; then
      echo -e "*\n!.gitignore" >.gitignore
      git add .gitignore
      git commit -m "Initializes dot repo"
      echo "Repository initialized with default .gitignore"
    fi
    ;;

  "add")
    if [[ -z "$2" ]]; then
      echo "Error: Please specify a path to add"
      return 1
    fi

    # Convert path to be relative to repo root
    local rel_path
    rel_path=$(realpath --relative-to="$repo_root" "$(realpath "$2")")

    # Append to .gitignore if pattern doesn't already exist
    if ! grep -q "^${rel_path}$" "${repo_root}/.gitignore"; then
      echo "!${rel_path}" >>"${repo_root}/.gitignore"
      git add "${repo_root}/.gitignore"
      echo "Added '!${rel_path}' to .gitignore"
    fi

    git add "$2"
    ;;

  "rm")
    if [[ -z "$2" ]]; then
      echo "Error: Please specify a path to remove"
      return 1
    fi

    # Convert path to be relative to repo root
    local rel_path
    rel_path=$(realpath --relative-to="$repo_root" "$(realpath "$2")")

    # Remove from .gitignore, maintaining empty lines
    sed -i "/^!${rel_path}$/d" "${repo_root}/.gitignore"
    git add "${repo_root}/.gitignore"
    echo "Removed '!${rel_path}' from .gitignore"
    git rm --cached "$2"
    ;;

  *)
    # Pass through all other commands to git
    git "$@"
    ;;
  esac
}
