#!/usr/bin/env bash
# bootstrap.sh
# One-shot bootstrap for a fresh Linux (Ubuntu/Debian) machine.
# Installs curl, git, chezmoi, and Bitwarden CLI, authenticates with Bitwarden,
# then runs chezmoi init --apply to pull and apply this dotfiles repo.
#
# Usage:
#   bash <(curl -fsLS https://raw.githubusercontent.com/StevanFreeborn/dotfiles/main/scripts/bootstrap.sh)

set -euo pipefail

DOTFILES_REPO="https://gitea.freeborn.cloud/Stevan/dotfiles.git"
DOTFILES_REPO_FALLBACK="StevanFreeborn/dotfiles"

step()  { echo -e "\n\033[0;36m==> $*\033[0m"; }
ok()    { echo -e "    \033[0;32m$*\033[0m"; }
skip()  { echo -e "    \033[0;90m$*\033[0m"; }
err()   { echo -e "    \033[0;31mERROR: $*\033[0m" >&2; exit 1; }

# --- Ensure running on a supported distro ---
if ! command -v apt-get &>/dev/null; then
    err "This script requires apt-get (Ubuntu/Debian). Adjust for your distro."
fi

# --- Install curl and git ---
step "Ensuring curl and git are installed..."
missing=()
command -v curl &>/dev/null || missing+=("curl")
command -v git  &>/dev/null || missing+=("git")

if [ ${#missing[@]} -gt 0 ]; then
    sudo apt-get update -qq
    sudo apt-get install -y "${missing[@]}"
    ok "Installed: ${missing[*]}"
else
    skip "curl and git already present."
fi

# --- Install Bitwarden CLI ---
step "Checking Bitwarden CLI..."
if BW_VERSION=$(bw --version 2>/dev/null); then
    skip "bw already installed ($BW_VERSION)."
else
    # Remove broken snap installation if present
    if command -v snap &>/dev/null && snap list bw &>/dev/null 2>&1; then
        echo "    Removing broken snap installation..."
        sudo snap remove bw
    fi

    step "Downloading Bitwarden CLI binary..."
    BW_VERSION=$(curl -fsLS "https://api.github.com/repos/bitwarden/clients/releases?per_page=20" \
        | grep '"tag_name"' | grep cli | head -1 | sed 's/.*"cli-v\([^"]*\)".*/\1/' || echo "")
    if [ -z "$BW_VERSION" ]; then
        err "Could not determine latest Bitwarden CLI version. Install bw manually and re-run."
    fi
    TMP_ZIP=$(mktemp /tmp/bw-XXXXXX.zip)
    curl -fsLS "https://github.com/bitwarden/clients/releases/download/cli-v${BW_VERSION}/bw-linux-${BW_VERSION}.zip" \
        -o "$TMP_ZIP"
    sudo unzip -o "$TMP_ZIP" -d /usr/local/bin/ bw
    sudo chmod +x /usr/local/bin/bw
    rm -f "$TMP_ZIP"
    ok "bw ${BW_VERSION} installed to /usr/local/bin/bw."
fi

# --- Install chezmoi ---
step "Checking chezmoi..."
if command -v chezmoi &>/dev/null; then
    skip "chezmoi already installed ($(chezmoi --version))."
else
    step "Installing chezmoi..."
    sh -c "$(curl -fsLS get.chezmoi.io)" -- -b "$HOME/.local/bin"
    export PATH="$HOME/.local/bin:$PATH"
    ok "chezmoi installed."
fi

# --- Bitwarden login ---
step "Checking Bitwarden login status..."
BW_STATUS=$(bw status 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('status','unauthenticated'))" 2>/dev/null || echo "unauthenticated")

if [ "$BW_STATUS" != "unlocked" ]; then
    if [ "$BW_STATUS" = "unauthenticated" ]; then
        step "Logging into Bitwarden (enter your email and master password)..."
        bw login || err "Bitwarden login failed. Check your credentials and re-run."
    else
        skip "Already logged in."
    fi

    step "Unlocking Bitwarden vault..."
    export BW_SESSION
    BW_SESSION=$(bw unlock --raw) || err "Failed to unlock Bitwarden vault."
    ok "Vault unlocked. BW_SESSION is set."
else
    skip "Bitwarden vault already unlocked."
    if [ -z "${BW_SESSION:-}" ]; then
        step "Refreshing BW_SESSION..."
        export BW_SESSION
        BW_SESSION=$(bw unlock --raw)
    fi
fi

# --- Bootstrap dotfiles ---
step "Bootstrapping dotfiles with chezmoi..."

CHEZMOI_SOURCE_DIR="$HOME/.local/share/chezmoi"

if [ -d "$CHEZMOI_SOURCE_DIR/.git" ]; then
    # Already initialized — pull latest and apply
    step "chezmoi already initialized, pulling latest changes..."
    chezmoi update || err "chezmoi update failed."
    ok "Dotfiles updated and applied."
else
    # Fresh init — try Gitea first, fall back to GitHub mirror
    if chezmoi init --apply "$DOTFILES_REPO" 2>/dev/null; then
        ok "Dotfiles applied from Gitea."
    else
        echo "    Primary Gitea repo unreachable, trying GitHub mirror..."
        chezmoi init --apply "$DOTFILES_REPO_FALLBACK" \
            || err "chezmoi init failed. Check the repo URL and your network connection."
        ok "Dotfiles applied from GitHub mirror."
    fi
fi

echo ""
echo -e "\033[0;32mBootstrap complete!\033[0m"
echo ""
echo "IMPORTANT: Open a new terminal (or run: exec zsh) before continuing."
echo "  ~/.local/bin is now in your PATH via ~/.zshenv, but your current"
echo "  shell session won't see it until you start a new one."
echo ""
echo "  chezmoi is at: $HOME/.local/bin/chezmoi"
echo ""
echo "Next steps:"
echo "  1. Open a new terminal"
echo "  2. Run: chezmoi update   at any time to sync the latest changes"
