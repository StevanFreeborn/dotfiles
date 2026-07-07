using namespace System.Management.Automation
using namespace System.Management.Automation.Language

$WarningPreference = "SilentlyContinue"

[console]::InputEncoding = [console]::OutputEncoding = [System.Text.UTF8Encoding]::new()

if ($host.Name -eq 'ConsoleHost') {
    Import-Module PSReadLine
}

Import-Module -Name Terminal-Icons

oh-my-posh init pwsh --config "~/.config/oh-my-posh/theme.omp.json" | Invoke-Expression
oh-my-posh toggle command

Register-ArgumentCompleter -Native -CommandName winget -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
    [Console]::InputEncoding = [Console]::OutputEncoding = $OutputEncoding = [System.Text.Utf8Encoding]::new()
    $Local:word = $wordToComplete.Replace('"', '""')
    $Local:ast = $commandAst.ToString().Replace('"', '""')
    winget complete --word="$Local:word" --commandline "$Local:ast" --position $cursorPosition | ForEach-Object {
        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
    }
}

# PowerShell parameter completion shim for the dotnet CLI
Register-ArgumentCompleter -Native -CommandName dotnet -ScriptBlock {
    param($commandName, $wordToComplete, $cursorPosition)
    dotnet complete --position $cursorPosition "$wordToComplete" | ForEach-Object {
        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
    }
}

# ---


# This is an example profile for PSReadLine.
#
# This is roughly what I use so there is some emphasis on emacs bindings,
# but most of these bindings make sense in Windows mode as well.

# Searching for commands with up/down arrow is really handy.  The
# option "moves to end" is useful if you want the cursor at the end
# of the line while cycling through history like it does w/o searching,
# without that option, the cursor will remain at the position it was
# when you used up arrow, which can be useful if you forget the exact
# string you started the search on.
Set-PSReadLineKeyHandler -Key UpArrow -Function HistorySearchBackward
Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward

# This key handler shows the entire or filtered history using Out-GridView. The
# typed text is used as the substring pattern for filtering. A selected command
# is inserted to the command line without invoking. Multiple command selection
# is supported, e.g. selected by Ctrl + Click.
Set-PSReadLineKeyHandler -Key F7 `
    -BriefDescription History `
    -LongDescription 'Show command history' `
    -ScriptBlock {
    $pattern = $null
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$pattern, [ref]$null)
    if ($pattern) {
        $pattern = [regex]::Escape($pattern)
    }

    $history = [System.Collections.ArrayList]@(
        $last = ''
        $lines = ''
        foreach ($line in [System.IO.File]::ReadLines((Get-PSReadLineOption).HistorySavePath)) {
            if ($line.EndsWith('`')) {
                $line = $line.Substring(0, $line.Length - 1)
                $lines = if ($lines) {
                    "$lines`n$line"
                }
                else {
                    $line
                }
                continue
            }

            if ($lines) {
                $line = "$lines`n$line"
                $lines = ''
            }

            if (($line -cne $last) -and (!$pattern -or ($line -match $pattern))) {
                $last = $line
                $line
            }
        }
    )
    $history.Reverse()

    $command = $history | Out-GridView -Title History -PassThru
    if ($command) {
        [Microsoft.PowerShell.PSConsoleReadLine]::RevertLine()
        [Microsoft.PowerShell.PSConsoleReadLine]::Insert(($command -join "`n"))
    }
}


# CaptureScreen is good for blog posts or email showing a transaction
# of what you did when asking for help or demonstrating a technique.
Set-PSReadLineKeyHandler -Chord 'Ctrl+d,Ctrl+c' -Function CaptureScreen

# The built-in word movement uses character delimiters, but token based word
# movement is also very useful - these are the bindings you'd use if you
# prefer the token based movements bound to the normal emacs word movement
# key bindings.
Set-PSReadLineKeyHandler -Key Alt+d -Function ShellKillWord
Set-PSReadLineKeyHandler -Key Alt+Backspace -Function ShellBackwardKillWord
Set-PSReadLineKeyHandler -Key Alt+b -Function ShellBackwardWord
Set-PSReadLineKeyHandler -Key Alt+f -Function ShellForwardWord
Set-PSReadLineKeyHandler -Key Alt+B -Function SelectShellBackwardWord
Set-PSReadLineKeyHandler -Key Alt+F -Function SelectShellForwardWord

#region Smart Insert/Delete

# The next four key handlers are designed to make entering matched quotes
# parens, and braces a nicer experience.  I'd like to include functions
# in the module that do this, but this implementation still isn't as smart
# as ReSharper, so I'm just providing it as a sample.

Set-PSReadLineKeyHandler -Key '"', "'" `
    -BriefDescription SmartInsertQuote `
    -LongDescription "Insert paired quotes if not already on a quote" `
    -ScriptBlock {
    param($key, $arg)

    $quote = $key.KeyChar

    $selectionStart = $null
    $selectionLength = $null
    [Microsoft.PowerShell.PSConsoleReadLine]::GetSelectionState([ref]$selectionStart, [ref]$selectionLength)

    $line = $null
    $cursor = $null
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)

    # If text is selected, just quote it without any smarts
    if ($selectionStart -ne -1) {
        [Microsoft.PowerShell.PSConsoleReadLine]::Replace($selectionStart, $selectionLength, $quote + $line.SubString($selectionStart, $selectionLength) + $quote)
        [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($selectionStart + $selectionLength + 2)
        return
    }

    $ast = $null
    $tokens = $null
    $parseErrors = $null
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$ast, [ref]$tokens, [ref]$parseErrors, [ref]$null)

    function FindToken {
        param($tokens, $cursor)

        foreach ($token in $tokens) {
            if ($cursor -lt $token.Extent.StartOffset) { continue }
            if ($cursor -lt $token.Extent.EndOffset) {
                $result = $token
                $token = $token -as [StringExpandableToken]
                if ($token) {
                    $nested = FindToken $token.NestedTokens $cursor
                    if ($nested) { $result = $nested }
                }

                return $result
            }
        }
        return $null
    }

    $token = FindToken $tokens $cursor

    # If we're on or inside a **quoted** string token (so not generic), we need to be smarter
    if ($token -is [StringToken] -and $token.Kind -ne [TokenKind]::Generic) {
        # If we're at the start of the string, assume we're inserting a new string
        if ($token.Extent.StartOffset -eq $cursor) {
            [Microsoft.PowerShell.PSConsoleReadLine]::Insert("$quote$quote ")
            [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($cursor + 1)
            return
        }

        # If we're at the end of the string, move over the closing quote if present.
        if ($token.Extent.EndOffset -eq ($cursor + 1) -and $line[$cursor] -eq $quote) {
            [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($cursor + 1)
            return
        }
    }

    if ($null -eq $token -or
        $token.Kind -eq [TokenKind]::RParen -or $token.Kind -eq [TokenKind]::RCurly -or $token.Kind -eq [TokenKind]::RBracket) {
        if ($line[0..$cursor].Where{ $_ -eq $quote }.Count % 2 -eq 1) {
            # Odd number of quotes before the cursor, insert a single quote
            [Microsoft.PowerShell.PSConsoleReadLine]::Insert($quote)
        }
        else {
            # Insert matching quotes, move cursor to be in between the quotes
            [Microsoft.PowerShell.PSConsoleReadLine]::Insert("$quote$quote")
            [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($cursor + 1)
        }
        return
    }

    # If cursor is at the start of a token, enclose it in quotes.
    if ($token.Extent.StartOffset -eq $cursor) {
        if ($token.Kind -eq [TokenKind]::Generic -or $token.Kind -eq [TokenKind]::Identifier -or 
            $token.Kind -eq [TokenKind]::Variable -or $token.TokenFlags.hasFlag([TokenFlags]::Keyword)) {
            $end = $token.Extent.EndOffset
            $len = $end - $cursor
            [Microsoft.PowerShell.PSConsoleReadLine]::Replace($cursor, $len, $quote + $line.SubString($cursor, $len) + $quote)
            [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($end + 2)
            return
        }
    }

    # We failed to be smart, so just insert a single quote
    [Microsoft.PowerShell.PSConsoleReadLine]::Insert($quote)
}

Set-PSReadLineKeyHandler -Key '(', '{', '[' `
    -BriefDescription InsertPairedBraces `
    -LongDescription "Insert matching braces" `
    -ScriptBlock {
    param($key, $arg)

    $closeChar = switch ($key.KeyChar) {
        <#case#> '(' { [char]')'; break }
        <#case#> '{' { [char]'}'; break }
        <#case#> '[' { [char]']'; break }
    }

    $selectionStart = $null
    $selectionLength = $null
    [Microsoft.PowerShell.PSConsoleReadLine]::GetSelectionState([ref]$selectionStart, [ref]$selectionLength)

    $line = $null
    $cursor = $null
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)
    
    if ($selectionStart -ne -1) {
        # Text is selected, wrap it in brackets
        [Microsoft.PowerShell.PSConsoleReadLine]::Replace($selectionStart, $selectionLength, $key.KeyChar + $line.SubString($selectionStart, $selectionLength) + $closeChar)
        [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($selectionStart + $selectionLength + 2)
    }
    else {
        # No text is selected, insert a pair
        [Microsoft.PowerShell.PSConsoleReadLine]::Insert("$($key.KeyChar)$closeChar")
        [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($cursor + 1)
    }
}

Set-PSReadLineKeyHandler -Key ')', ']', '}' `
    -BriefDescription SmartCloseBraces `
    -LongDescription "Insert closing brace or skip" `
    -ScriptBlock {
    param($key, $arg)

    $line = $null
    $cursor = $null
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)

    if ($line[$cursor] -eq $key.KeyChar) {
        [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($cursor + 1)
    }
    else {
        [Microsoft.PowerShell.PSConsoleReadLine]::Insert("$($key.KeyChar)")
    }
}

Set-PSReadLineKeyHandler -Key Backspace `
    -BriefDescription SmartBackspace `
    -LongDescription "Delete previous character or matching quotes/parens/braces" `
    -ScriptBlock {
    param($key, $arg)

    $line = $null
    $cursor = $null
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)

    if ($cursor -gt 0) {
        $toMatch = $null
        if ($cursor -lt $line.Length) {
            switch ($line[$cursor]) {
                <#case#> '"' { $toMatch = '"'; break }
                <#case#> "'" { $toMatch = "'"; break }
                <#case#> ')' { $toMatch = '('; break }
                <#case#> ']' { $toMatch = '['; break }
                <#case#> '}' { $toMatch = '{'; break }
            }
        }

        if ($toMatch -ne $null -and $line[$cursor - 1] -eq $toMatch) {
            [Microsoft.PowerShell.PSConsoleReadLine]::Delete($cursor - 1, 2)
        }
        else {
            [Microsoft.PowerShell.PSConsoleReadLine]::BackwardDeleteChar($key, $arg)
        }
    }
}

#endregion Smart Insert/Delete

# Sometimes you enter a command but realize you forgot to do something else first.
# This binding will let you save that command in the history so you can recall it,
# but it doesn't actually execute.  It also clears the line with RevertLine so the
# undo stack is reset - though redo will still reconstruct the command line.
Set-PSReadLineKeyHandler -Key Alt+w `
    -BriefDescription SaveInHistory `
    -LongDescription "Save current line in history but do not execute" `
    -ScriptBlock {
    param($key, $arg)

    $line = $null
    $cursor = $null
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)
    [Microsoft.PowerShell.PSConsoleReadLine]::AddToHistory($line)
    [Microsoft.PowerShell.PSConsoleReadLine]::RevertLine()
}

# Insert text from the clipboard as a here string
Set-PSReadLineKeyHandler -Key Ctrl+V `
    -BriefDescription PasteAsHereString `
    -LongDescription "Paste the clipboard text as a here string" `
    -ScriptBlock {
    param($key, $arg)

    Add-Type -Assembly PresentationCore
    if ([System.Windows.Clipboard]::ContainsText()) {
        # Get clipboard text - remove trailing spaces, convert \r\n to \n, and remove the final \n.
        $text = ([System.Windows.Clipboard]::GetText() -replace "\p{Zs}*`r?`n", "`n").TrimEnd()
        [Microsoft.PowerShell.PSConsoleReadLine]::Insert("@'`n$text`n'@")
    }
    else {
        [Microsoft.PowerShell.PSConsoleReadLine]::Ding()
    }
}

# Sometimes you want to get a property of invoke a member on what you've entered so far
# but you need parens to do that.  This binding will help by putting parens around the current selection,
# or if nothing is selected, the whole line.
Set-PSReadLineKeyHandler -Key 'Alt+(' `
    -BriefDescription ParenthesizeSelection `
    -LongDescription "Put parenthesis around the selection or entire line and move the cursor to after the closing parenthesis" `
    -ScriptBlock {
    param($key, $arg)

    $selectionStart = $null
    $selectionLength = $null
    [Microsoft.PowerShell.PSConsoleReadLine]::GetSelectionState([ref]$selectionStart, [ref]$selectionLength)

    $line = $null
    $cursor = $null
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)
    if ($selectionStart -ne -1) {
        [Microsoft.PowerShell.PSConsoleReadLine]::Replace($selectionStart, $selectionLength, '(' + $line.SubString($selectionStart, $selectionLength) + ')')
        [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($selectionStart + $selectionLength + 2)
    }
    else {
        [Microsoft.PowerShell.PSConsoleReadLine]::Replace(0, $line.Length, '(' + $line + ')')
        [Microsoft.PowerShell.PSConsoleReadLine]::EndOfLine()
    }
}

# Each time you press Alt+', this key handler will change the token
# under or before the cursor.  It will cycle through single quotes, double quotes, or
# no quotes each time it is invoked.
Set-PSReadLineKeyHandler -Key "Alt+'" `
    -BriefDescription ToggleQuoteArgument `
    -LongDescription "Toggle quotes on the argument under the cursor" `
    -ScriptBlock {
    param($key, $arg)

    $ast = $null
    $tokens = $null
    $errors = $null
    $cursor = $null
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$ast, [ref]$tokens, [ref]$errors, [ref]$cursor)

    $tokenToChange = $null
    foreach ($token in $tokens) {
        $extent = $token.Extent
        if ($extent.StartOffset -le $cursor -and $extent.EndOffset -ge $cursor) {
            $tokenToChange = $token

            # If the cursor is at the end (it's really 1 past the end) of the previous token,
            # we only want to change the previous token if there is no token under the cursor
            if ($extent.EndOffset -eq $cursor -and $foreach.MoveNext()) {
                $nextToken = $foreach.Current
                if ($nextToken.Extent.StartOffset -eq $cursor) {
                    $tokenToChange = $nextToken
                }
            }
            break
        }
    }

    if ($tokenToChange -ne $null) {
        $extent = $tokenToChange.Extent
        $tokenText = $extent.Text
        if ($tokenText[0] -eq '"' -and $tokenText[-1] -eq '"') {
            # Switch to no quotes
            $replacement = $tokenText.Substring(1, $tokenText.Length - 2)
        }
        elseif ($tokenText[0] -eq "'" -and $tokenText[-1] -eq "'") {
            # Switch to double quotes
            $replacement = '"' + $tokenText.Substring(1, $tokenText.Length - 2) + '"'
        }
        else {
            # Add single quotes
            $replacement = "'" + $tokenText + "'"
        }

        [Microsoft.PowerShell.PSConsoleReadLine]::Replace(
            $extent.StartOffset,
            $tokenText.Length,
            $replacement)
    }
}

# This example will replace any aliases on the command line with the resolved commands.
Set-PSReadLineKeyHandler -Key "Alt+%" `
    -BriefDescription ExpandAliases `
    -LongDescription "Replace all aliases with the full command" `
    -ScriptBlock {
    param($key, $arg)

    $ast = $null
    $tokens = $null
    $errors = $null
    $cursor = $null
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$ast, [ref]$tokens, [ref]$errors, [ref]$cursor)

    $startAdjustment = 0
    foreach ($token in $tokens) {
        if ($token.TokenFlags -band [TokenFlags]::CommandName) {
            $alias = $ExecutionContext.InvokeCommand.GetCommand($token.Extent.Text, 'Alias')
            if ($alias -ne $null) {
                $resolvedCommand = $alias.ResolvedCommandName
                if ($resolvedCommand -ne $null) {
                    $extent = $token.Extent
                    $length = $extent.EndOffset - $extent.StartOffset
                    [Microsoft.PowerShell.PSConsoleReadLine]::Replace(
                        $extent.StartOffset + $startAdjustment,
                        $length,
                        $resolvedCommand)

                    # Our copy of the tokens won't have been updated, so we need to
                    # adjust by the difference in length
                    $startAdjustment += ($resolvedCommand.Length - $length)
                }
            }
        }
    }
}

# F1 for help on the command line - naturally
Set-PSReadLineKeyHandler -Key F1 `
    -BriefDescription CommandHelp `
    -LongDescription "Open the help window for the current command" `
    -ScriptBlock {
    param($key, $arg)

    $ast = $null
    $tokens = $null
    $errors = $null
    $cursor = $null
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$ast, [ref]$tokens, [ref]$errors, [ref]$cursor)

    $commandAst = $ast.FindAll( {
            $node = $args[0]
            $node -is [CommandAst] -and
            $node.Extent.StartOffset -le $cursor -and
            $node.Extent.EndOffset -ge $cursor
        }, $true) | Select-Object -Last 1

    if ($commandAst -ne $null) {
        $commandName = $commandAst.GetCommandName()
        if ($commandName -ne $null) {
            $command = $ExecutionContext.InvokeCommand.GetCommand($commandName, 'All')
            if ($command -is [AliasInfo]) {
                $commandName = $command.ResolvedCommandName
            }

            if ($commandName -ne $null) {
                Get-Help $commandName -ShowWindow
            }
        }
    }
}


#
# Ctrl+Shift+j then type a key to mark the current directory.
# Ctrj+j then the same key will change back to that directory without
# needing to type cd and won't change the command line.

#
$global:PSReadLineMarks = @{}

Set-PSReadLineKeyHandler -Key Ctrl+J `
    -BriefDescription MarkDirectory `
    -LongDescription "Mark the current directory" `
    -ScriptBlock {
    param($key, $arg)

    $key = [Console]::ReadKey($true)
    $global:PSReadLineMarks[$key.KeyChar] = $pwd
}

Set-PSReadLineKeyHandler -Key Ctrl+j `
    -BriefDescription JumpDirectory `
    -LongDescription "Goto the marked directory" `
    -ScriptBlock {
    param($key, $arg)

    $key = [Console]::ReadKey()
    $dir = $global:PSReadLineMarks[$key.KeyChar]
    if ($dir) {
        cd $dir
        [Microsoft.PowerShell.PSConsoleReadLine]::InvokePrompt()
    }
}

Set-PSReadLineKeyHandler -Key Alt+j `
    -BriefDescription ShowDirectoryMarks `
    -LongDescription "Show the currently marked directories" `
    -ScriptBlock {
    param($key, $arg)

    $global:PSReadLineMarks.GetEnumerator() | % {
        [PSCustomObject]@{Key = $_.Key; Dir = $_.Value } } |
    Format-Table -AutoSize | Out-Host

    [Microsoft.PowerShell.PSConsoleReadLine]::InvokePrompt()
}

# Auto correct 'git cmt' to 'git commit'
Set-PSReadLineOption -CommandValidationHandler {
    param([CommandAst]$CommandAst)

    switch ($CommandAst.GetCommandName()) {
        'git' {
            $gitCmd = $CommandAst.CommandElements[1].Extent
            switch ($gitCmd.Text) {
                'cmt' {
                    [Microsoft.PowerShell.PSConsoleReadLine]::Replace(
                        $gitCmd.StartOffset, $gitCmd.EndOffset - $gitCmd.StartOffset, 'commit')
                }
            }
        }
    }
}

# `ForwardChar` accepts the entire suggestion text when the cursor is at the end of the line.
# This custom binding makes `RightArrow` behave similarly - accepting the next word instead of the entire suggestion text.
Set-PSReadLineKeyHandler -Key RightArrow `
    -BriefDescription ForwardCharAndAcceptNextSuggestionWord `
    -LongDescription "Move cursor one character to the right in the current editing line and accept the next word in suggestion when it's at the end of current editing line" `
    -ScriptBlock {
    param($key, $arg)

    $line = $null
    $cursor = $null
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)

    if ($cursor -lt $line.Length) {
        [Microsoft.PowerShell.PSConsoleReadLine]::ForwardChar($key, $arg)
    }
    else {
        [Microsoft.PowerShell.PSConsoleReadLine]::AcceptNextSuggestionWord($key, $arg)
    }
}

# Cycle through arguments on current line and select the text. This makes it easier to quickly change the argument if re-running a previously run command from the history
# or if using a psreadline predictor. You can also use a digit argument to specify which argument you want to select, i.e. Alt+1, Alt+a selects the first argument
# on the command line. 
Set-PSReadLineKeyHandler -Key Alt+a `
    -BriefDescription SelectCommandArguments `
    -LongDescription "Set current selection to next command argument in the command line. Use of digit argument selects argument by position" `
    -ScriptBlock {
    param($key, $arg)

    $ast = $null
    $cursor = $null
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$ast, [ref]$null, [ref]$null, [ref]$cursor)

    $asts = $ast.FindAll( {
            $args[0] -is [System.Management.Automation.Language.ExpressionAst] -and
            $args[0].Parent -is [System.Management.Automation.Language.CommandAst] -and
            $args[0].Extent.StartOffset -ne $args[0].Parent.Extent.StartOffset
        }, $true)

    if ($asts.Count -eq 0) {
        [Microsoft.PowerShell.PSConsoleReadLine]::Ding()
        return
    }
    
    $nextAst = $null

    if ($null -ne $arg) {
        $nextAst = $asts[$arg - 1]
    }
    else {
        foreach ($ast in $asts) {
            if ($ast.Extent.StartOffset -ge $cursor) {
                $nextAst = $ast
                break
            }
        } 
        
        if ($null -eq $nextAst) {
            $nextAst = $asts[0]
        }
    }

    $startOffsetAdjustment = 0
    $endOffsetAdjustment = 0

    if ($nextAst -is [System.Management.Automation.Language.StringConstantExpressionAst] -and
        $nextAst.StringConstantType -ne [System.Management.Automation.Language.StringConstantType]::BareWord) {
        $startOffsetAdjustment = 1
        $endOffsetAdjustment = 2
    }

    [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($nextAst.Extent.StartOffset + $startOffsetAdjustment)
    [Microsoft.PowerShell.PSConsoleReadLine]::SetMark($null, $null)
    [Microsoft.PowerShell.PSConsoleReadLine]::SelectForwardChar($null, ($nextAst.Extent.EndOffset - $nextAst.Extent.StartOffset) - $endOffsetAdjustment)
}


Set-PSReadLineOption -PredictionSource History
Set-PSReadLineOption -PredictionViewStyle ListView
Set-PSReadLineOption -EditMode Windows


# This is an example of a macro that you might use to execute a command.
# This will add the command to history.
Set-PSReadLineKeyHandler -Key Ctrl+Shift+b `
    -BriefDescription BuildCurrentDirectory `
    -LongDescription "Build the current directory" `
    -ScriptBlock {
    [Microsoft.PowerShell.PSConsoleReadLine]::RevertLine()
    [Microsoft.PowerShell.PSConsoleReadLine]::Insert("dotnet build")
    [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine()
}

Set-PSReadLineKeyHandler -Key Ctrl+Shift+t `
    -BriefDescription BuildCurrentDirectory `
    -LongDescription "Build the current directory" `
    -ScriptBlock {
    [Microsoft.PowerShell.PSConsoleReadLine]::RevertLine()
    [Microsoft.PowerShell.PSConsoleReadLine]::Insert("dotnet test")
    [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine()
}

Set-PSReadLineOption -Colors @{
    "Parameter" = [ConsoleColor]::DarkBlue
}

function printJSON {
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        $json
    )
    $json | ConvertFrom-Json | ConvertTo-Json -Depth 100
}

$env:PYTHONIOENCODING="utf-8"
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

Import-Module posh-git

$env:VIRTUAL_ENV_DISABLE_PROMPT=1

# Import the Chocolatey Profile that contains the necessary code to enable
# tab-completions to function for `choco`.
# Be aware that if you are missing these lines from your profile, tab completion
# for `choco` will not function.
# See https://ch0.co/tab-completion for details.
$ChocolateyProfile = "$env:ChocolateyInstall\helpers\chocolateyProfile.psm1"

if (Test-Path($ChocolateyProfile)) {
  Import-Module "$ChocolateyProfile"
}

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

$NVIM_CONFIG_PATH = "$env:LOCALAPPDATA\nvim"
$NVIM_CONFIG_DATA_PATH = "$env:LOCALAPPDATA\nvim-data"

function GotoNvimConfig {
  cd $NVIM_CONFIG_PATH
}

function GotoNvimData {
  cd $NVIM_CONFIG_DATA_PATH
}

function EditNvimConfig {
  Edit-InDirectory $NVIM_CONFIG_PATH
}

function DisableReadline {
  Set-PSReadLineOption -PredictionSource None
}

function EnableReadline {
  Set-PSReadLineOption -PredictionSource History
}

function CopyPath {
  param(
    [Parameter(Mandatory=$true)]
    [string]$File
  )
  
  $path = (Get-Item $File).FullName
  Set-Clipboard $path
}

Invoke-Expression (& { (zoxide init powershell | Out-String) })

Remove-Item alias:cd -Force
Set-Alias -Name cd -Value z

Set-Alias -Name fromjson -Value ConvertFrom-Json -Description "Alias for ConvertFrom-Json"
Set-Alias -Name tojson -Value ConvertTo-Json -Description "Alias for ConvertTo-Json"

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

New-Alias -Name catc -Value Copy-FileContent -Description "Reads file content to clipboard (cat + copy)" -Force -Scope Global

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

New-Alias -Name grep -Value Select-String -Description "Alias for Select-String" -Force -Scope Global

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