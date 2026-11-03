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
  [[ -d "$PANEL_DIR" && -f "$PANEL_DIR/artisan" ]] || {
    fail "Pterodactyl panel not found at $PANEL_DIR"
    return 1
  }
}

check_blueprint() {
  [[ -x "$BLUEPRINT_BIN" ]] || {
    fail "Blueprint CLI not found at $BLUEPRINT_BIN"
    say "Install Blueprint Framework first using its official instructions: https://blueprint.zip/"
    return 1
  }
}

pause() { printf "\nPress Enter to return to menu..."; read -r _; }

install_lily() {
  local tmp clone_dir package dest backup
  check_panel || return 1
  check_blueprint || return 1

  tmp="$(mktemp -d -t lilyhosting.XXXXXX)"
  clone_dir="$tmp/$REPO_NAME"
  package="$clone_dir/$EXTENSION_FILE"
  dest="$PANEL_DIR/$EXTENSION_FILE"

  cleanup() { rm -rf "$tmp"; }
  trap cleanup RETURN

  say "${CYAN}[1/5]${RESET} Cloning Lilyhosting repository..."
  if ! git clone --depth 1 "$REPO_URL" "$clone_dir"; then
    fail "Git clone failed. Check internet access and repository URL."
    return 1
  fi

  say "${CYAN}[2/5]${RESET} Validating Blueprint package..."
  if [[ ! -s "$package" ]]; then
    fail "Expected package $EXTENSION_FILE was not found in the repository."
    return 1
  fi
  if ! file "$package" | grep -qiE 'Zip archive|Java archive|data'; then
    warn "The package file type is unusual; Blueprint will validate it during installation."
  fi
  if command -v unzip >/dev/null 2>&1; then
    if ! unzip -tq "$package" >/dev/null 2>&1; then
      fail "The downloaded $EXTENSION_FILE is not a valid ZIP/Blueprint archive."
      return 1
    fi
  fi

  say "${CYAN}[3/5]${RESET} Moving package into Pterodactyl directory..."
  if [[ -e "$dest" ]]; then
    backup="$dest.backup.$(date +%Y%m%d-%H%M%S)"
    cp -a "$dest" "$backup"
    warn "Existing package backed up to: $backup"
  fi
  install -m 0644 "$package" "$dest"

  say "${CYAN}[4/5]${RESET} Installing Lily Theme with Blueprint..."
  cd "$PANEL_DIR"
  if ! "$BLUEPRINT_BIN" -install "$dest"; then
    fail "Blueprint reported an installation failure. Package kept at $dest for inspection."
    return 1
  fi

  say "${CYAN}[5/5]${RESET} Refreshing panel cache..."
  if id www-data >/dev/null 2>&1; then
    chown -R www-data:www-data "$PANEL_DIR/storage" "$PANEL_DIR/bootstrap/cache"
    runuser -u www-data -- php "$PANEL_DIR/artisan" optimize:clear || warn "Could not clear Laravel cache automatically."
  fi
  systemctl restart php8.3-fpm 2>/dev/null || systemctl restart php-fpm 2>/dev/null || true
  systemctl reload nginx 2>/dev/null || true
  ok "Lily Theme installation command completed."
  say "${LAVENDER}Check Blueprint in your Pterodactyl admin area to confirm the extension is listed.${RESET}"
}

remove_lily() {
  local listing
  check_panel || return 1
  check_blueprint || return 1

  say "${CYAN}[1/4]${RESET} Checking installed Lily extension..."
  cd "$PANEL_DIR"
  listing="$("$BLUEPRINT_BIN" -list 2>&1 || true)"
  if ! grep -qi "$EXTENSION_ID" <<<"$listing"; then
    warn "Blueprint list did not confirm '$EXTENSION_ID'."
    say "Blueprint output:"
    printf '%s\n' "$listing"
    say "The theme package will not be deleted because installation status is uncertain."
    return 1
  fi

  say "${YELLOW}This will uninstall the Lily Theme extension. The Pterodactyl panel and Blueprint framework will remain installed.${RESET}"
  read -r -p "Continue? [y/N]: " confirm
  [[ "$confirm" =~ ^([yY][eE][sS]|[yY])$ ]] || { warn "Cancelled."; return 0; }

  say "${CYAN}[2/4]${RESET} Uninstalling Lily Theme through Blueprint..."
  if ! "$BLUEPRINT_BIN" -remove "$EXTENSION_ID"; then
    fail "Blueprint uninstall failed. Keeping package files untouched."
    return 1
  fi

  say "${CYAN}[3/4]${RESET} Removing local Lily package files..."
  rm -f "$PANEL_DIR/$EXTENSION_FILE" "$PANEL_DIR/lily.blueprint"
  rm -rf "$PANEL_DIR/$REPO_NAME"

  say "${CYAN}[4/4]${RESET} Clearing panel cache..."
  if id www-data >/dev/null 2>&1; then
    chown -R www-data:www-data "$PANEL_DIR/storage" "$PANEL_DIR/bootstrap/cache"
    runuser -u www-data -- php "$PANEL_DIR/artisan" optimize:clear || warn "Could not clear Laravel cache automatically."
  fi
  systemctl restart php8.3-fpm 2>/dev/null || systemctl restart php-fpm 2>/dev/null || true
  systemctl reload nginx 2>/dev/null || true
  ok "Lily Theme removal completed. Blueprint framework was not removed."
}

main() {
  require_root
  while true; do
    banner
    say "${WHITE}Pterodactyl directory:${RESET} ${CYAN}$PANEL_DIR${RESET}"
    say ""
    say "${PURPLE}[1]${RESET} Install Lily Theme (Git clone + Blueprint install)"
    say "${PURPLE}[2]${RESET} Uninstall Lily Theme and remove its local package/folder"
    say "${PURPLE}[0]${RESET} Exit"
    say ""
    read -r -p "Choose an option [1/2/0]: " choice
    case "$choice" in
      1) banner; install_lily; pause ;;
      2) banner; remove_lily; pause ;;
      0) ok "Goodbye."; exit 0 ;;
      *) warn "Invalid option. Choose 1, 2, or 0."; sleep 1 ;;
    esac
  done
}

main "$@"
