if ($host.Name -eq 'ConsoleHost') {
    if (Get-Module -ListAvailable -Name PSReadLine) {
        Import-Module PSReadLine
    }
}

if (Get-Module -ListAvailable -Name Terminal-Icons) {
    Import-Module -Name Terminal-Icons
}

if (Get-Command oh-my-posh -ErrorAction SilentlyContinue) {
    oh-my-posh init pwsh --config "~/.config/oh-my-posh/theme.omp.json" | Invoke-Expression
    oh-my-posh toggle command
}

if (Get-Module -ListAvailable -Name posh-git) {
    Import-Module posh-git
}

if ($ChocolateyProfile -and (Test-Path $ChocolateyProfile)) {
    Import-Module "$ChocolateyProfile"
}

if (Get-Command zoxide -ErrorAction SilentlyContinue) {
    Invoke-Expression (& { (zoxide init powershell | Out-String) })
}
