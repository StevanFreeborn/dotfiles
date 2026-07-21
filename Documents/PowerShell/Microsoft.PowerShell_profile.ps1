$CurrentDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $PROFILE }
$ProfileDir = Join-Path -Path $CurrentDir -ChildPath "Profile"

if (Test-Path -Path $ProfileDir) {
    $mutexName = "Global\PowerShellProfileInit"
    $mutex = [System.Threading.Mutex]::new($false, $mutexName)
    $acquired = $false

    try {
        $acquired = $mutex.WaitOne(10000)
        if ($acquired) {
            $ProfileScripts = Get-ChildItem -Path $ProfileDir -Filter "*.ps1" | Sort-Object Name
            foreach ($Script in $ProfileScripts) {
                try {
                    . $Script.FullName
                }
                catch {
                    Write-Warning "Failed to load profile module: $($Script.Name). Error: $($_.Exception.Message)"
                }
            }
        }
        else {
            Write-Warning "Profile initialization lock timed out — another terminal may be loading."
        }
    }
    finally {
        if ($acquired) { $mutex.ReleaseMutex() }
        $mutex.Dispose()
    }
}
else {
    Write-Warning "Profile directory not found at: $ProfileDir"
}
