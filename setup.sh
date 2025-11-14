#!/bin/bash

set -e

SCRIPT_PATH=$(dirname $(readlink -f "${0}" 2>/dev/null || realpath "${0}" 2>/dev/null || echo "${0}"))
source "${SCRIPT_PATH}/aws-functions.sh"

# Scripts to symlink (exclude setup.sh, aws-functions.sh, LICENSE, README.md)
SCRIPTS=(
  "aws-cw"
  "aws-ecr-login"
  "aws-eks-update"
  "aws-imagebuilder"
  "aws-profiles"
  "aws-sessions"
  "aws-sso-login"
)

# Dependencies to check
DEPENDENCIES=(
  "aws:AWS CLI"
  "fzf:fzf (optional, for interactive selection)"
  "jq:jq"
  "perl:perl"
)

# Optional dependencies
OPTIONAL_DEPENDENCIES=()

MODE="interactive"
TARGET_DIR=""
DRY_RUN=false

usage() {
  echo "Usage: $(basename $0) [-t|--target TARGET_DIR] [-s|--silent] [-n|--dry-run] [-h|--help]"
  echo ""
  echo "Options:"
  echo "  -t, --target DIR    Target directory where symlinks will be created (required)"
  echo "  -s, --silent         Silent mode: only show info and warnings, skip prompts"
  echo "  -n, --dry-run        Dry-run mode: show what would be done without making changes"
  echo "  -h, --help           Show this help message"
  echo ""
  echo "Examples:"
  echo "  $(basename $0) --target ~/bin"
  echo "  $(basename $0) --target /usr/local/bin --silent"
  echo "  $(basename $0) --target ~/bin --dry-run"
}

# Detect OS type for installation instructions
detect_os() {
  if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    OS_ID="${ID}"
    OS_VERSION_ID="${VERSION_ID}"
  elif [[ "$(uname)" == "Darwin" ]]; then
    OS_ID="macos"
  else
    OS_ID="unknown"
  fi
}

# Check if a command exists
check_command() {
  type "$1" &>/dev/null
}

# Get installation command for a dependency based on OS
get_install_command() {
  local cmd=$1
  local os=$2

  case "$os" in
    "macos")
      case "$cmd" in
        "aws") echo "brew install awscli" ;;
        "fzf") echo "brew install fzf" ;;
        "jq") echo "brew install jq" ;;
        "perl") echo "Perl is pre-installed on macOS" ;;
      esac
      ;;
    "ubuntu"|"debian")
      case "$cmd" in
        "aws") echo "sudo apt-get update && sudo apt-get install -y awscli" ;;
        "fzf") echo "sudo apt-get install -y fzf" ;;
        "jq") echo "sudo apt-get install -y jq" ;;
        "perl") echo "sudo apt-get install -y perl" ;;
      esac
      ;;
    "alpine")
      case "$cmd" in
        "aws") echo "apk add --no-cache aws-cli" ;;
        "fzf") echo "apk add --no-cache fzf" ;;
        "jq") echo "apk add --no-cache jq" ;;
        "perl") echo "apk add --no-cache perl" ;;
      esac
      ;;
    "fedora"|"rhel"|"centos"|"rocky"|"almalinux")
      case "$cmd" in
        "aws") echo "sudo dnf install -y awscli" ;;
        "fzf") echo "sudo dnf install -y fzf" ;;
        "jq") echo "sudo dnf install -y jq" ;;
        "perl") echo "sudo dnf install -y perl" ;;
      esac
      ;;
    *)
      log_warn "Unknown OS type: $os. Please install $cmd manually."
      return 1
      ;;
  esac
}

# Check dependencies
check_dependencies() {
  local missing_deps=()
  local missing_optional=()
  local os_type

  detect_os
  os_type="${OS_ID}"

  log_info "Checking dependencies..."

  # Check required dependencies
  for dep in "${DEPENDENCIES[@]}"; do
    IFS=':' read -r cmd name <<< "$dep"
    if check_command "$cmd"; then
      log_ok "$name is installed"
    else
      missing_deps+=("$cmd:$name")
      log_warn "$name is not installed"
    fi
  done

  # Check optional dependencies
  for dep in "${OPTIONAL_DEPENDENCIES[@]}"; do
    IFS=':' read -r cmd name <<< "$dep"
    if check_command "$cmd"; then
      log_ok "$name is installed"
    else
      missing_optional+=("$cmd:$name")
      log_warn "$name is not installed (optional)"
    fi
  done

  # Show installation instructions for missing dependencies
  if [[ ${#missing_deps[@]} -gt 0 ]] || [[ ${#missing_optional[@]} -gt 0 ]]; then
    echo ""
    log_info "Installation instructions:"
    echo ""

    for dep in "${missing_deps[@]}" "${missing_optional[@]}"; do
      IFS=':' read -r cmd name <<< "$dep"
      echo "  ${BOLD}$name${NC}:"

      # macOS
      if [[ "$os_type" == "macos" ]]; then
        install_cmd=$(get_install_command "$cmd" "macos")
        echo "    macOS: $install_cmd"
      fi

      # Debian/Ubuntu
      if [[ "$os_type" == "ubuntu" ]] || [[ "$os_type" == "debian" ]]; then
        install_cmd=$(get_install_command "$cmd" "$os_type")
        echo "    Debian/Ubuntu: $install_cmd"
      fi

      # Alpine
      if [[ "$os_type" == "alpine" ]]; then
        install_cmd=$(get_install_command "$cmd" "alpine")
        echo "    Alpine: $install_cmd"
      fi

      # RPM-based (Fedora, RHEL, CentOS, Rocky, AlmaLinux)
      if [[ "$os_type" == "fedora" ]] || [[ "$os_type" == "rhel" ]] || \
         [[ "$os_type" == "centos" ]] || [[ "$os_type" == "rocky" ]] || \
         [[ "$os_type" == "almalinux" ]]; then
        install_cmd=$(get_install_command "$cmd" "$os_type")
        echo "    RPM-based: $install_cmd"
      fi

      # Generic instructions if OS not detected
      if [[ "$os_type" == "unknown" ]]; then
        case "$cmd" in
          "aws") echo "    Install AWS CLI from: https://aws.amazon.com/cli/" ;;
          "fzf") echo "    Install fzf from: https://github.com/junegunn/fzf" ;;
          "jq") echo "    Install jq from: https://stedolan.github.io/jq/" ;;
          "perl") echo "    Install perl using your system's package manager" ;;
        esac
      fi

      echo ""
    done
  fi

  # Exit if required dependencies are missing
  if [[ ${#missing_deps[@]} -gt 0 ]]; then
    log_fatal "Missing required dependencies. Please install them before continuing."
  fi
}

# Check if target is already a symlink to our script
is_symlink_to_script() {
  local target=$1
  local script=$2

  if [[ -L "$target" ]]; then
    local link_target=$(readlink -f "$target" 2>/dev/null || readlink "$target" 2>/dev/null)
    local script_abs=$(readlink -f "$script" 2>/dev/null || realpath "$script" 2>/dev/null || echo "$script")

    if [[ "$link_target" == "$script_abs" ]]; then
      return 0
    fi
  fi
  return 1
}

# Create symlink for a script
# Returns: 0 = created, 1 = skipped, 2 = already exists
create_symlink() {
  local script=$1
  local target_dir=$2
  local script_name=$(basename "$script")
  local target_path="${target_dir}/${script_name}"

  # Check if target already exists
  if [[ -e "$target_path" ]] || [[ -L "$target_path" ]]; then
    # Check if it's already a symlink to our script
    if is_symlink_to_script "$target_path" "${SCRIPT_PATH}/${script_name}"; then
      if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Symlink already exists: ${target_path} -> ${SCRIPT_PATH}/${script_name}"
      else
        log_info "Symlink already exists: ${target_path} -> ${SCRIPT_PATH}/${script_name}"
        chmod +x "$target_path" 2>/dev/null || true
      fi
      return 2
    fi

    # File exists but is not our symlink
    if [[ "$MODE" == "silent" ]]; then
      if [[ "$DRY_RUN" == "true" ]]; then
        log_warn "[DRY-RUN] File already exists: ${target_path}. Would skip."
      else
        log_warn "File already exists: ${target_path}. Skipping."
      fi
      return 1
    else
      # Interactive mode
      echo ""
      log_warn "File already exists: ${target_path}"
      echo "  What would you like to do?"
      echo "  1) Overwrite (remove existing and create symlink)"
      echo "  2) Keep existing (skip)"
      echo "  3) Abort setup"
      echo ""
      read -p "Your choice [1-3]: " choice

      case "$choice" in
        1)
          if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY-RUN] Would remove existing file: ${target_path}"
          else
            log_info "Removing existing file: ${target_path}"
            rm -f "$target_path"
          fi
          ;;
        2)
          log_info "Keeping existing file: ${target_path}"
          return 1
          ;;
        3)
          log_fatal "Setup aborted by user"
          ;;
        *)
          log_warn "Invalid choice. Keeping existing file."
          return 1
          ;;
      esac
    fi
  fi

  # Create symlink
  if [[ "$DRY_RUN" == "true" ]]; then
    log_ok "[DRY-RUN] Would create symlink: ${target_path} -> ${SCRIPT_PATH}/${script_name}"
    log_info "[DRY-RUN] Would run: ln -s \"${SCRIPT_PATH}/${script_name}\" \"$target_path\""
    log_info "[DRY-RUN] Would run: chmod +x \"$target_path\""
  else
    ln -s "${SCRIPT_PATH}/${script_name}" "$target_path"
    chmod +x "$target_path"
    log_ok "Created symlink: ${target_path} -> ${SCRIPT_PATH}/${script_name}"
  fi
}

# Parse command line arguments
POSITIONAL_ARGS=()

while [[ $# -gt 0 ]]; do
  case $1 in
    -t|--target)
      TARGET_DIR="$2"
      shift
      shift
      ;;
    -s|--silent)
      MODE="silent"
      shift
      ;;
    -n|--dry-run)
      DRY_RUN=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*|--*)
      log_error "Unknown option: $1"
      usage
      exit 1
      ;;
    *)
      POSITIONAL_ARGS+=("$1")
      shift
      ;;
  esac
done

# Validate target directory
if [[ -z "$TARGET_DIR" ]]; then
  log_error "Target directory is required"
  usage
  exit 1
fi

# Expand tilde and resolve path
TARGET_DIR="${TARGET_DIR/#\~/$HOME}"
TARGET_DIR=$(readlink -f "$TARGET_DIR" 2>/dev/null || realpath "$TARGET_DIR" 2>/dev/null || echo "$TARGET_DIR")

# Check if target directory exists
if [[ ! -d "$TARGET_DIR" ]]; then
  log_fatal "Target directory does not exist: ${TARGET_DIR}"
fi

# Check if target directory is writable
if [[ ! -w "$TARGET_DIR" ]]; then
  log_fatal "Target directory is not writable: ${TARGET_DIR}"
fi

# Check if target directory is in PATH
check_path() {
  local target_dir=$1
  local target_abs=$(readlink -f "$target_dir" 2>/dev/null || realpath "$target_dir" 2>/dev/null || echo "$target_dir")
  local path_dirs

  # Get PATH and normalize it
  IFS=':' read -ra path_dirs <<< "$PATH"

  for dir in "${path_dirs[@]}"; do
    local dir_abs=$(readlink -f "$dir" 2>/dev/null || realpath "$dir" 2>/dev/null || echo "$dir")
    if [[ "$dir_abs" == "$target_abs" ]]; then
      return 0
    fi
  done

  return 1
}

# Detect shell configuration file
detect_shell_config() {
  local shell_name
  local config_file

  if [[ -n "$ZSH_VERSION" ]]; then
    shell_name="zsh"
    if [[ -f "$HOME/.zshrc" ]]; then
      config_file="$HOME/.zshrc"
    elif [[ -f "$HOME/.zshenv" ]]; then
      config_file="$HOME/.zshenv"
    else
      config_file="$HOME/.zshrc"
    fi
  elif [[ -n "$BASH_VERSION" ]]; then
    shell_name="bash"
    if [[ -f "$HOME/.bashrc" ]]; then
      config_file="$HOME/.bashrc"
    elif [[ -f "$HOME/.bash_profile" ]]; then
      config_file="$HOME/.bash_profile"
    elif [[ -f "$HOME/.profile" ]]; then
      config_file="$HOME/.profile"
    else
      config_file="$HOME/.bashrc"
    fi
  else
    shell_name="shell"
    if [[ -f "$HOME/.profile" ]]; then
      config_file="$HOME/.profile"
    else
      config_file="$HOME/.profile"
    fi
  fi

  echo "$shell_name:$config_file"
}

# Show PATH setup instructions
show_path_instructions() {
  local target_dir=$1
  echo ""
  log_warn "Target directory is not in your PATH"
  log_info "To make the scripts available, add the following to your shell configuration:"
  echo ""

  IFS=':' read -r shell_name config_file <<< "$(detect_shell_config)"

  # Determine the export command format
  local export_cmd
  local target_display
  if [[ "$target_dir" == "$HOME"* ]]; then
    # Use ~ if it's in home directory
    target_display="${target_dir/#$HOME/~}"
    export_cmd="export PATH=\"\$PATH:$target_display\""
  else
    export_cmd="export PATH=\"\$PATH:$target_dir\""
  fi

  echo "  ${BOLD}For $shell_name:${NC}"
  echo "    Add this line to ${config_file}:"
  echo ""
  echo "    ${GREEN}$export_cmd${NC}"
  echo ""
  echo "  ${BOLD}Or run:${NC}"
  echo "    ${GREEN}echo '$export_cmd' >> ${config_file}${NC}"
  echo ""
  log_info "After adding, reload your shell configuration:"
  echo "    ${GREEN}source ${config_file}${NC}"
  echo ""
  log_info "Or start a new terminal session"
  echo ""
}

if ! check_path "$TARGET_DIR"; then
  show_path_instructions "$TARGET_DIR"
fi

log_info "Target directory: ${TARGET_DIR}"
log_info "Mode: ${MODE}"
if [[ "$DRY_RUN" == "true" ]]; then
  log_info "Dry-run mode: No changes will be made"
fi
echo ""

# Check dependencies
check_dependencies

echo ""
log_info "Creating symlinks..."

# Create symlinks for each script
success_count=0
skip_count=0
exists_count=0

for script in "${SCRIPTS[@]}"; do
  script_path="${SCRIPT_PATH}/${script}"

  if [[ ! -f "$script_path" ]]; then
    log_warn "Script not found: ${script_path}. Skipping."
    ((skip_count++))
    continue
  fi

  set +e
  create_symlink "$script" "$TARGET_DIR"
  result=$?
  set -e
  case $result in
    0)
      ((success_count++))
      ;;
    1)
      ((skip_count++))
      ;;
    2)
      ((exists_count++))
      ;;
  esac
done

echo ""
if [[ "$DRY_RUN" == "true" ]]; then
  log_ok "Dry-run complete!"
  log_info "Would create: ${success_count} symlink(s)"
  if [[ $exists_count -gt 0 ]]; then
    log_info "Already exist: ${exists_count} symlink(s)"
  fi
  if [[ $skip_count -gt 0 ]]; then
    log_info "Would skip: ${skip_count} script(s)"
  fi
  echo ""
  log_info "Run without --dry-run to apply these changes"
else
  log_ok "Setup complete!"
  log_info "Created: ${success_count} symlink(s)"
  if [[ $exists_count -gt 0 ]]; then
    log_info "Already exist: ${exists_count} symlink(s)"
  fi
  if [[ $skip_count -gt 0 ]]; then
    log_info "Skipped: ${skip_count} script(s)"
  fi
fi

