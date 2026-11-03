#!/usr/bin/env bash
set -Eeuo pipefail

# Lily Theme Blueprint installer / remover for Pterodactyl.
# Repository: https://github.com/therynzo/Lilyhosting

PURPLE='\033[38;5;141m'
LAVENDER='\033[38;5;183m'
WHITE='\033[1;97m'
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
RESET='\033[0m'

REPO_URL='https://github.com/therynzo/Lilyhosting.git'
REPO_NAME='Lilyhosting'
EXTENSION_FILE='lilytheme.blueprint'
EXTENSION_ID='lilytheme'
PANEL_DIR='/var/www/pterodactyl'
BLUEPRINT_BIN='/usr/local/bin/blueprint'

say()  { printf "%b\n" "$*"; }
ok()   { say "${GREEN}[+]${RESET} $*"; }
warn() { say "${YELLOW}[!]${RESET} $*"; }
fail() { say "${RED}[x]${RESET} $*" >&2; }

banner() {
  clear 2>/dev/null || true
  say "${PURPLE}╔══════════════════════════════════════════════════════════════╗${RESET}"
  say "${PURPLE}║${WHITE}                 L I L Y  T H E M E  M A N A G E R             ${PURPLE}║${RESET}"
  say "${PURPLE}║${LAVENDER}              PTERODACTYL BLUEPRINT AUTO-INSTALLER            ${PURPLE}║${RESET}"
  say "${PURPLE}╚══════════════════════════════════════════════════════════════╝${RESET}"
  say ""
}

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    fail "Run this script as root: sudo bash installing.sh"
    exit 1
  fi
}

check_panel() {
  if [[ ! -d "$PANEL_DIR" || ! -f "$PANEL_DIR/artisan" ]]; then
    fail "Pterodactyl panel not found at $PANEL_DIR"
    return 1
  fi
}

check_blueprint() {
  if [[ ! -x "$BLUEPRINT_BIN" ]]; then
    fail "Blueprint CLI not found at $BLUEPRINT_BIN"
    say "Install Blueprint Framework first: https://blueprint.zip/"
    return 1
  fi
}

refresh_panel() {
  if id www-data >/dev/null 2>&1; then
    chown -R www-data:www-data "$PANEL_DIR/storage" "$PANEL_DIR/bootstrap/cache" || warn "Could not reset Laravel cache ownership."
    runuser -u www-data -- php "$PANEL_DIR/artisan" optimize:clear || warn "Could not clear Laravel cache automatically."
  fi
  systemctl restart php8.3-fpm 2>/dev/null || systemctl restart php-fpm 2>/dev/null || warn "Could not restart PHP-FPM automatically."
  systemctl reload nginx 2>/dev/null || warn "Could not reload Nginx automatically."
}

pause() { printf "\nPress Enter to return to menu..."; read -r _; }

install_lily() {
  local tmp clone_dir repo_dest package dest backup repo_backup
  check_panel || return 1
  check_blueprint || return 1
  command -v git >/dev/null 2>&1 || { fail "Git is required. Install it with: apt-get install -y git"; return 1; }
  command -v unzip >/dev/null 2>&1 || { fail "unzip is required. Install it with: apt-get install -y unzip"; return 1; }

  tmp="$(mktemp -d -t lilyhosting.XXXXXX)"
  clone_dir="$tmp/$REPO_NAME"
  repo_dest="$PANEL_DIR/$REPO_NAME"
  dest="$PANEL_DIR/$EXTENSION_FILE"
  trap 'rm -rf -- "$tmp"' RETURN

  say "${CYAN}[1/5]${RESET} Cloning Lilyhosting repository..."
  if ! git clone --depth 1 "$REPO_URL" "$clone_dir"; then
    fail "Git clone failed. Check internet access and the repository URL."
    return 1
  fi

  package="$clone_dir/$EXTENSION_FILE"
  say "${CYAN}[2/5]${RESET} Validating Blueprint package..."
  if [[ ! -s "$package" ]]; then
    fail "The repository does not contain a non-empty $EXTENSION_FILE."
    return 1
  fi
  if ! unzip -tq "$package" >/dev/null 2>&1; then
    fail "$EXTENSION_FILE is not a valid ZIP/Blueprint archive. Nothing was installed."
    return 1
  fi

  say "${CYAN}[3/5]${RESET} Placing repository and package in the Pterodactyl directory..."
  if [[ -e "$repo_dest" ]]; then
    repo_backup="$repo_dest.backup.$(date +%Y%m%d-%H%M%S)"
    if ! mv "$repo_dest" "$repo_backup"; then
      fail "Could not back up existing $repo_dest."
      return 1
    fi
    warn "Existing repository folder backed up to $repo_backup"
  fi
  if ! mv "$clone_dir" "$repo_dest"; then
    [[ -n "${repo_backup:-}" && -e "$repo_backup" ]] && mv "$repo_backup" "$repo_dest" || true
    fail "Could not move the cloned repository into $PANEL_DIR."
    return 1
  fi
  package="$repo_dest/$EXTENSION_FILE"

  if [[ -e "$dest" ]]; then
    backup="$dest.backup.$(date +%Y%m%d-%H%M%S)"
    if ! cp -a "$dest" "$backup"; then
      fail "Could not back up the existing extension package."
      return 1
    fi
    warn "Existing package backed up to $backup"
  fi
  if ! install -m 0644 "$package" "$dest"; then
    fail "Could not copy $EXTENSION_FILE into the Pterodactyl directory."
    return 1
  fi

  say "${CYAN}[4/5]${RESET} Installing Lily Theme through the Blueprint CLI..."
  cd "$PANEL_DIR"
  # Blueprint accepts either the extension identifier or identifier.blueprint.
  if ! "$BLUEPRINT_BIN" -install "$EXTENSION_FILE"; then
    fail "Blueprint installation failed. The package and cloned repository have been kept for inspection."
    return 1
  fi

  say "${CYAN}[5/5]${RESET} Refreshing panel cache and services..."
  refresh_panel
  ok "Lily Theme installation command completed."
  say "${LAVENDER}Check Admin → Blueprint → Extensions to confirm Lily Theme is listed.${RESET}"
}

remove_lily() {
  local repo_dir remote
  check_panel || return 1
  check_blueprint || return 1

  say "${CYAN}[1/3]${RESET} Ready to ask Blueprint to uninstall '$EXTENSION_ID'."
  say "Blueprint CLI does not provide a -list command; the previous script used an invalid option."
  say "${YELLOW}This removes only the Lily Theme extension. Blueprint Framework and Pterodactyl remain installed.${RESET}"
  read -r -p "Continue with Lily Theme removal? [y/N]: " confirm
  [[ "$confirm" =~ ^([yY]|[yY][eE][sS])$ ]] || { warn "Cancelled; no files changed."; return 0; }

  say "${CYAN}[2/3]${RESET} Uninstalling Lily Theme using Blueprint..."
  cd "$PANEL_DIR"
  # Do not delete local files unless Blueprint confirms successful removal.
  if ! "$BLUEPRINT_BIN" -remove "$EXTENSION_ID"; then
    fail "Blueprint could not remove '$EXTENSION_ID'. Local package and repository files were preserved."
    say "Check the Blueprint CLI output above; do not manually delete the extension files yet."
    return 1
  fi

  say "${CYAN}[3/3]${RESET} Cleaning up Lily package files..."
  rm -f -- "$PANEL_DIR/$EXTENSION_FILE" "$PANEL_DIR/lily.blueprint"

  repo_dir="$PANEL_DIR/$REPO_NAME"
  if [[ -d "$repo_dir/.git" ]]; then
    remote="$(git -C "$repo_dir" config --get remote.origin.url 2>/dev/null || true)"
    if [[ "$remote" == "$REPO_URL" || "$remote" == 'git@github.com:therynzo/Lilyhosting.git' ]]; then
      rm -rf -- "$repo_dir"
    else
      warn "Kept $repo_dir because its Git remote is not the expected Lilyhosting repository."
    fi
  elif [[ -e "$repo_dir" ]]; then
    warn "Kept $repo_dir because it is not clearly a Lilyhosting Git clone."
  fi

  refresh_panel
  ok "Lily Theme removal completed. Blueprint Framework was not removed."
}

main() {
  require_root
  while true; do
    banner
    say "${WHITE}Pterodactyl directory:${RESET} ${CYAN}$PANEL_DIR${RESET}"
    say ""
    say "${PURPLE}[1]${RESET} Install Lily Theme (Git clone + validate + Blueprint install)"
    say "${PURPLE}[2]${RESET} Uninstall Lily Theme and clean its package/repository folder"
    say "${PURPLE}[0]${RESET} Exit"
    say ""
    read -r -p "Choose an option [1/2/0]: " choice
    case "$choice" in
      1) banner; install_lily || warn "Installation did not complete."; pause ;;
      2) banner; remove_lily || warn "Removal did not complete; files were preserved where possible."; pause ;;
      0) ok "Goodbye."; exit 0 ;;
      *) warn "Invalid option. Choose 1, 2, or 0."; sleep 1 ;;
    esac
  done
}

main "$@"
