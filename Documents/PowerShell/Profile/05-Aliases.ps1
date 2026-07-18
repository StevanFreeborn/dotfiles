# CD to Zoxide
if (Get-Command z -ErrorAction SilentlyContinue) {
    Remove-Item alias:cd -Force -ErrorAction SilentlyContinue
    Set-Alias -Name cd -Value z
}

Set-Alias -Name fromjson -Value ConvertFrom-Json -Description "Alias for ConvertFrom-Json"
Set-Alias -Name tojson -Value ConvertTo-Json -Description "Alias for ConvertTo-Json"

# Redundant aliases removed from functions.ps1 and grouped here:
New-Alias -Name catc -Value Copy-FileContent -Description "Reads file content to clipboard (cat + copy)" -Force -Scope Global
New-Alias -Name grep -Value Select-String -Description "Alias for Select-String" -Force -Scope Global

# Shorthand & Navigation functions
function Edit-InDirectory {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Directory,
            
        [Parameter(ValueFromRemainingArguments=$true)]
        [string[]]$FilePath
    )
        
    $originalLocation = Get-Location
        
    try {
        Set-Location $Directory
            
        if ($FilePath) {
            nvim $FilePath
        } else {
            nvim
        }
    }
    finally {
        Set-Location $originalLocation
    }
}

function GotoNvimConfig {
    cd $NVIM_CONFIG_PATH
}

function GotoNvimData {
    cd $NVIM_CONFIG_DATA_PATH
}

function EditNvimConfig {
    Edit-InDirectory $NVIM_CONFIG_PATH
}

function printJSON {
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        $json
    )
    $json | ConvertFrom-Json | ConvertTo-Json -Depth 100
}

function fuck {
    $history = (Get-History -Count 1).CommandLine;
    if (-not [string]::IsNullOrWhiteSpace($history)) {
        $fuck = $(thefuck $args $history);
        if (-not [string]::IsNullOrWhiteSpace($fuck)) {
            if ($fuck.StartsWith("echo")) { $fuck = $fuck.Substring(5); }
            else { iex "$fuck"; }
        }
    }
    [Console]::ResetColor() 
}

function CopyPath {
    param(
        [Parameter(Mandatory=$true)]
        [string]$File
    )
    
    $path = (Get-Item $File).FullName
    Set-Clipboard $path
}
