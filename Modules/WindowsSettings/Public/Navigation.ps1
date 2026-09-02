# =============================================================
# Navigation & Modern Directory Inspection (eza, zoxide, tree)
# =============================================================

# Un-alias default PowerShell ls redirect
if (Test-Path "Alias:ls") {
    Remove-Item "Alias:ls" -Force -ErrorAction SilentlyContinue
}

$programFiles = if ($env:ProgramFiles) { $env:ProgramFiles } else { Join-Path ($env:SystemDrive ?? 'C:') 'Program Files' }
$coreutilsLs = Join-Path $programFiles 'coreutils\cmd\ls.cmd'
$coreutilsCat = Join-Path $programFiles 'coreutils\cmd\cat.cmd'

# Modern Directory Listing
function ls {
    if (Get-Command eza -ErrorAction SilentlyContinue) {
        & eza --icons=auto --group-directories-first @args
    } elseif (Test-Path $coreutilsLs) {
        & $coreutilsLs --color=auto @args
    } elseif (Get-Command ls.exe -ErrorAction SilentlyContinue) {
        & ls.exe --color=auto @args
    } else {
        Get-ChildItem @args
    }
}

function ll {
    if (Get-Command eza -ErrorAction SilentlyContinue) {
        & eza -la --icons=auto --git --header --group-directories-first @args
    } elseif (Test-Path $coreutilsLs) {
        & $coreutilsLs --color=auto -alFh @args
    } elseif (Get-Command ls.exe -ErrorAction SilentlyContinue) {
        & ls.exe --color=auto -alFh @args
    } else {
        Get-ChildItem -Force @args
    }
}

function la {
    if (Get-Command eza -ErrorAction SilentlyContinue) {
        & eza -a --icons=auto --group-directories-first @args
    } elseif (Test-Path $coreutilsLs) {
        & $coreutilsLs --color=auto -AFhl @args
    } elseif (Get-Command ls.exe -ErrorAction SilentlyContinue) {
        & ls.exe --color=auto -AFhl @args
    } else {
        Get-ChildItem -Force @args
    }
}

function lt {
    if (Get-Command eza -ErrorAction SilentlyContinue) {
        & eza --tree --level=2 --icons=auto @args
    } else {
        Format-PathTree @args
    }
}

# Modern Syntax-Highlighted File Inspection (bat / coreutils cat / Get-Content)
function cat {
    if (Get-Command bat -ErrorAction SilentlyContinue) {
        & bat --theme="Solarized-Dark-TrueColor" --paging=auto @args
    } elseif (Test-Path $coreutilsCat) {
        & $coreutilsCat @args
    } elseif (Get-Command cat.exe -ErrorAction SilentlyContinue) {
        & cat.exe @args
    } else {
        Get-Content @args
    }
}

function Render-TreeNode($node, $prefix) {
    $keys = [string[]]$node.Keys
    for ($i = 0; $i -lt $keys.Count; $i++) {
        $key = $keys[$i]
        $isLast = ($i -eq $keys.Count - 1)
        $connector = if ($isLast) { [char]0x2514 + [char]0x2500 + [char]0x2500 + ' ' } else { [char]0x251C + [char]0x2500 + [char]0x2500 + ' ' }
        $childPrefix = if ($isLast) { '    ' } else { [char]0x2502 + '   ' }

        $isDir = ($node[$key].Keys.Count -gt 0)
        $color = if ($isDir) {
            'Blue'
        } elseif ($key -match '\.(go|py|rs|c|cpp|h|java|md|txt|json|yml|yaml|toml|xml)$') {
            'Green'
        } elseif ($key -match '\.(exe|cmd|bat|ps1|sh)$') {
            'Red'
        } elseif ($key -match '\.(zip|tar|gz|7z|rar|iso|png|jpg|svg|mp4)$') {
            'Yellow'
        } else {
            'White'
        }

        Write-Host -NoNewline "$prefix$connector" -ForegroundColor Gray
        Write-Host "$key" -ForegroundColor $color

        if ($isDir) {
            Render-TreeNode $node[$key] "$prefix$childPrefix"
        }
    }
}

# Visual Tree Path Formatter (Native PowerShell replacement for Linux `tree --fromfile`)
function Format-PathTree {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline = $true, ValueFromRemainingArguments = $true)]
        [string[]]$Paths
    )

    begin {
        $allPaths = [System.Collections.Generic.List[string]]::new()
    }
    process {
        if ($null -ne $Paths) {
            foreach ($p in $Paths) {
                if ($p) { $allPaths.Add($p.Trim()) }
            }
        }
    }
    end {
        if ($allPaths.Count -eq 0) { return }

        $root = [ordered]@{}
        foreach ($rawPath in $allPaths) {
            $parts = $rawPath -split '[\\/]' | Where-Object { $_ -ne '' }
            $current = $root
            foreach ($part in $parts) {
                if (-not $current.Contains($part)) {
                    $current[$part] = [ordered]@{}
                }
                $current = $current[$part]
            }
        }

        Write-Host '.' -ForegroundColor Cyan
        Render-TreeNode $root ''
    }
}

# Directory Visual Search Helper (fd piped to Format-PathTree visual hierarchy)
function fs {
    if (Get-Command fd -ErrorAction SilentlyContinue) {
        fd --no-ignore-vcs @args | Format-PathTree
    } else {
        Get-ChildItem -Recurse @args | Select-Object -ExpandProperty FullName | Format-PathTree
    }
}

# Initialize Zoxide (Smart directory jumping with compiled cache)
$zoxideCache = "$HOME\.cache\powershell\zoxide_init.ps1"
if (Test-Path $zoxideCache) {
    . $zoxideCache
} elseif (Get-Command zoxide -ErrorAction SilentlyContinue) {
    $cacheDir = "$HOME\.cache\powershell"
    if (-not (Test-Path $cacheDir)) {
        New-Item -ItemType Directory -Force -Path $cacheDir | Out-Null
    }
    zoxide init powershell | Out-File -FilePath $zoxideCache -Encoding utf8 -Force
    . $zoxideCache
}
