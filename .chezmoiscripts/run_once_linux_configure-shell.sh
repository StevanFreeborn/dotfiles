#!/usr/bin/env bash
# run_once_linux_configure-shell.sh
# Configures zsh as the default shell and sets up the shell environment.
# This script runs once (unless deleted from ~/.local/share/chezmoi).

set -euo pipefail

echo "==> Configuring shell environment (Linux)..."

# --- Set zsh as default shell ---
ZSH_PATH=$(which zsh 2>/dev/null || echo "")
if [ -z "$ZSH_PATH" ]; then
    echo "  ERROR: zsh is not installed. Run the package install script first."
    exit 1
fi

CURRENT_SHELL=$(getent passwd "$USER" | cut -d: -f7)
if [ "$CURRENT_SHELL" != "$ZSH_PATH" ]; then
    echo "  Setting zsh as default shell..."
    chsh -s "$ZSH_PATH"
    echo "  Default shell set to: $ZSH_PATH"
else
    echo "  zsh is already the default shell"
fi

# --- Set up Rust (cargo) in environment ---
CARGO_ENV="$HOME/.cargo/env"
if [ -f "$CARGO_ENV" ]; then
    RUST_ZSHENV_LINE='. "$HOME/.cargo/env"'
    ZSHENV="$HOME/.zshenv"
    if ! grep -qF "$RUST_ZSHENV_LINE" "$ZSHENV" 2>/dev/null; then
        echo "$RUST_ZSHENV_LINE" >> "$ZSHENV"
        echo "  Added Rust cargo env to .zshenv"
    fi
fi

# --- Set up Go in environment ---
if [ -d "/usr/local/go" ]; then
    GO_ZSHENV_LINE='export PATH=$PATH:/usr/local/go/bin'
    ZSHENV="$HOME/.zshenv"
    if ! grep -qF "go/bin" "$ZSHENV" 2>/dev/null; then
        echo "$GO_ZSHENV_LINE" >> "$ZSHENV"
        echo "  Added Go to PATH in .zshenv"
    fi
fi

echo "==> Shell configuration complete!"
echo "    NOTE: Log out and back in (or restart your terminal) for shell changes to take effect."
