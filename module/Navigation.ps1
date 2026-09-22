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

# Helpers for standard directory listing fallback
function Invoke-LsStandard {
    if (Test-Path $coreutilsLs) {
        & $coreutilsLs --color=auto @args
    } elseif (Get-Command ls.exe -ErrorAction SilentlyContinue) {
        & ls.exe --color=auto @args
    } else {
        Get-ChildItem @args
    }
}

function Invoke-LlStandard {
    if (Test-Path $coreutilsLs) {
        & $coreutilsLs --color=auto -alF @args
    } elseif (Get-Command ls.exe -ErrorAction SilentlyContinue) {
        & ls.exe --color=auto -alF @args
    } else {
        Get-ChildItem -Force @args
    }
}

# Standard Directory Listing (GNU coreutils ls defaults matching home-settings)
function ls { Invoke-LsStandard @args }
function ll { Invoke-LlStandard @args }

function la {
    if (Test-Path $coreutilsLs) {
        & $coreutilsLs --color=auto -A @args
    } elseif (Get-Command ls.exe -ErrorAction SilentlyContinue) {
        & ls.exe --color=auto -A @args
    } else {
        Get-ChildItem -Force @args
    }
}

function l {
    if (Test-Path $coreutilsLs) {
        & $coreutilsLs --color=auto -CF @args
    } elseif (Get-Command ls.exe -ErrorAction SilentlyContinue) {
        & ls.exe --color=auto -CF @args
    } else {
        Get-ChildItem @args
    }
}

# Optional Modern Directory Listing (eza shortcuts matching home-settings)
function e {
    if (Get-Command eza -ErrorAction SilentlyContinue) {
        & eza --icons=auto --group-directories-first @args
    } else {
        Invoke-LsStandard @args
    }
}

function el {
    if (Get-Command eza -ErrorAction SilentlyContinue) {
        & eza -la --icons=auto --git --header --group --group-directories-first --time-style=long-iso @args
    } else {
        Invoke-LlStandard @args
    }
}

function elm {
    if (Get-Command eza -ErrorAction SilentlyContinue) {
        & eza -la --icons=auto --git --header --group --group-directories-first --time-style=long-iso --sort=modified @args
    } elseif (Test-Path $coreutilsLs) {
        & $coreutilsLs --color=auto -alFt @args
    } elseif (Get-Command ls.exe -ErrorAction SilentlyContinue) {
        & ls.exe --color=auto -alFt @args
    } else {
        Get-ChildItem -Force @args | Sort-Object LastWriteTime -Descending
    }
}

function et {
    if (Get-Command eza -ErrorAction SilentlyContinue) {
        & eza --tree --level=2 --icons=auto @args
    } else {
        Format-PathTree @args
    }
}

# Backward compatibility alias
function lt { et @args }

function elt {
    if (Get-Command eza -ErrorAction SilentlyContinue) {
        & eza -la --tree --level=2 --icons=auto --git --group --time-style=long-iso @args
    } else {
        Format-PathTree @args
    }
}

function elx {
    if (Get-Command eza -ErrorAction SilentlyContinue) {
        & eza -la --icons=auto --git --header --group --group-directories-first --time-style=long-iso -H -i -S --extended @args
    } elseif (Test-Path $coreutilsLs) {
        & $coreutilsLs --color=auto -alF -i -s @args
    } elseif (Get-Command ls.exe -ErrorAction SilentlyContinue) {
        & ls.exe --color=auto -alF -i -s @args
    } else {
        Get-ChildItem -Force @args
    }
}

# Modern Syntax-Highlighted File Inspection (bat / coreutils cat / Get-Content)
function cat {
    if ($MyInvocation.ExpectingInput) {
        if (Get-Command bat -ErrorAction SilentlyContinue) {
            $input | & bat --theme="Solarized-Dark-TrueColor" --paging=never @args
        } elseif (Test-Path $coreutilsCat) {
            $input | & $coreutilsCat @args
        } elseif (Get-Command cat.exe -ErrorAction SilentlyContinue) {
            $input | & cat.exe @args
        } else {
            $input | Out-String -Stream
        }
    } else {
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
        } elseif ($key -match '\.(exe|cmd|bat|ps1|sh)$') {
            'Green'
        } elseif ($key -match '\.(zip|tar|gz|bz2|xz|7z|rar|iso|zst)$') {
            'Yellow'
        } elseif ($key -match '\.(key|pem|crt|cer|gpg|asc|aes|enc)$') {
            'Magenta'
        } elseif ($key -match '\.(png|jpg|jpeg|gif|svg|webp|mp4|webm|wav|mp3|flac)$') {
            'DarkMagenta'
        } else {
            'Gray'
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
if ((Test-Path $zoxideCache) -and (Get-Item $zoxideCache).Length -gt 0) {
    . $zoxideCache
} elseif (Get-Command zoxide -ErrorAction SilentlyContinue) {
    $cacheDir = "$HOME\.cache\powershell"
    if (-not (Test-Path $cacheDir)) {
        New-Item -ItemType Directory -Force -Path $cacheDir | Out-Null
    }
    zoxide init powershell | Out-File -FilePath $zoxideCache -Encoding utf8 -Force
    if ((Test-Path $zoxideCache) -and (Get-Item $zoxideCache).Length -gt 0) {
        . $zoxideCache
    }
}
