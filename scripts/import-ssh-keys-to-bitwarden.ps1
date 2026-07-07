#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Imports SSH private keys from ~/.ssh into Bitwarden as Secure Notes.

.DESCRIPTION
    Creates a Bitwarden Secure Note for each private SSH key using the naming
    convention expected by the dotfiles setup script:

        "SSH Key - <filename>"

    e.g. "SSH Key - zenbook_tinker", "SSH Key - stevan@freeborn.cloud"

    Public keys (.pub files) and non-key files (config, known_hosts) are skipped.

    Requires the Bitwarden CLI (bw) to be installed and your vault to be unlocked:

        bw login                              # first time
        $env:BW_SESSION = bw unlock --raw    # each session

.EXAMPLE
    # Unlock Bitwarden, then run the script
    $env:BW_SESSION = bw unlock --raw
    .\import-ssh-keys-to-bitwarden.ps1

.EXAMPLE
    # Dry-run: see what would be imported without creating anything
    .\import-ssh-keys-to-bitwarden.ps1 -WhatIf
#>

[CmdletBinding(SupportsShouldProcess)]
param (
    [string]$SshDir = (Join-Path $env:USERPROFILE ".ssh")
)

$ErrorActionPreference = "Stop"

# --- Preflight checks ---

if (-not (Get-Command bw -ErrorAction SilentlyContinue)) {
    Write-Error "Bitwarden CLI (bw) not found. Install it with: winget install Bitwarden.CLI"
    exit 1
}

if (-not $env:BW_SESSION) {
    Write-Error "BW_SESSION is not set. Unlock your vault first:`n  `$env:BW_SESSION = bw unlock --raw"
    exit 1
}

$vaultStatus = bw status 2>$null | ConvertFrom-Json
if ($vaultStatus.status -ne "unlocked") {
    Write-Error "Bitwarden vault is not unlocked. Run: `$env:BW_SESSION = bw unlock --raw"
    exit 1
}

if (-not (Test-Path $SshDir)) {
    Write-Error "SSH directory not found: $SshDir"
    exit 1
}

# --- Identify private keys ---

$skipNames = @("config", "known_hosts", "known_hosts.old", "authorized_keys")

$privateKeys = Get-ChildItem $SshDir -File | Where-Object {
    $_.Extension -ne ".pub" -and $_.Name -notin $skipNames
}

if ($privateKeys.Count -eq 0) {
    Write-Host "No private keys found in $SshDir" -ForegroundColor Yellow
    exit 0
}

Write-Host "Found $($privateKeys.Count) private key(s) in $SshDir`n" -ForegroundColor Cyan

# --- Get existing Bitwarden items to avoid duplicates ---

Write-Host "Fetching existing Bitwarden items..." -ForegroundColor DarkGray
$existingItems = bw list items 2>$null | ConvertFrom-Json
$existingNames = $existingItems | ForEach-Object { $_.name }

# --- Import each key ---

$imported = 0
$skipped  = 0
$failed   = 0

foreach ($keyFile in $privateKeys) {
    $itemName = "SSH Key - $($keyFile.Name)"

    Write-Host "  $($keyFile.Name)" -NoNewline

    # Check for duplicate
    if ($existingNames -contains $itemName) {
        Write-Host " — already in Bitwarden, skipping" -ForegroundColor DarkGray
        $skipped++
        continue
    }

    if ($PSCmdlet.ShouldProcess($itemName, "Create Bitwarden Secure Note")) {
        try {
            $keyContent = Get-Content $keyFile.FullName -Raw -ErrorAction Stop

            # Build Bitwarden Secure Note JSON
            $item = [ordered]@{
                organizationId = $null
                collectionIds  = @()
                folderId       = $null
                type           = 2        # 2 = Secure Note
                name           = $itemName
                notes          = $keyContent
                favorite       = $false
                secureNote     = @{ type = 0 }
                reprompt       = 0
            }

            $json    = $item | ConvertTo-Json -Depth 5 -Compress
            $encoded = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($json))

            $result = bw create item $encoded 2>&1
            if ($LASTEXITCODE -ne 0) {
                throw $result
            }

            Write-Host " — imported" -ForegroundColor Green
            $imported++
        }
        catch {
            Write-Host " — FAILED: $_" -ForegroundColor Red
            $failed++
        }
    }
}

# --- Summary ---

Write-Host ""
Write-Host "Done: $imported imported, $skipped already existed, $failed failed" -ForegroundColor Cyan

if ($imported -gt 0) {
    Write-Host ""
    Write-Host "Syncing vault..." -ForegroundColor DarkGray
    bw sync 2>$null | Out-Null
    Write-Host "Vault synced." -ForegroundColor DarkGray
}
