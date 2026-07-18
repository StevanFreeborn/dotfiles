$CurrentDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $PROFILE }
$ProfileDir = Join-Path -Path $CurrentDir -ChildPath "Profile"

if (Test-Path -Path $ProfileDir) {
    $ProfileScripts = Get-ChildItem -Path $ProfileDir -Filter "*.ps1" | Sort-Object Name
    
    foreach ($Script in $ProfileScripts) {
        try {
            . $Script.FullName
        }
        catch {
            Write-Warning "Failed to load profile module: $($Script.Name). Error: $($_.Exception.Message)"
        }
    }
} else {
    Write-Warning "Profile directory not found at: $ProfileDir"
}
