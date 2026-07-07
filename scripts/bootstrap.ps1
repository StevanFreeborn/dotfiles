#!/usr/bin/env pwsh
# bootstrap.ps1
# One-shot bootstrap for a fresh Windows machine.
# Installs chezmoi and Bitwarden CLI, authenticates with Bitwarden,
# then runs chezmoi init --apply to pull and apply this dotfiles repo.
#
# Usage (run from an elevated or standard PowerShell prompt):
#   iwr -useb https://raw.githubusercontent.com/StevanFreeborn/dotfiles/main/scripts/bootstrap.ps1 | iex

$ErrorActionPreference = "Stop"

$DOTFILES_REPO = "https://gitea.freeborn.cloud/Stevan/dotfiles.git"
$DOTFILES_REPO_FALLBACK = "StevanFreeborn/dotfiles"

function Write-Step($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host "    $msg" -ForegroundColor Green }
function Write-Skip($msg) { Write-Host "    $msg" -ForegroundColor DarkGray }
function Write-Err($msg)  { Write-Host "    ERROR: $msg" -ForegroundColor Red }

# --- Check winget ---
Write-Step "Checking winget..."
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Err "winget not found. Install App Installer from the Microsoft Store and re-run."
    exit 1
}
Write-Ok "winget is available."

# --- Helper: winget install if not present ---
function Install-WingetPackage($id, $name) {
    if (Get-Command $name -ErrorAction SilentlyContinue) {
        Write-Skip "$name already installed, skipping."
        return
    }
    Write-Step "Installing $name ($id) via winget..."
    winget install --id $id --silent --accept-package-agreements --accept-source-agreements
    # Refresh PATH so the new binary is usable in this session
    $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("PATH", "User")
    Write-Ok "$name installed."
}

# --- Install Bitwarden CLI ---
Install-WingetPackage "Bitwarden.CLI" "bw"

# --- Install chezmoi ---
Install-WingetPackage "twpayne.chezmoi" "chezmoi"

# --- Bitwarden login ---
Write-Step "Checking Bitwarden login status..."
$bwStatus = (bw status 2>$null | ConvertFrom-Json -ErrorAction SilentlyContinue).status

if ($bwStatus -ne "unlocked") {
    if ($bwStatus -ne "unauthenticated" -and $null -ne $bwStatus) {
        Write-Skip "Already logged in, skipping login."
    } else {
        Write-Step "Logging into Bitwarden (enter your email and master password)..."
        bw login
        if ($LASTEXITCODE -ne 0) {
            Write-Err "Bitwarden login failed. Please check your credentials and re-run."
            exit 1
        }
    }

    Write-Step "Unlocking Bitwarden vault..."
    $env:BW_SESSION = bw unlock --raw
    if (-not $env:BW_SESSION) {
        Write-Err "Failed to unlock Bitwarden vault. Re-run the script and try again."
        exit 1
    }
    Write-Ok "Vault unlocked. BW_SESSION is set."
} else {
    Write-Skip "Bitwarden vault already unlocked."
    if (-not $env:BW_SESSION) {
        Write-Step "Refreshing BW_SESSION..."
        $env:BW_SESSION = bw unlock --raw
    }
}

# --- Bootstrap dotfiles ---
Write-Step "Bootstrapping dotfiles with chezmoi..."

$chezmoiSourceDir = Join-Path $env:USERPROFILE ".local\share\chezmoi"

if (Test-Path (Join-Path $chezmoiSourceDir ".git")) {
    # Already initialized — pull latest and apply
    Write-Step "chezmoi already initialized, pulling latest changes..."
    chezmoi update
    if ($LASTEXITCODE -ne 0) {
        Write-Err "chezmoi update failed."
        exit 1
    }
    Write-Ok "Dotfiles updated and applied."
} else {
    # Fresh init — try Gitea first, fall back to GitHub mirror
    $applied = $false
    try {
        chezmoi init --apply $DOTFILES_REPO
        $applied = $LASTEXITCODE -eq 0
    } catch {
        $applied = $false
    }

    if (-not $applied) {
        Write-Host "    Primary Gitea repo unreachable, trying GitHub mirror..." -ForegroundColor Yellow
        chezmoi init --apply $DOTFILES_REPO_FALLBACK
        if ($LASTEXITCODE -ne 0) {
            Write-Err "chezmoi init failed. Check the repo URL and your network connection."
            exit 1
        }
    }
}

Write-Host ""
Write-Host "Bootstrap complete!" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  - Restart your terminal to pick up the new PowerShell profile."
Write-Host "  - Run 'chezmoi update' at any time to sync the latest changes."
Write-Host "  - To add a new machine later, re-run this script."
