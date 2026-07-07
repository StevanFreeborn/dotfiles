#!/usr/bin/env pwsh
# run_once_windows_configure-shell.ps1
# Installs PowerShell modules and configures the shell environment.
# This script runs once (unless deleted from ~/.local/share/chezmoi).

$ErrorActionPreference = "Continue"

Write-Host "==> Configuring PowerShell shell environment..." -ForegroundColor Cyan

# --- Install PowerShell modules ---
$modules = @("PSReadLine", "Terminal-Icons", "posh-git")

foreach ($module in $modules) {
    if (-not (Get-Module -ListAvailable -Name $module)) {
        Write-Host "  Installing module: $module..." -ForegroundColor Yellow
        Install-Module -Name $module -Force -Scope CurrentUser -SkipPublisherCheck -ErrorAction SilentlyContinue
        Write-Host "  Installed: $module" -ForegroundColor Green
    } else {
        Write-Host "  Module already installed: $module" -ForegroundColor DarkGray
    }
}

# --- Set PowerShell execution policy ---
$policy = Get-ExecutionPolicy -Scope CurrentUser
if ($policy -ne "RemoteSigned" -and $policy -ne "Unrestricted") {
    Write-Host "  Setting execution policy to RemoteSigned for CurrentUser..." -ForegroundColor Yellow
    Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
}

# --- Ensure profile directory exists ---
$profileDir = Split-Path $PROFILE -Parent
if (-not (Test-Path $profileDir)) {
    New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
    Write-Host "  Created profile directory: $profileDir" -ForegroundColor Green
}

Write-Host "==> Shell configuration complete!" -ForegroundColor Cyan
