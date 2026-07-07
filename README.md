# dotfiles

> One-stop shop to set up and sync my Windows and Linux machines.

Managed with **[chezmoi](https://www.chezmoi.io/)** — cross-platform, idempotent, with native [Bitwarden](https://bitwarden.com/) secret integration.

---

## What's managed

| Config                 | Windows path                                                         | Linux path                                             |
|------------------------|----------------------------------------------------------------------|--------------------------------------------------------|
| Git config             | `~/.gitconfig`                                                       | `~/.gitconfig`                                         |
| SSH config             | `~/.ssh/config`                                                      | `~/.ssh/config`                                        |
| Neovim                 | `~/AppData/Local/nvim/` *(external)*                                 | `~/.config/nvim/` *(external)*                         |
| VS Code                | `~/AppData/Roaming/Code/User/`                                       | `~/.config/Code/User/`                                 |
| Windows Terminal       | `~/AppData/Local/Packages/Microsoft.WindowsTerminal_.../LocalState/` | N/A                                                    |
| PowerShell profile     | `~/Documents/PowerShell/Microsoft.PowerShell_profile.ps1`            | N/A                                                    |
| Zsh config (Oh My Zsh) | N/A                                                                  | `~/.zshrc`, `~/.zshenv`                                |
| Oh My Zsh custom theme | N/A                                                                  | `~/.oh-my-zsh/custom/themes/lavender-dimmed.zsh-theme` |
| Oh My Posh theme       | `~/.config/oh-my-posh/theme.omp.json`                                | N/A (Windows only)                                     |
| WSL config             | `~/.wslconfig`                                                       | N/A                                                    |

---

## Prerequisites

Before running bootstrap, complete these **one-time manual steps**:

1. **Create a Bitwarden account** at [bitwarden.com](https://bitwarden.com)
2. **Import SSH private keys** into Bitwarden as Secure Notes (see [Storing SSH keys in Bitwarden](#storing-ssh-keys-in-bitwarden))

Everything else — installing chezmoi, Bitwarden CLI, logging in, and applying the dotfiles — is handled by the bootstrap script.

---

## Source of truth

The primary repo lives on a self-hosted Gitea server and is mirrored to GitHub:

|                     | URL                                            |
|---------------------|------------------------------------------------|
| **Primary (Gitea)** | `https://gitea.freeborn.cloud/Stevan/dotfiles` |
| **Mirror (GitHub)** | `https://github.com/StevanFreeborn/dotfiles`   |

Push changes to Gitea — GitHub is updated automatically via push mirroring.

---

## Fresh machine setup

### Windows

Open PowerShell (no admin required) and run:

```powershell
iwr -useb https://raw.githubusercontent.com/StevanFreeborn/dotfiles/main/scripts/bootstrap.ps1 | iex
```

### Linux (Ubuntu/Debian)

```bash
bash <(curl -fsLS https://raw.githubusercontent.com/StevanFreeborn/dotfiles/main/scripts/bootstrap.sh)
```

The bootstrap script will:

1. Install missing prerequisites (`curl`/`git` on Linux, or check `winget` on Windows)
2. Install Bitwarden CLI if not present
3. Install chezmoi if not present
4. Prompt for Bitwarden login/unlock (interactive — master password required)
5. Run `chezmoi init --apply` to clone and apply the full dotfiles repo

> **Primary vs. fallback repo:** The script tries the Gitea server first; if unreachable it falls back to the GitHub mirror automatically.

### Manual bootstrap (advanced)

<details>
<summary>Expand for step-by-step instructions</summary>

#### Windows

```powershell
# 1. Install chezmoi
winget install --id twpayne.chezmoi --silent --accept-package-agreements --accept-source-agreements

# 2. Log into Bitwarden CLI and unlock
winget install --id Bitwarden.CLI --silent --accept-package-agreements --accept-source-agreements
bw login
$env:BW_SESSION = bw unlock --raw

# 3. Bootstrap dotfiles
chezmoi init --apply https://gitea.freeborn.cloud/Stevan/dotfiles.git
```

#### Linux (Ubuntu/Debian)

```bash
# 1. Install chezmoi
sh -c "$(curl -fsLS get.chezmoi.io)"

# 2. Log into Bitwarden CLI and unlock
sudo snap install bw
bw login
export BW_SESSION=$(bw unlock --raw)

# 3. Bootstrap dotfiles
chezmoi init --apply https://gitea.freeborn.cloud/Stevan/dotfiles.git
```

</details>

---

## Syncing an existing machine

Pull the latest changes and apply them:

```bash
chezmoi update
```

Preview what would change before applying:

```bash
chezmoi update --dry-run
```

---

## Managing dotfiles

### Add a new file to be managed

```bash
chezmoi add ~/.some-new-config
```

### Edit a managed file

```bash
# Opens the file in your editor within the chezmoi source dir
chezmoi edit ~/.gitconfig

# Apply your edits
chezmoi apply
```

### View pending changes

```bash
chezmoi diff
```

### Push changes to Gitea

```bash
chezmoi cd
git add .
git commit -m "your message"
git push
```

### Neovim config (external repo)

Neovim config is managed as a [chezmoi external](https://www.chezmoi.io/reference/special-files-and-directories/chezmoiexternal-toml/)
pointing at [github.com/StevanFreeborn/nvim-config](https://github.com/StevanFreeborn/nvim-config).

- **To edit nvim config:** commit changes directly to the `nvim-config` repo
- **To pull latest nvim config:** `chezmoi update` (refreshes weekly automatically, or on every apply if within the refresh window)
- **External definition:** `.chezmoiexternal.toml.tmpl`

---

## Package management

### Windows

Packages are defined in [`packages/windows.json`](packages/windows.json) and installed via winget.

To add a new package:

1. Find the package ID: `winget search <name>`
2. Add it to `packages/windows.json`
3. Run `chezmoi apply` — the install script re-runs because the file hash changed

### Linux

Apt packages are listed in [`packages/linux.txt`](packages/linux.txt). Additional tools (Go, Rust, NVM, Neovim, etc.) are installed via the [`run_onchange_linux_install-packages.sh.tmpl`](.chezmoiscripts/run_onchange_linux_install-packages.sh.tmpl) script.

---

## Secret management

Secrets are managed using [Bitwarden CLI](https://bitwarden.com/help/cli/) integrated with chezmoi.

### Initial setup

```bash
# Log in (first time)
bw login

# Unlock your vault and export the session key
# Windows:
$env:BW_SESSION = bw unlock --raw

# Linux/macOS:
export BW_SESSION=$(bw unlock --raw)
```

### Storing SSH keys in Bitwarden

1. Open Bitwarden and create a **Secure Note** for each SSH private key
2. Name each note: `SSH Key - <key-filename>` (e.g. `SSH Key - stevan@freeborn.cloud`)
3. Paste the **private key content** as the note body

The setup script will read these notes and write the keys to `~/.ssh/` with correct permissions (`600`).

### Using secrets in templates

chezmoi templates can pull values from Bitwarden:

```txt
{{ (bitwarden "My Secret Item").login.password }}
{{ (bitwardenFields "My Item").custom_field.value }}
```

---

## Platform notes

### Windows + WSL

The `.wslconfig` file controls WSL2 resource limits. Edit it via:

```powershell
chezmoi edit ~/.wslconfig
chezmoi apply
```

After applying a `.wslconfig` change, restart WSL:

```powershell
wsl --shutdown
```

### Oh My Posh theme

The theme file lives at `~/.config/oh-my-posh/theme.omp.json` on Windows. The PowerShell profile references this path.

To change the theme, edit `dot_config/oh-my-posh/theme.omp.json` in the chezmoi source and apply.

---

## Troubleshooting

**`chezmoi apply` asks for Bitwarden session on every run**  
→ Set `BW_SESSION` before running chezmoi. Add it to your shell session: `export BW_SESSION=$(bw unlock --raw)`

**Package install script doesn't re-run after adding a package**  
→ The script's hash is based on the packages file content. Ensure you saved `packages/windows.json` or `packages/linux.txt` and then run `chezmoi apply`.

**Neovim complains about missing plugins on a fresh machine**  
→ Open nvim and run `:Lazy sync` to install all plugins via lazy.nvim.

**`dot_gitconfig.tmpl` prompts for name/email**  
→ These are set once and stored in `~/.config/chezmoi/chezmoi.toml`. Delete that file to re-enter them.
