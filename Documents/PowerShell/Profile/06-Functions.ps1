#region Security Tools

function Generate-JwtSecret {
    <#
    .SYNOPSIS
    Generates a secure, Base64-encoded random string suitable for a JWT secret (HS256).

    .DESCRIPTION
    This function creates a cryptographically strong, random byte array of a specified length
    (defaulting to 32 bytes/256 bits) and then encodes it to a Base64 string.
    This is ideal for use as a symmetric key in JWTs (e.g., for HS256 algorithm).

    .PARAMETER Length
    Specifies the length of the random byte array in bytes.
    A length of 32 bytes (256 bits) is generally recommended for HS256.
    Defaults to 32 if not specified.

    .EXAMPLE
    Generate-JwtSecret

    This will generate a 32-byte (256-bit) Base64-encoded JWT secret.

    .EXAMPLE
    Generate-JwtSecret -Length 64

    This will generate a 64-byte (512-bit) Base64-encoded JWT secret.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position=0)]
        [int]$Length = 32
    )

    try {
        $bytes = New-Object byte[] $Length
        [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
        [Convert]::ToBase64String($bytes)
    }
    catch {
        Write-Error "Failed to generate JWT secret: $($_.Exception.Message)"
        return $null
    }
}

#endregion

#region File Management

function Copy-FileContent {
    <#
    .SYNOPSIS
        Copies the content of a specified file to the clipboard.

    .DESCRIPTION
        The Copy-FileContent function reads the entire content of a specified text file
        and places that content onto the system clipboard using Set-Clipboard.
        This function can be invoked using its alias 'catc'.

        The function is designed to be silent in terms of explicit success messages.
        If an error occurs (e.g., file not found, permission issues, clipboard error),
        it will throw a terminating error. This allows the calling script or user
        to handle the error using standard PowerShell try/catch blocks or by checking
        the $? automatic variable.

    .PARAMETER Path
        Specifies the path to the file whose content will be copied to the clipboard.
        This parameter is mandatory. It accepts pipeline input.

    .EXAMPLE
        PS C:\> Copy-FileContent -Path "C:\Users\Me\Documents\MyNotes.txt"
        # Copies the content of MyNotes.txt to the clipboard.
        # If successful, $? will be $true. If an error occurs, it will be $false
        # and an error record will be generated.

    .EXAMPLE
        PS C:\> catc "C:\Logs\important.log"
        # Uses the alias 'catc' to copy the content of important.log to the clipboard.

    .EXAMPLE
        PS C:\> try {
        PS C:\>     catc "C:\path\to\nonexistentfile.txt"
        PS C:\>     Write-Host "File content copied successfully."
        PS C:\> }
        PS C:\> catch {
        PS C:\>     Write-Error "Operation failed: $($_.Exception.Message)"
        PS C:\>     # A calling script could use 'exit 1' here if needed
        PS C:\> }
        # This example shows how to catch and handle errors from the function.

    .EXAMPLE
        PS C:\> "C:\Temp\data.log" | catc
        PS C:\> if ($?) {
        PS C:\>     # Optional: Perform action on success, though the function is silent.
        PS C:\> } else {
        PS C:\>     Write-Warning "catc command failed for data.log."
        PS C:\> }
        # Checks the success status after execution.

    .OUTPUTS
        None. This function does not output any objects to the pipeline. It interacts
        with the clipboard. On error, it writes an error record to the error stream.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, Position=0, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [string]$Path
    )

    process {
        try {
            if (-not (Test-Path -Path $Path -PathType Leaf)) {
                throw "File not found or not a file: '$Path'"
            }

            Get-Content -Path $Path -Raw -ErrorAction Stop | Set-Clipboard -ErrorAction Stop
        }
        catch {
            throw
        }
    }
}

function Move-ZipsAndCleanup {
    <#
    .SYNOPSIS
    Moves all .zip files from subdirectories to the root directory and removes empty subdirectories.
    
    .DESCRIPTION
    This function recursively searches through all subdirectories of the specified path,
    moves all .zip files to the root directory, and then removes the leftover subdirectories.
    If naming conflicts occur, files are automatically renamed with a counter suffix.
    
    .PARAMETER Path
    The root directory path to process. Defaults to current directory if not specified.
    
    .EXAMPLE
    Move-ZipsAndCleanup -Path "C:\MyFolder"
    
    .EXAMPLE
    Move-ZipsAndCleanup -Path "16298879069"
    
    .EXAMPLE
    Move-ZipsAndCleanup -Path "." -WhatIf
    #>
    
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Position = 0)]
        [string]$Path = "."
    )
    
    # Resolve the full path
    $ResolvedPath = Resolve-Path $Path -ErrorAction SilentlyContinue
    if (-not $ResolvedPath) {
        Write-Error "Path '$Path' does not exist."
        return
    }
    
    $RootPath = $ResolvedPath.Path
    Write-Host "Processing directory: $RootPath" -ForegroundColor Green
    
    # Step 1: Move all .zip files to root directory
    Write-Host "Step 1: Moving .zip files to root directory..." -ForegroundColor Yellow
    
    $ZipFiles = Get-ChildItem -Path $RootPath -Recurse -Filter "*.zip" | Where-Object { $_.Directory.FullName -ne $RootPath }
    
    if ($ZipFiles.Count -eq 0) {
        Write-Host "No .zip files found in subdirectories." -ForegroundColor Cyan
    } else {
        Write-Host "Found $($ZipFiles.Count) .zip file(s) to move." -ForegroundColor Cyan
        
        foreach ($ZipFile in $ZipFiles) {
            $DestinationPath = Join-Path $RootPath $ZipFile.Name
            
            # Handle naming conflicts
            if (Test-Path $DestinationPath) {
                $Counter = 1
                do {
                    $NewName = $ZipFile.BaseName + "_$Counter" + $ZipFile.Extension
                    $DestinationPath = Join-Path $RootPath $NewName
                    $Counter++
                } while (Test-Path $DestinationPath)
                
                Write-Host "  Renaming due to conflict: $($ZipFile.Name) -> $(Split-Path $DestinationPath -Leaf)" -ForegroundColor Magenta
            }
            
            if ($PSCmdlet.ShouldProcess($ZipFile.FullName, "Move to $DestinationPath")) {
                try {
                    Move-Item -Path $ZipFile.FullName -Destination $DestinationPath -Force
                    Write-Host "  Moved: $(Split-Path $DestinationPath -Leaf)" -ForegroundColor Green
                } catch {
                    Write-Error "  Failed to move $($ZipFile.Name): $($_.Exception.Message)"
                }
            }
        }
    }
    
    # Step 2: Remove leftover subdirectories
    Write-Host "Step 2: Removing leftover subdirectories..." -ForegroundColor Yellow
    
    $Subdirectories = Get-ChildItem -Path $RootPath -Directory
    
    if ($Subdirectories.Count -eq 0) {
        Write-Host "No subdirectories found to remove." -ForegroundColor Cyan
    } else {
        Write-Host "Found $($Subdirectories.Count) subdirectorie(s) to remove." -ForegroundColor Cyan
        
        foreach ($Directory in $Subdirectories) {
            if ($PSCmdlet.ShouldProcess($Directory.FullName, "Remove directory")) {
                try {
                    Remove-Item -Path $Directory.FullName -Recurse -Force
                    Write-Host "  Removed: $($Directory.Name)" -ForegroundColor Green
                } catch {
                    Write-Error "  Failed to remove $($Directory.Name): $($_.Exception.Message)"
                }
            }
        }
    }
    
    Write-Host "Operation completed!" -ForegroundColor Green
}

#endregion

#region Media & Entertainment

function BRB {
    $steam1Lines = @'
    ( ( 
     ) )
'@ -split [System.Environment]::NewLine
    
    $steam2Lines = @'
     ) )
    ( ( 
'@ -split [System.Environment]::NewLine
    
    $steamFrames = @($steam1Lines, $steam2Lines)
    $frameIndex = 0
 
    $cupLines = @'
  ........
  |      |]
  \      /    
   `----' 
'@ -split [System.Environment]::NewLine
 
    $brbMessage = "BRB WENT TO GET COFFEE"
 
    try {
        [System.Console]::CursorVisible = $false
 
        Clear-Host
 
        $topPosition = [System.Console]::CursorTop
 
        while (-not [Console]::KeyAvailable) {
            [System.Console]::SetCursorPosition(0, $topPosition)
            
            $currentSteamLines = $steamFrames[$frameIndex]
            foreach ($line in $currentSteamLines) {
                Write-Host $line -ForegroundColor Gray
            }
            
            Write-Host $cupLines[0] -ForegroundColor Red
            
            Write-Host -NoNewline $cupLines[1] -ForegroundColor Red
            Write-Host "   $brbMessage" # Default color
 
            Write-Host $cupLines[2] -ForegroundColor Red
 
            Write-Host $cupLines[3] -ForegroundColor Red
            
            $frameIndex = ($frameIndex + 1) % $steamFrames.Length
            
            Start-Sleep -Milliseconds 1000
        }
    }
    finally {
        while ([Console]::KeyAvailable) {
            [void][Console]::ReadKey($true)
        }
        
        [System.Console]::CursorVisible = $true
        
        Clear-Host
    }
}

function Get-YouTubeVideo {
    <#
    .SYNOPSIS
    Downloads the best quality video and audio from a YouTube URL and merges them.
    
    .DESCRIPTION
    Requires yt-dlp and ffmpeg to be installed and available in your system PATH.
    
    .PARAMETER Url
    The URL of the YouTube video.
    
    .PARAMETER OutputPath
    Optional. The exact path and filename to save the video (e.g., "C:\Videos\MyVideo.mp4"). 
    If not specified, it saves to the current directory using the video's title.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [string]$Url,

        [Parameter(Mandatory=$false, Position=1)]
        [string]$OutputPath
    )

    # Verify dependencies are installed
    if (-not (Get-Command "yt-dlp" -ErrorAction SilentlyContinue)) {
        Write-Warning "yt-dlp is missing. Please install it (e.g., 'winget install yt-dlp') and restart your terminal."
        return
    }

    if (-not (Get-Command "ffmpeg" -ErrorAction SilentlyContinue)) {
        Write-Warning "ffmpeg is missing. It is required to merge the audio and video. Please install it (e.g., 'winget install ffmpeg') and restart your terminal."
        return
    }

    # Set up arguments for best video (mp4) and best audio (m4a), merged into an mp4
    $Arguments = @(
        "-f", "bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best",
        "--merge-output-format", "mp4"
    )

    # Handle output naming
    if ($OutputPath) {
        $Arguments += "-o"
        $Arguments += $OutputPath
    } else {
        $Arguments += "-o"
        $Arguments += "%(title)s.%(ext)s"
    }

    $Arguments += $Url

    Write-Host "Starting download and merge process..." -ForegroundColor Cyan
    
    # Execute yt-dlp with the arguments
    & yt-dlp @Arguments
}

#endregion
