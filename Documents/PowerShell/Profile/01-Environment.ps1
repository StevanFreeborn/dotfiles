using namespace System.Management.Automation
using namespace System.Management.Automation.Language

$NVIM_CONFIG_PATH = "$env:LOCALAPPDATA\nvim"
$NVIM_CONFIG_DATA_PATH = "$env:LOCALAPPDATA\nvim-data"
$ChocolateyProfile = "$env:ChocolateyInstall\helpers\chocolateyProfile.psm1"
$env:PYTHONIOENCODING="utf-8"
$env:VIRTUAL_ENV_DISABLE_PROMPT=1
$env:EDITOR="nvim"

$WarningPreference = "SilentlyContinue"

[console]::InputEncoding = [console]::OutputEncoding = [System.Text.UTF8Encoding]::new()

function Add-UserPath {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path
    )

    if (-not (Test-Path -Path $Path)) {
        Write-Warning "The path '$Path' does not exist. Skipping."
        return
    }

    $currentPath = [Environment]::GetEnvironmentVariable("Path", "User")
    
    # Split the path into an array to check for exact matches
    $pathArray = $currentPath -split ";"

    if ($pathArray -notcontains $Path) {
        $newPath = "$currentPath;$Path".TrimStart(';')
        [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
        Write-Host "Successfully added '$Path' to the User Path." -ForegroundColor Cyan
    } else {
        Write-Host "Path already exists in the User environment variable." -ForegroundColor Yellow
    }
}
