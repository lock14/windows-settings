# ==============================================================================
# Rpc.ps1 - Direct .NET NamedPipe MsgPack-RPC, file opener, cd & AI prompt send
# ==============================================================================

function ConvertTo-MsgPackByteArray([object]$Value) {
    if ($null -eq $Value) {
        return [byte[]]@(0xC0)
    }
    if ($Value -is [bool]) {
        return [byte[]]@($(if ($Value) { 0xC3 } else { 0xC2 }))
    }
    if ($Value -is [int] -or $Value -is [long]) {
        $v = [long]$Value
        if ($v -ge 0 -and $v -le 127) {
            return [byte[]]@([byte]$v)
        }
        if ($v -ge -32 -and $v -lt 0) {
            return [byte[]]@([byte](256 + $v))
        }
        if ($v -ge 0 -and $v -le 0xFF) {
            return [byte[]]@(0xCC, [byte]$v)
        }
        if ($v -ge 0 -and $v -le 0xFFFF) {
            return [byte[]]@(0xCD, [byte](($v -shr 8) -band 0xFF), [byte]($v -band 0xFF))
        }
        if ($v -ge -2147483648 -and $v -le 2147483647) {
            $iv = [int]$v
            return [byte[]]@(
                0xD2,
                [byte](($iv -shr 24) -band 0xFF),
                [byte](($iv -shr 16) -band 0xFF),
                [byte](($iv -shr 8) -band 0xFF),
                [byte]($iv -band 0xFF)
            )
        }
        $be = [System.BitConverter]::GetBytes($v)
        if ([System.BitConverter]::IsLittleEndian) { [Array]::Reverse($be) }
        return ([byte[]]@(0xD3) + $be)
    }
    if ($Value -is [string]) {
        $raw = [System.Text.Encoding]::UTF8.GetBytes($Value)
        $n = $raw.Length
        $ms = [System.IO.MemoryStream]::new($n + 5)
        if ($n -le 31) {
            $ms.WriteByte([byte](0xA0 -bor $n))
        } elseif ($n -le 0xFF) {
            $ms.WriteByte(0xD9)
            $ms.WriteByte([byte]$n)
        } elseif ($n -le 0xFFFF) {
            $ms.WriteByte(0xDA)
            $ms.WriteByte([byte](($n -shr 8) -band 0xFF))
            $ms.WriteByte([byte]($n -band 0xFF))
        } else {
            $ms.WriteByte(0xDB)
            $ms.WriteByte([byte](($n -shr 24) -band 0xFF))
            $ms.WriteByte([byte](($n -shr 16) -band 0xFF))
            $ms.WriteByte([byte](($n -shr 8) -band 0xFF))
            $ms.WriteByte([byte]($n -band 0xFF))
        }
        if ($n -gt 0) {
            $ms.Write($raw, 0, $n)
        }
        return $ms.ToArray()
    }
    if ($Value -is [System.Collections.IList] -or $Value -is [array]) {
        $items = @($Value)
        $cnt = $items.Count
        $ms = [System.IO.MemoryStream]::new()
        if ($cnt -le 15) {
            $ms.WriteByte([byte](0x90 -bor $cnt))
        } elseif ($cnt -le 0xFFFF) {
            $ms.WriteByte(0xDC)
            $ms.WriteByte([byte](($cnt -shr 8) -band 0xFF))
            $ms.WriteByte([byte]($cnt -band 0xFF))
        } else {
            $ms.WriteByte(0xDD)
            $ms.WriteByte([byte](($cnt -shr 24) -band 0xFF))
            $ms.WriteByte([byte](($cnt -shr 16) -band 0xFF))
            $ms.WriteByte([byte](($cnt -shr 8) -band 0xFF))
            $ms.WriteByte([byte]($cnt -band 0xFF))
        }
        foreach ($it in $items) {
            $eb = ConvertTo-MsgPackByteArray $it
            $ms.Write($eb, 0, $eb.Length)
        }
        return $ms.ToArray()
    }
    return (ConvertTo-MsgPackByteArray "$Value")
}

function Read-MsgPackUintBe([byte[]]$Data, [int]$Offset, [int]$Width) {
    if ($Offset + $Width -gt $Data.Length) {
        throw [System.IO.EndOfStreamException]::new()
    }
    [uint64]$acc = 0
    for ($k = 0; $k -lt $Width; $k++) {
        $acc = ($acc -shl 8) -bor [uint64]$Data[$Offset + $k]
    }
    return $acc
}

function ConvertFrom-MsgPackByteArray([byte[]]$Data, [ref]$Pos) {
    $total = $Data.Length
    $p = [int]$Pos.Value
    if ($p -ge $total) {
        throw [System.IO.EndOfStreamException]::new()
    }
    $tag = [int]$Data[$p]
    $p++

    if ($tag -le 0x7F) {
        $Pos.Value = $p
        return $tag
    }
    if ($tag -ge 0xE0) {
        $Pos.Value = $p
        return ($tag - 256)
    }
    if ($tag -eq 0xC0) {
        $Pos.Value = $p
        return $null
    }
    if ($tag -eq 0xC2) {
        $Pos.Value = $p
        return $false
    }
    if ($tag -eq 0xC3) {
        $Pos.Value = $p
        return $true
    }
    if ($tag -ge 0x90 -and $tag -le 0x9F) {
        $cnt = $tag -band 0x0F
        $Pos.Value = $p
        $arr = [object[]]::new($cnt)
        for ($k = 0; $k -lt $cnt; $k++) {
            $arr[$k] = ConvertFrom-MsgPackByteArray -Data $Data -Pos $Pos
        }
        return ,$arr
    }
    if ($tag -ge 0x80 -and $tag -le 0x8F) {
        $cnt = $tag -band 0x0F
        $Pos.Value = $p
        $map = @{}
        for ($k = 0; $k -lt $cnt; $k++) {
            $mk = ConvertFrom-MsgPackByteArray -Data $Data -Pos $Pos
            $mv = ConvertFrom-MsgPackByteArray -Data $Data -Pos $Pos
            $map["$mk"] = $mv
        }
        return $map
    }
    if ($tag -ge 0xA0 -and $tag -le 0xBF) {
        $n = $tag -band 0x1F
        if ($p + $n -gt $total) { throw [System.IO.EndOfStreamException]::new() }
        $Pos.Value = $p + $n
        return [System.Text.Encoding]::UTF8.GetString($Data, $p, $n)
    }
    if ($tag -in @(0xD9, 0xC4)) {
        $n = [int](Read-MsgPackUintBe -Data $Data -Offset $p -Width 1)
        $p += 1
        if ($p + $n -gt $total) { throw [System.IO.EndOfStreamException]::new() }
        $Pos.Value = $p + $n
        return [System.Text.Encoding]::UTF8.GetString($Data, $p, $n)
    }
    if ($tag -in @(0xDA, 0xC5)) {
        $n = [int](Read-MsgPackUintBe -Data $Data -Offset $p -Width 2)
        $p += 2
        if ($p + $n -gt $total) { throw [System.IO.EndOfStreamException]::new() }
        $Pos.Value = $p + $n
        return [System.Text.Encoding]::UTF8.GetString($Data, $p, $n)
    }
    if ($tag -in @(0xDB, 0xC6)) {
        $n = [int](Read-MsgPackUintBe -Data $Data -Offset $p -Width 4)
        $p += 4
        if ($p + $n -gt $total) { throw [System.IO.EndOfStreamException]::new() }
        $Pos.Value = $p + $n
        return [System.Text.Encoding]::UTF8.GetString($Data, $p, $n)
    }
    switch ($tag) {
        0xCC {
            $v = [int](Read-MsgPackUintBe -Data $Data -Offset $p -Width 1)
            $Pos.Value = $p + 1
            return $v
        }
        0xD0 {
            $u = [int](Read-MsgPackUintBe -Data $Data -Offset $p -Width 1)
            $Pos.Value = $p + 1
            return $(if ($u -ge 128) { $u - 256 } else { $u })
        }
        0xCD {
            $v = [int](Read-MsgPackUintBe -Data $Data -Offset $p -Width 2)
            $Pos.Value = $p + 2
            return $v
        }
        0xD1 {
            $u = [int](Read-MsgPackUintBe -Data $Data -Offset $p -Width 2)
            $Pos.Value = $p + 2
            return $(if ($u -ge 32768) { $u - 65536 } else { $u })
        }
        0xCE {
            $v = [long](Read-MsgPackUintBe -Data $Data -Offset $p -Width 4)
            $Pos.Value = $p + 4
            return $v
        }
        0xD2 {
            if ($p + 4 -gt $total) { throw [System.IO.EndOfStreamException]::new() }
            $slice = [byte[]]@($Data[$p..($p + 3)])
            if ([System.BitConverter]::IsLittleEndian) { [Array]::Reverse($slice) }
            $Pos.Value = $p + 4
            return [System.BitConverter]::ToInt32($slice, 0)
        }
        0xCA {
            if ($p + 4 -gt $total) { throw [System.IO.EndOfStreamException]::new() }
            $slice = [byte[]]@($Data[$p..($p + 3)])
            if ([System.BitConverter]::IsLittleEndian) { [Array]::Reverse($slice) }
            $Pos.Value = $p + 4
            return [double][System.BitConverter]::ToSingle($slice, 0)
        }
        0xCF {
            $v = Read-MsgPackUintBe -Data $Data -Offset $p -Width 8
            $Pos.Value = $p + 8
            return [long]$v
        }
        0xD3 {
            if ($p + 8 -gt $total) { throw [System.IO.EndOfStreamException]::new() }
            $slice = [byte[]]@($Data[$p..($p + 7)])
            if ([System.BitConverter]::IsLittleEndian) { [Array]::Reverse($slice) }
            $Pos.Value = $p + 8
            return [System.BitConverter]::ToInt64($slice, 0)
        }
        0xCB {
            if ($p + 8 -gt $total) { throw [System.IO.EndOfStreamException]::new() }
            $slice = [byte[]]@($Data[$p..($p + 7)])
            if ([System.BitConverter]::IsLittleEndian) { [Array]::Reverse($slice) }
            $Pos.Value = $p + 8
            return [System.BitConverter]::ToDouble($slice, 0)
        }
        { $_ -in @(0xDC, 0xDD) } {
            $w = if ($tag -eq 0xDC) { 2 } else { 4 }
            $cnt = [int](Read-MsgPackUintBe -Data $Data -Offset $p -Width $w)
            $Pos.Value = $p + $w
            $arr = [object[]]::new($cnt)
            for ($k = 0; $k -lt $cnt; $k++) {
                $arr[$k] = ConvertFrom-MsgPackByteArray -Data $Data -Pos $Pos
            }
            return ,$arr
        }
        { $_ -in @(0xDE, 0xDF) } {
            $w = if ($tag -eq 0xDE) { 2 } else { 4 }
            $cnt = [int](Read-MsgPackUintBe -Data $Data -Offset $p -Width $w)
            $Pos.Value = $p + $w
            $map = @{}
            for ($k = 0; $k -lt $cnt; $k++) {
                $mk = ConvertFrom-MsgPackByteArray -Data $Data -Pos $Pos
                $mv = ConvertFrom-MsgPackByteArray -Data $Data -Pos $Pos
                $map["$mk"] = $mv
            }
            return $map
        }
        { $_ -ge 0xD4 -and $_ -le 0xD8 } {
            $extLen = 1 -shl ($tag - 0xD4)
            if ($p + 1 + $extLen -gt $total) { throw [System.IO.EndOfStreamException]::new() }
            $Pos.Value = $p + 1 + $extLen
            return $null
        }
        { $_ -in @(0xC7, 0xC8, 0xC9) } {
            $w = if ($tag -eq 0xC7) { 1 } elseif ($tag -eq 0xC8) { 2 } else { 4 }
            $extLen = [int](Read-MsgPackUintBe -Data $Data -Offset $p -Width $w)
            $p += $w
            if ($p + 1 + $extLen -gt $total) { throw [System.IO.EndOfStreamException]::new() }
            $Pos.Value = $p + 1 + $extLen
            return $null
        }
    }
    throw [System.InvalidOperationException]::new("Unsupported MsgPack tag: $tag")
}

function Format-NvimRpcValue([object]$Val) {
    if ($null -eq $Val) { return '' }
    if ($Val -is [bool]) { return $(if ($Val) { '1' } else { '0' }) }
    if ($Val -is [string]) { return $Val.Trim() }
    if ($Val -is [int] -or $Val -is [long] -or $Val -is [double]) { return "$Val" }
    return (($Val | ConvertTo-Json -Compress -Depth 5))
}

function Invoke-NvimNamedPipeRpc(
    [string]$PipePath,
    [string]$LuaCode,
    [object[]]$LuaArgs = @(),
    [int]$TimeoutMs = 1500
) {
    if (-not $PipePath -or -not $LuaCode) {
        return @{ Status = 'conn_err'; Output = '' }
    }
    $pipeName = if ($PipePath -match '^\\\\\.\\pipe\\(.+)$') { $Matches[1] } else { $PipePath }
    if (-not (Test-IdePipeLive $PipePath)) {
        return @{ Status = 'conn_err'; Output = '' }
    }

    # Build MsgPack request: [0, 1, "nvim_exec_lua", [$LuaCode, @($LuaArgs)]]
    $reqFrame = [object[]]@(0, 1, 'nvim_exec_lua', [object[]]@($LuaCode, [object[]]@($LuaArgs)))
    $reqBytes = ConvertTo-MsgPackByteArray $reqFrame

    $cts = [System.Threading.CancellationTokenSource]::new($TimeoutMs)
    $client = $null
    try {
        $client = [System.IO.Pipes.NamedPipeClientStream]::new(
            '.',
            $pipeName,
            [System.IO.Pipes.PipeDirection]::InOut,
            [System.IO.Pipes.PipeOptions]::Asynchronous
        )
        $client.ConnectAsync($cts.Token).GetAwaiter().GetResult()
        $client.WriteAsync($reqBytes, 0, $reqBytes.Length, $cts.Token).GetAwaiter().GetResult()
        $client.FlushAsync($cts.Token).GetAwaiter().GetResult()

        $accum = [System.Collections.Generic.List[byte]]::new()
        $chunk = [byte[]]::new(8192)
        while (-not $cts.IsCancellationRequested) {
            $readN = $client.ReadAsync($chunk, 0, $chunk.Length, $cts.Token).GetAwaiter().GetResult()
            if ($readN -le 0) {
                return @{ Status = 'conn_err'; Output = '' }
            }
            for ($bIdx = 0; $bIdx -lt $readN; $bIdx++) {
                $accum.Add($chunk[$bIdx])
            }
            $dataArr = $accum.ToArray()
            $decodePos = 0
            $savedPos = 0
            try {
                while ($decodePos -lt $dataArr.Length) {
                    $savedPos = $decodePos
                    $msg = ConvertFrom-MsgPackByteArray -Data $dataArr -Pos ([ref]$decodePos)
                    if ($msg -is [array] -and $msg.Count -eq 4 -and [int]$msg[0] -eq 1 -and [int]$msg[1] -eq 1) {
                        if ($null -ne $msg[2]) {
                            return @{ Status = 'rpc_err'; Output = (Format-NvimRpcValue $msg[2]) }
                        }
                        return @{ Status = 'ok'; Output = (Format-NvimRpcValue $msg[3]) }
                    }
                }
                if ($decodePos -gt 0) {
                    $accum.RemoveRange(0, $decodePos)
                }
            } catch [System.IO.EndOfStreamException] {
                if ($savedPos -gt 0) {
                    $accum.RemoveRange(0, $savedPos)
                }
                continue
            }
        }
        return @{ Status = 'conn_err'; Output = '' }
    } catch {
        return @{ Status = 'conn_err'; Output = '' }
    } finally {
        if ($null -ne $client) { $client.Dispose() }
        $cts.Dispose()
    }
}

function Invoke-NvimLua(
    [string]$PipePath,
    [string]$LuaCode,
    [object[]]$LuaArgs = @(),
    [int]$TimeoutMs = 1500,
    [string]$NvimExecutable = ''
) {
    $direct = Invoke-NvimNamedPipeRpc -PipePath $PipePath -LuaCode $LuaCode -LuaArgs $LuaArgs -TimeoutMs $TimeoutMs
    if ($direct.Status -eq 'ok') {
        return @{ Success = $true; Output = $direct.Output }
    }
    if ($direct.Status -eq 'rpc_err') {
        return @{ Success = $false; Output = $direct.Output }
    }

    # Headless CLI fallback when NamedPipe stream cannot connect
    $argJson = (@($LuaArgs) | ConvertTo-Json -Compress -Depth 5)
    $escLua = $LuaCode.Replace("'", "''")
    $escJson = $argJson.Replace("'", "''")
    $expr = "luaeval('(function(raw) local ok, a = pcall(vim.json.decode, raw); local fn = loadstring($([char]39)$escLua$([char]39)); if not fn then return """" end; return fn(unpack(ok and type(a)==$([char]39)table$([char]39) and a or {})) end)(_A)', '$escJson')"
    return (Invoke-NvimRemoteExpr -PipePath $PipePath -Expr $expr -TimeoutMs $TimeoutMs -NvimExecutable $NvimExecutable)
}

function Invoke-NvimRemoteExpr([string]$PipePath, [string]$Expr, [int]$TimeoutMs = 2500, [string]$NvimExecutable = '') {
    if (-not (Test-IdePipeLive $PipePath)) {
        return @{ Success = $false; Output = '' }
    }
    $directEval = Invoke-NvimNamedPipeRpc -PipePath $PipePath -LuaCode 'local e = ...; return vim.fn.eval(e)' -LuaArgs @($Expr) -TimeoutMs ([Math]::Min(1500, $TimeoutMs))
    if ($directEval.Status -eq 'ok') {
        return @{ Success = $true; Output = $directEval.Output }
    }

    $nvimBin = if ($NvimExecutable) { $NvimExecutable } else { Resolve-NvimExecutable }
    if (-not $nvimBin) {
        return @{ Success = $false; Output = '' }
    }
    try {
        $psi = [System.Diagnostics.ProcessStartInfo]::new($nvimBin)
        foreach ($argItem in @('--headless', '--server', $PipePath, '--remote-expr', $Expr)) {
            $psi.ArgumentList.Add($argItem)
        }
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $proc = [System.Diagnostics.Process]::Start($psi)
        if (-not $proc) {
            return @{ Success = $false; Output = '' }
        }
        if (-not $proc.WaitForExit($TimeoutMs)) {
            try { $proc.Kill() } catch { Write-Verbose 'Timed-out RPC client terminated' }
            return @{ Success = $false; Output = '' }
        }
        $stdout = $proc.StandardOutput.ReadToEnd().Trim()
        return @{
            Success = ($proc.ExitCode -eq 0)
            Output  = $stdout
        }
    } catch {
        return @{ Success = $false; Output = '' }
    }
}

function Split-FileAndLineSpec([string]$RawFile, [string]$ExplicitLine = '') {
    $clean = if ($RawFile) { $RawFile.Trim() } else { '' }
    if ($clean.StartsWith('file://')) {
        $clean = [Uri]::UnescapeDataString($clean.Substring(7))
        if ($clean -match '^/+([A-Za-z]:[\\/].*)$') {
            $clean = $Matches[1]
        }
    }
    $filePart = $clean
    $lineNum = 0
    $anchorPart = ''
    if ($ExplicitLine -and $ExplicitLine -match '^\+?([0-9]+)$') {
        $lineNum = [int]$Matches[1]
    } elseif ($clean -match '^(.+)#[Ll]?([0-9]+)(?:-[Ll]?[0-9]+)?$' -and -not (Test-Path -LiteralPath $clean)) {
        $filePart = $Matches[1]
        $lineNum = [int]$Matches[2]
    } elseif ($clean -match '^(.+)#([A-Za-z0-9._%-]+)$' -and -not (Test-Path -LiteralPath $clean)) {
        $filePart = $Matches[1]
        $anchorPart = $Matches[2]
    } elseif ($clean -match '^([A-Za-z]:[^:]+|[^:]+):[Ll]?([0-9]+)(?::[0-9]+)?$' -and $clean -notmatch '^[A-Za-z]:[\\/]?$') {
        $candPath = $Matches[1]
        if (-not (Test-Path -LiteralPath $clean) -and ((Test-Path -LiteralPath $candPath) -or -not [System.IO.Path]::IsPathRooted($clean))) {
            $filePart = $candPath
            $lineNum = [int]$Matches[2]
        }
    }
    return @{
        File   = $filePart
        Line   = $lineNum
        Anchor = $anchorPart
    }
}

function Resolve-IdeOpenFilePath([string]$RawFilePart, [string]$BaseCwd, [System.Collections.IDictionary]$Meta) {
    if (-not $RawFilePart) { return '' }
    $cand = $RawFilePart
    if ($cand -eq '~') { return (Get-UserHomeDir) }
    if ($cand.StartsWith('~\') -or $cand.StartsWith('~/')) {
        $cand = Join-Path (Get-UserHomeDir) $cand.Substring(2)
    }
    if ([System.IO.Path]::IsPathRooted($cand)) {
        return [System.IO.Path]::GetFullPath($cand)
    }

    $wdir = if ($Meta -and $Meta['workdir']) { [string]$Meta['workdir'] } else { '' }
    $initRoot = if ($Meta -and $Meta['root']) { [string]$Meta['root'] } else { '' }
    foreach ($base in @($BaseCwd, $wdir, $initRoot)) {
        if ($base) {
            $joined = Join-Path $base $cand
            if ([System.IO.File]::Exists($joined) -or [System.IO.Directory]::Exists($joined)) {
                return [System.IO.Path]::GetFullPath($joined)
            }
        }
    }

    if (-not (Get-Command Invoke-IdeResolveLinkHook -CommandType Function -ErrorAction SilentlyContinue)) {
        $hooksFile = Join-Path (Get-IdeLibDir) 'Hooks.ps1'
        if ([System.IO.File]::Exists($hooksFile)) { . $hooksFile }
    }
    if (Get-Command Invoke-IdeResolveLinkHook -CommandType Function -ErrorAction SilentlyContinue) {
        $hookOut = Invoke-IdeResolveLinkHook -Word $cand -Cwd $BaseCwd
        if ($hookOut -and $hookOut.StartsWith('file://')) {
            $subSpec = Split-FileAndLineSpec -RawFile $hookOut
            if ($subSpec.File -and [System.IO.File]::Exists($subSpec.File)) {
                return [System.IO.Path]::GetFullPath($subSpec.File)
            }
        }
    }

    return [System.IO.Path]::GetFullPath((Join-Path $BaseCwd $cand))
}

function ConvertFrom-EditorCliArgList([object[]]$RawArgs, [string]$BaseCwd = '') {
    $cwdPath = if ($BaseCwd) { $BaseCwd } else { (Get-Location).ProviderPath }
    $afterDoubleDash = $false
    $canRouteRpc = $true
    $globalLine = 0
    $exCmds = [System.Collections.Generic.List[string]]::new()
    $fileTargets = [System.Collections.Generic.List[hashtable]]::new()

    for ($i = 0; $i -lt $RawArgs.Count; $i++) {
        $s = "$($RawArgs[$i])"
        if (-not $afterDoubleDash) {
            if ($s -eq '--') {
                $afterDoubleDash = $true
                continue
            }
            if ($s -eq '-c') {
                if ($i + 1 -ge $RawArgs.Count) {
                    $canRouteRpc = $false
                    break
                }
                $exCmds.Add("$($RawArgs[++$i])")
                continue
            }
            if ($s -match '^\+([0-9]+)$') {
                $globalLine = [int]$Matches[1]
                continue
            }
            if ($s -eq '+') {
                $exCmds.Add('$')
                continue
            }
            if ($s.StartsWith('+')) {
                $exCmds.Add($s.Substring(1))
                continue
            }
            if ($s.StartsWith('-')) {
                $canRouteRpc = $false
                break
            }
        }

        $parsed = Split-FileAndLineSpec -RawFile $s
        $fPath = $parsed.File
        if (-not [System.IO.Path]::IsPathRooted($fPath)) {
            $fPath = [System.IO.Path]::GetFullPath((Join-Path $cwdPath $fPath))
        }
        $fileTargets.Add(@{ path = $fPath; line = [int]$parsed.Line })
    }

    return @{
        CanRouteRpc = ($canRouteRpc -and $fileTargets.Count -ge 1)
        GlobalLine  = $globalLine
        ExCmds      = @($exCmds)
        FileTargets = @($fileTargets)
        BaseCwd     = $cwdPath
    }
}

function Send-IdeEditorBatch(
    [hashtable[]]$FileTargets,
    [int]$GlobalLine = 0,
    [string[]]$ExCmds = @(),
    [bool]$FocusEditor = $true,
    [string]$BaseCwd = '',
    [string]$NvimExecutable = '',
    [string]$SessionArg = '',
    [string]$AnchorSlug = ''
) {
    if (-not $FileTargets -or $FileTargets.Count -eq 0) { return $false }
    $sess = Resolve-TargetSession $SessionArg
    $meta = Read-SessionState $sess

    $pipePath = ''
    if (-not $SessionArg -and $env:NVIM_IDE_SOCKET -and (Test-IdePipeLive $env:NVIM_IDE_SOCKET.Trim())) {
        $pipePath = $env:NVIM_IDE_SOCKET.Trim()
    } else {
        $candPipe = if ($meta -and $meta['pipe']) { [string]$meta['pipe'] } else { Get-SessionPipePath $sess }
        if (Test-IdePipeLive $candPipe) {
            $pipePath = $candPipe
        }
    }
    if (-not $pipePath) { return $false }

    $cwdFallback = if ($BaseCwd) { $BaseCwd } else { (Get-Location).ProviderPath }
    $healDir = if (-not $SessionArg -and $env:IDE_WORKDIR -and [System.IO.Directory]::Exists($env:IDE_WORKDIR)) {
        $env:IDE_WORKDIR
    } elseif ($meta -and $meta['workdir'] -and [System.IO.Directory]::Exists([string]$meta['workdir'])) {
        [string]$meta['workdir']
    } elseif ($meta -and $meta['root'] -and [System.IO.Directory]::Exists([string]$meta['root'])) {
        [string]$meta['root']
    } else {
        $cwdFallback
    }
    $syncCwd = [bool](($meta -and $meta['workdir']) -or (-not $SessionArg -and $env:IDE_WORKDIR))
    $cleanAnchor = if ($AnchorSlug) { $AnchorSlug.Trim().TrimStart('#') } else { '' }
    if ($cleanAnchor) {
        try { $cleanAnchor = [Uri]::UnescapeDataString($cleanAnchor) } catch { Write-Verbose 'Anchor unescape skipped' }
    }

    $rpcPayload = @{
        workdir  = $healDir
        sync_cwd = $syncCwd
        files    = @($FileTargets)
        line     = $GlobalLine
        anchor   = $cleanAnchor
        cmds     = @($ExCmds)
    } | ConvertTo-Json -Compress -Depth 4

    $luaCode = @'
local raw = ...
vim.schedule(function()
    local ok, p = pcall(vim.json.decode, raw)
    if not ok or type(p) ~= "table" then return end
    pcall(function() require("mini.files").close() end)
    local uv = vim.uv or vim.loop
    if type(p.workdir) == "string" and p.workdir ~= "" and uv.fs_stat(p.workdir) then
        local no_cwd = (uv.fs_stat(vim.fn.getcwd()) == nil)
        local can_sync = (p.sync_cwd and vim.fn.haslocaldir() == 0 and vim.fn.haslocaldir(-1, 0) == 0)
        if no_cwd or can_sync then
            pcall(vim.fn.chdir, p.workdir)
        end
    end
    pcall(vim.cmd, "silent! checktime")
    local gl = tonumber(p.line) or 0
    for _, it in ipairs(p.files or {}) do
        if type(it.path) == "string" and it.path ~= "" then
            pcall(vim.cmd, "silent! normal! m'")
            vim.cmd("silent! keepjumps edit " .. vim.fn.fnameescape(it.path))
            local fl = tonumber(it.line) or 0
            if fl > 0 then pcall(vim.api.nvim_win_set_cursor, 0, { fl, 0 }) end
        end
    end
    if gl > 0 then
        pcall(vim.api.nvim_win_set_cursor, 0, { gl, 0 })
    elseif type(p.anchor) == "string" and p.anchor ~= "" then
        local ok_l, links = pcall(require, "solarized.links")
        if ok_l and links and links.find_markdown_anchor_line then
            local al = links.find_markdown_anchor_line(0, p.anchor)
            if al and al > 0 then
                pcall(vim.api.nvim_win_set_cursor, 0, { al, 0 })
                pcall(vim.cmd, "silent! normal! ^zz")
            end
        end
    end
    for _, ex in ipairs(p.cmds or {}) do
        if type(ex) == "string" and ex ~= "" then pcall(vim.cmd, ex) end
    end
    if gl > 0 or #(p.cmds or {}) > 0 then pcall(vim.cmd, "silent! normal! zz") end
end)
return "OK"
'@

    $res = Invoke-NvimLua -PipePath $pipePath -LuaCode $luaCode -LuaArgs @($rpcPayload) -NvimExecutable $NvimExecutable
    if (-not $res.Success -or $res.Output -notmatch 'OK') {
        return $false
    }
    if ($FocusEditor -and ($env:ZELLIJ -or $SessionArg)) {
        [void](Select-IdeRolePane -SessionName $sess -Role 'editor' -EnsureOnly $true)
    }
    return $true
}

function Invoke-EditorNvimInIdleZellijPane(
    [string]$SessionName,
    [string]$PipePath,
    [string]$TargetPath,
    [int]$LineNum,
    [bool]$FocusEditor
) {
    $zellijBin = Resolve-ZellijExecutable
    $nvimBin = Resolve-NvimExecutable
    if (-not $zellijBin -or -not $nvimBin) { return $false }
    $liveZellij = Get-LiveZellijSessionMap
    if ($liveZellij[$SessionName] -ne 'live') { return $false }

    $edPaneId = Get-RolePaneId -SessionName $SessionName -Role 'editor'
    $panesJson = try {
        Invoke-ZellijSessionAction -SessionName $SessionName -ActionArgs @('list-panes', '--all', '--json') -PassThru
    } catch {
        ''
    }
    $edEntry = $null
    if ($panesJson) {
        try {
            $allPanes = @($panesJson | ConvertFrom-Json)
            if ($edPaneId -and ($edPaneId -replace '^terminal_', '') -match '^[0-9]+$') {
                $rawNum = [int]($edPaneId -replace '^terminal_', '')
                $edEntry = $allPanes | Where-Object { -not $_.is_plugin -and $_.id -eq $rawNum } | Select-Object -First 1
            }
            if (-not $edEntry) {
                $edEntry = $allPanes | Where-Object { -not $_.is_plugin -and "$($_.title)" -match '(?i)(\[Editor\]|^Editor$|\bnvim\b)' } | Select-Object -First 1
                if ($edEntry) { $edPaneId = "terminal_$($edEntry.id)" }
            }
        } catch {
            Write-Verbose "Editor pane JSON lookup skipped: $_"
        }
    }
    if (-not $edPaneId -or ($edEntry -and $edEntry.exited -eq $true)) {
        return $false
    }
    if ($edEntry -and "$($edEntry.title)" -match '(?i)\bnvim\b') {
        return $false
    }
    if ($edEntry -and $edEntry.is_suppressed -eq $true) {
        [void](Invoke-ZellijPipe -SessionName $SessionName -PipeName 'ws-ide-role' -Payload 'toggle:editor')
    }

    $escNvim = $nvimBin.Replace("'", "''")
    $escPipe = $PipePath.Replace("'", "''")
    $escFile = $TargetPath.Replace("'", "''")
    $launchCmd = if ($LineNum -gt 0) {
        " & '$escNvim' --listen '$escPipe' '+$LineNum' '$escFile'"
    } else {
        " & '$escNvim' --listen '$escPipe' '$escFile'"
    }
    [void](Invoke-ZellijSessionAction -SessionName $SessionName -ActionArgs @('paste', '--pane-id', $edPaneId, '--', $launchCmd))
    [void](Invoke-ZellijSessionAction -SessionName $SessionName -ActionArgs @('write', '--pane-id', $edPaneId, '13'))

    for ($attempt = 0; $attempt -lt 40; $attempt++) {
        if (Test-IdePipeLive $PipePath) { break }
        Start-Sleep -Milliseconds 50
    }
    if ($FocusEditor) {
        [void](Select-IdeRolePane -SessionName $SessionName -Role 'editor' -EnsureOnly $true)
    }
    return $true
}

function Invoke-IdeOpen(
    [string]$RawFile,
    [string]$ExplicitLine = '',
    [bool]$FallbackLocalEdit = $false,
    [bool]$FocusEditor = $true,
    [string]$SessionArg = ''
) {
    if (-not $RawFile) {
        [Console]::Error.WriteLine("Error: 'ide open' requires a file path.")
        exit 1
    }
    $sess = Resolve-TargetSession $SessionArg
    $meta = Read-SessionState $sess
    $cwdNow = (Get-Location).ProviderPath
    $parsed = Split-FileAndLineSpec -RawFile $RawFile -ExplicitLine $ExplicitLine
    $targetPath = Resolve-IdeOpenFilePath -RawFilePart $parsed.File -BaseCwd $cwdNow -Meta $meta
    $lineNum = [int]$parsed.Line

    if ([System.IO.Directory]::Exists($targetPath) -and -not $FallbackLocalEdit) {
        Invoke-IdeCd -TargetArg $targetPath -SessionArg $SessionArg
        exit 0
    }

    $batchTargets = @(@{ path = $targetPath; line = $lineNum })
    if (Send-IdeEditorBatch -FileTargets $batchTargets -GlobalLine $lineNum -AnchorSlug ([string]$parsed.Anchor) -FocusEditor $FocusEditor -SessionArg $SessionArg) {
        exit 0
    }

    $pipePath = if ($meta -and $meta['pipe']) { [string]$meta['pipe'] } else { Get-SessionPipePath $sess }
    if (Invoke-EditorNvimInIdleZellijPane -SessionName $sess -PipePath $pipePath -TargetPath $targetPath -LineNum $lineNum -FocusEditor $FocusEditor) {
        exit 0
    }

    if ($FallbackLocalEdit) {
        $nvimBin = Resolve-NvimExecutable
        if (-not $nvimBin) {
            [Console]::Error.WriteLine('Error: nvim is not installed.')
            exit 1
        }
        if ($lineNum -gt 0) {
            & $nvimBin "+$lineNum" $targetPath
        } else {
            & $nvimBin $targetPath
        }
        exit $LASTEXITCODE
    }

    [Console]::Error.WriteLine("Error: No active IDE Neovim server found for session '$sess'.")
    exit 1
}

function Invoke-OpenInIde([string]$RawFile, [string]$ExplicitLine, [bool]$FallbackLocalEdit, [bool]$FocusEditor) {
    Invoke-IdeOpen -RawFile $RawFile -ExplicitLine $ExplicitLine -FallbackLocalEdit $FallbackLocalEdit -FocusEditor $FocusEditor
}

function Sync-IdleShellPaneDirectory([string]$SessionName, [string]$TargetDir) {
    if ($env:IDE_CD_SKIP_SHELL -eq '1') { return }
    $zellijBin = Resolve-ZellijExecutable
    if (-not $zellijBin) { return }
    $liveZellij = Get-LiveZellijSessionMap
    if ($liveZellij[$SessionName] -ne 'live') { return }

    $termPaneId = Get-RolePaneId -SessionName $SessionName -Role 'term'
    $panesJson = try {
        Invoke-ZellijSessionAction -SessionName $SessionName -ActionArgs @('list-panes', '--all', '--json') -PassThru
    } catch {
        ''
    }
    if (-not $panesJson) { return }

    $termEntry = $null
    try {
        $allPanes = @($panesJson | ConvertFrom-Json)
        if ($termPaneId -and ($termPaneId -replace '^terminal_', '') -match '^[0-9]+$') {
            $rawNum = [int]($termPaneId -replace '^terminal_', '')
            $termEntry = $allPanes | Where-Object { -not $_.is_plugin -and $_.id -eq $rawNum } | Select-Object -First 1
        }
        if (-not $termEntry) {
            $termEntry = $allPanes | Where-Object { -not $_.is_plugin -and "$($_.title)" -match '(?i)(\[Shell\]|^Shell$)' } | Select-Object -First 1
            if ($termEntry) { $termPaneId = "terminal_$($termEntry.id)" }
        }
    } catch {
        return
    }
    if (-not $termEntry -or $termEntry.exited -eq $true) { return }
    # Only send cd when pane title shows idle shell (not running an external foreground TUI)
    if ("$($termEntry.title)" -notmatch '(?i)(\[Shell\]|^Shell$|\bpwsh\b|\bpowershell\b|\bcmd\b)') {
        return
    }
    # If invoked from inside the Shell pane itself, skip pasting back into our own active command prompt
    $callerPane = ConvertTo-ZellijPaneId $env:ZELLIJ_PANE_ID
    if ((Test-IsCurrentZellijSession $SessionName) -and $callerPane -eq $termPaneId) {
        return
    }

    $escDir = $TargetDir.Replace("'", "''")
    $cdLine = " Set-Location -LiteralPath '$escDir'"
    [void](Invoke-ZellijSessionAction -SessionName $SessionName -ActionArgs @('write', '--pane-id', $termPaneId, '27'))
    [void](Invoke-ZellijSessionAction -SessionName $SessionName -ActionArgs @('paste', '--pane-id', $termPaneId, '--', $cdLine))
    [void](Invoke-ZellijSessionAction -SessionName $SessionName -ActionArgs @('write', '--pane-id', $termPaneId, '13'))
}

function Invoke-IdeCd([string]$TargetArg = '', [string]$SessionArg = '') {
    $sess = Resolve-TargetSession $SessionArg
    $meta = Read-SessionState $sess
    $initRoot = if ($meta -and $meta['root']) {
        [string]$meta['root']
    } elseif ($env:IDE_INITIAL_ROOT -and $env:IDE_INITIAL_ROOT.Trim()) {
        $env:IDE_INITIAL_ROOT.Trim()
    } else {
        (Get-Location).ProviderPath
    }
    $curWorkdir = if ($meta -and $meta['workdir']) {
        [string]$meta['workdir']
    } elseif (-not $SessionArg -and $env:IDE_WORKDIR) {
        $env:IDE_WORKDIR
    } else {
        $initRoot
    }

    $resolved = if (-not $TargetArg -or $TargetArg -in @('--reset', '~')) {
        $initRoot
    } elseif ($TargetArg -eq '-') {
        $savedPrev = if ($meta -and $meta['prev_workdir']) { [string]$meta['prev_workdir'] } else { '' }
        if ($savedPrev) { $savedPrev } else { $initRoot }
    } elseif ([System.IO.Path]::IsPathRooted($TargetArg)) {
        $TargetArg
    } else {
        $candFromWork = Join-Path $curWorkdir $TargetArg
        $candFromRoot = if ($initRoot) { Join-Path $initRoot $TargetArg } else { '' }
        if (Test-Path -LiteralPath $candFromWork -PathType Container) {
            [System.IO.Path]::GetFullPath($candFromWork)
        } elseif ($candFromRoot -and (Test-Path -LiteralPath $candFromRoot -PathType Container)) {
            [System.IO.Path]::GetFullPath($candFromRoot)
        } else {
            [System.IO.Path]::GetFullPath((Join-Path (Get-Location).ProviderPath $TargetArg))
        }
    }

    if (-not (Test-Path -LiteralPath $resolved -PathType Container)) {
        [Console]::Error.WriteLine("Error: Directory not found: $resolved")
        exit 1
    }
    $resolved = (Resolve-Path -LiteralPath $resolved).ProviderPath

    if (-not $meta) {
        $meta = Build-IdeSessionRecord `
            -SessionName $sess `
            -Root $initRoot `
            -Workdir $resolved `
            -PrevWorkdir $(if ($curWorkdir -and -not [string]::Equals($curWorkdir, $resolved, [System.StringComparison]::OrdinalIgnoreCase)) { $curWorkdir } else { '' }) `
            -Backend $(if ($env:ZELLIJ) { 'zellij' } else { 'wt' })
    } else {
        if ($curWorkdir -and -not [string]::Equals($curWorkdir, $resolved, [System.StringComparison]::OrdinalIgnoreCase)) {
            $meta['prev_workdir'] = $curWorkdir
        }
        $meta['workdir'] = $resolved
    }
    Save-SessionState $meta

    $pipePath = [string]$meta['pipe']
    if (Test-IdePipeLive $pipePath) {
        $cdLua = 'local d = ...; vim.schedule(function() pcall(vim.fn.chdir, d); pcall(vim.cmd, "silent! checktime") end); return "OK"'
        [void](Invoke-NvimLua -PipePath $pipePath -LuaCode $cdLua -LuaArgs @($resolved))
    }

    Sync-IdleShellPaneDirectory -SessionName $sess -TargetDir $resolved

    if ($env:ZELLIJ -or (Resolve-ZellijExecutable)) {
        [void](Invoke-ZellijPipe -SessionName $sess -PipeName 'ws-ide-state' -Payload "root=$initRoot;workdir=$resolved")
    }

    Write-Output $resolved
}

function Format-RelativeFileRef([string]$RawRef, [string]$BaseDir) {
    $trimmed = $RawRef.Trim().TrimStart('@')
    $filePart = $trimmed
    $l1 = ''
    $l2 = ''

    if ($trimmed -match '^(?<file>[A-Za-z]:[^:#]+|[^:#]+)(?:[:#]L?(?<l1>[0-9]+)(?:-L?(?<l2>[0-9]+))?)?$') {
        $filePart = $Matches['file']
        if ($Matches['l1']) { $l1 = $Matches['l1'] }
        if ($Matches['l2']) { $l2 = $Matches['l2'] }
    }

    $relPath = $filePart
    if ($BaseDir -and [System.IO.Path]::IsPathRooted($filePart)) {
        try {
            $computed = [System.IO.Path]::GetRelativePath($BaseDir, $filePart)
            if ($computed -and -not $computed.StartsWith('..')) {
                $relPath = $computed
            }
        } catch {
            $relPath = $filePart
        }
    }
    $relPath = $relPath.Replace('\', '/')

    if ($l1 -and $l2 -and $l1 -ne $l2) {
        return "@${relPath}#L${l1}-L${l2} "
    }
    if ($l1) {
        return "@${relPath}#L${l1} "
    }
    return "@${relPath} "
}

function ConvertTo-SanitizedPasteText([string]$Text) {
    if (-not $Text) { return '' }
    $esc = [char]27
    $csi = [char]0x9B
    $markers = @(
        "${esc}[200~",
        "${esc}[201~",
        "${csi}200~",
        "${csi}201~"
    )
    $clean = $Text
    $changed = $true
    while ($changed) {
        $changed = $false
        foreach ($m in $markers) {
            if ($clean.Contains($m)) {
                $clean = $clean.Replace($m, '')
                $changed = $true
            }
        }
    }
    return $clean
}

function Invoke-IdeSend([string[]]$SendArgs, [string]$PipedInput = '') {
    $mode = ''
    $payload = ''
    $noFocus = $false
    $switchSession = $false
    $posArgs = [System.Collections.Generic.List[string]]::new()
    $subEnd = $false

    for ($idx = 0; $idx -lt $SendArgs.Count; $idx++) {
        $a = $SendArgs[$idx]
        if (-not $subEnd -and $a -eq '--') {
            $subEnd = $true
            continue
        }
        if ($subEnd) {
            $posArgs.Add($a)
            continue
        }
        if ($a -eq '--stdin') {
            $mode = 'stdin'
            continue
        }
        if ($a -eq '--ref') {
            $mode = 'ref'
            if ($idx + 1 -ge $SendArgs.Count) {
                [Console]::Error.WriteLine("Error: '--ref' requires a file path.")
                exit 1
            }
            $payload = $SendArgs[++$idx]
            continue
        }
        if ($a.StartsWith('--ref=')) {
            $mode = 'ref'
            $payload = $a.Substring(6)
            continue
        }
        if ($a -eq '--text') {
            $mode = 'text'
            if ($idx + 1 -ge $SendArgs.Count) {
                [Console]::Error.WriteLine("Error: '--text' requires a text string.")
                exit 1
            }
            $payload = $SendArgs[++$idx]
            continue
        }
        if ($a.StartsWith('--text=')) {
            $mode = 'text'
            $payload = $a.Substring(7)
            continue
        }
        if ($a -eq '--no-focus') {
            $noFocus = $true
            $switchSession = $false
            continue
        }
        if ($a -eq '--switch') {
            $switchSession = $true
            $noFocus = $false
            continue
        }
        if ($a.StartsWith('-')) {
            [Console]::Error.WriteLine("Error: Unknown 'ide send' option '$a'.")
            exit 1
        }
        $posArgs.Add($a)
    }

    if (-not $mode -and $posArgs.Count -gt 0) {
        $mode = 'text'
        $payload = $posArgs[0]
        $posArgs.RemoveAt(0)
    }
    if ($posArgs.Count -gt 1) {
        [Console]::Error.WriteLine("Error: Unexpected extra argument '$($posArgs[1])'.")
        exit 1
    }
    $targetSessArg = if ($posArgs.Count -eq 1) { $posArgs[0] } else { '' }

    $sess = Resolve-TargetSession $targetSessArg
    $meta = Read-SessionState $sess
    $baseDir = if ($meta -and $meta['workdir']) {
        [string]$meta['workdir']
    } elseif ($meta -and $meta['root']) {
        [string]$meta['root']
    } else {
        (Get-Location).ProviderPath
    }

    if ($mode -eq 'stdin') {
        $payload = if ($PipedInput) { $PipedInput } elseif ([Console]::IsInputRedirected) { [Console]::In.ReadToEnd() } else { '' }
    } elseif ($mode -eq 'ref' -and $payload) {
        $payload = Format-RelativeFileRef -RawRef $payload -BaseDir $baseDir
    }

    $payload = ConvertTo-SanitizedPasteText $payload
    if (-not $payload) { exit 0 }

    $stateDir = Get-IdeStateDir
    $stageFile = Join-Path $stateDir "$sess.send.txt"
    Write-TextUtf8NoBom -Path $stageFile -Content $payload

    if ($env:WS_IDE_COPY_CLIPBOARD -eq '1' -and $env:WS_IDE_SKIP_CLIPBOARD -ne '1') {
        try {
            Set-Clipboard -Value $payload -ErrorAction Stop
        } catch {
            Write-Verbose "Clipboard stage skipped in headless environment: $_"
        }
    }

    $zellijBin = Resolve-ZellijExecutable
    $aiPaneId = Get-RolePaneId -SessionName $sess -Role 'ai'
    if (-not $aiPaneId) { $aiPaneId = 'terminal_0' }

    if ($zellijBin) {
        $liveZellij = Get-LiveZellijSessionMap
        if ($liveZellij[$sess] -eq 'live') {
            $inSameSession = Test-IsCurrentZellijSession $sess
            $panesJson = try {
                Invoke-ZellijSessionAction -SessionName $sess -ActionArgs @('list-panes', '--all', '--json') -PassThru
            } catch {
                ''
            }

            $aiEntry = $null
            if ($panesJson) {
                try {
                    $allPanes = @($panesJson | ConvertFrom-Json)
                    if (($aiPaneId -replace '^terminal_', '') -match '^[0-9]+$') {
                        $rawNum = [int]($aiPaneId -replace '^terminal_', '')
                        $aiEntry = $allPanes | Where-Object { -not $_.is_plugin -and $_.id -eq $rawNum } | Select-Object -First 1
                    }
                    if (-not $aiEntry) {
                        $aiEntry = $allPanes | Where-Object { -not $_.is_plugin -and "$($_.title)" -match '(?i)(^AI\b|\[AI:|\bagy\b|\bclaude\b|\bcodex\b)' } | Select-Object -First 1
                    }
                    if ($aiEntry) {
                        $aiPaneId = "terminal_$($aiEntry.id)"
                    }
                } catch {
                    Write-Verbose "Pane JSON inspection skipped: $_"
                }
            }

            if ($aiEntry -and $aiEntry.exited -eq $true) {
                [Console]::Error.WriteLine("Error: AI pane in session '$sess' has exited; refusing to paste into dead pane.")
                exit 1
            }

            $aiShellMarker = Join-Path $stateDir "$sess.ai-shell"
            if ($env:IDE_ALLOW_SHELL_SEND -ne '1' -and (
                [System.IO.File]::Exists($aiShellMarker) -or
                ($meta -and $meta['ai_cli'] -eq 'shell') -or
                ($aiEntry -and "$($aiEntry.title)" -match '\[AI:\s*shell\]')
            )) {
                $hasLiveAgentProc = @(Get-Process -Name 'agy', 'claude', 'codex' -ErrorAction SilentlyContinue).Count -gt 0
                if (-not $hasLiveAgentProc) {
                    [Console]::Error.WriteLine("Error: No active AI agent running in session '$sess' (pane is at an interactive shell); start an agent or set IDE_ALLOW_SHELL_SEND=1.")
                    exit 1
                }
            }

            if ($aiEntry -and $aiEntry.is_suppressed -eq $true) {
                [void](Invoke-ZellijPipe -SessionName $sess -PipeName 'ws-ide-role' -Payload 'toggle:ai')
            }

            [void](Invoke-ZellijSessionAction -SessionName $sess -ActionArgs @('paste', '--pane-id', $aiPaneId, '--', $payload))
            if ($inSameSession) {
                if (-not $noFocus) {
                    & $zellijBin action focus-pane-id $aiPaneId *> $null
                }
            } elseif ($switchSession) {
                if ($env:ZELLIJ) {
                    & $zellijBin action switch-session --pane-id $aiPaneId $sess *> $null
                } else {
                    & $zellijBin attach $sess
                }
            }
        }
    }
}

function Format-CleanLinkToken([string]$RawToken) {
    if (-not $RawToken) { return '' }
    $s = $RawToken.Trim().TrimStart('(', '[', '{', '"', '<', "'", '`')
    while ($s.Length -gt 0) {
        if ($s.StartsWith('//') -and ($s.EndsWith('/...') -or $s.EndsWith('/..'))) {
            break
        }
        $last = $s[$s.Length - 1]
        if ($last -in @('>', '"', "'", '`', ',', ';', '.', ':')) {
            $s = $s.Substring(0, $s.Length - 1)
        } elseif ($last -eq ')' -and (($s.Split(')').Count - 1) -gt ($s.Split('(').Count - 1))) {
            $s = $s.Substring(0, $s.Length - 1)
        } elseif ($last -eq ']' -and (($s.Split(']').Count - 1) -gt ($s.Split('[').Count - 1))) {
            $s = $s.Substring(0, $s.Length - 1)
        } elseif ($last -eq '}' -and (($s.Split('}').Count - 1) -gt ($s.Split('{').Count - 1))) {
            $s = $s.Substring(0, $s.Length - 1)
        } else {
            break
        }
    }
    return $s
}

function Split-IdeLinkTarget([string]$RawTarget, [string]$BaseCwd = '') {
    $clean = if ($RawTarget) { $RawTarget.Trim() } else { '' }
    if (-not $clean) {
        return @{ Path = ''; Line = 0; Anchor = '' }
    }
    $hadFileScheme = $clean.StartsWith('file://', [System.StringComparison]::OrdinalIgnoreCase)
    if ($hadFileScheme) {
        $clean = $clean.Substring(7)
        if ($clean.StartsWith('localhost/', [System.StringComparison]::OrdinalIgnoreCase)) {
            $clean = $clean.Substring(9)
        } elseif (-not $clean.StartsWith('/') -and $clean -notmatch '^[A-Za-z]:[\\/]' -and $clean.Contains('/')) {
            $clean = $clean.Substring($clean.IndexOf('/'))
        }
        try { $clean = [Uri]::UnescapeDataString($clean) } catch { Write-Verbose 'URI unescape skipped' }
        if ($clean -match '^/+([A-Za-z]:[\\/].*)$') {
            $clean = $Matches[1]
        }
    } elseif ($clean -match '%[0-9A-Fa-f]{2}') {
        try { $clean = [Uri]::UnescapeDataString($clean) } catch { Write-Verbose 'URI unescape skipped' }
    }

    $testExists = {
        param([string]$Candidate)
        if (-not $Candidate) { return $false }
        $exp = $Candidate
        if ($exp -eq '~') { $exp = Get-UserHomeDir }
        elseif ($exp.StartsWith('~/') -or $exp.StartsWith('~\')) { $exp = Join-Path (Get-UserHomeDir) $exp.Substring(2) }
        if ([System.IO.File]::Exists($exp) -or [System.IO.Directory]::Exists($exp)) { return $true }
        if ($BaseCwd -and -not [System.IO.Path]::IsPathRooted($exp)) {
            $rel = Join-Path $BaseCwd $exp
            return ([System.IO.File]::Exists($rel) -or [System.IO.Directory]::Exists($rel))
        }
        return $false
    }

    $lineNum = 0
    $anchor = ''
    if ($clean -match '^(.+)#[Ll]?([0-9]+)(?::[0-9]+)?(?:[-:][Ll]?[0-9]+(?::[0-9]+)?)?$' -and -not (& $testExists $clean)) {
        $clean = $Matches[1]
        $lineNum = [int]$Matches[2]
    } elseif ($clean.Contains('#') -and -not $clean.StartsWith('#') -and -not (& $testExists $clean)) {
        $hashIdx = $clean.LastIndexOf('#')
        $baseCand = $clean.Substring(0, $hashIdx)
        $fragCand = $clean.Substring($hashIdx + 1)
        if ((& $testExists $baseCand) -or $hadFileScheme -or ([System.IO.Path]::GetExtension($baseCand) -and $fragCand -match '^[A-Za-z0-9_.:%-]+$')) {
            $clean = $baseCand
            $anchor = $fragCand
        }
    }

    if ($lineNum -le 0 -and -not (& $testExists $clean)) {
        if ($clean -match '^([A-Za-z]:[^:]+|[^:]+):[Ll]?([0-9]+)(?::[0-9]+)?(?:-[Ll]?[0-9]+(?::[0-9]+)?)?$' -and $clean -notmatch '^[A-Za-z]:[\\/]?$') {
            $clean = $Matches[1]
            $lineNum = [int]$Matches[2]
        }
    }

    return @{
        Path   = $clean
        Line   = $lineNum
        Anchor = $anchor
    }
}

function Find-GitTrackedUniqueMatch([string]$SearchDir, [string]$RelCandidate) {
    if (-not $SearchDir -or -not $RelCandidate -or -not [System.IO.Directory]::Exists($SearchDir)) {
        return ''
    }
    $gitApp = Get-Command git.exe, git -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $gitApp) { return '' }

    $gitRoot = ''
    $cur = $SearchDir
    while ($cur) {
        $dotGit = Join-Path $cur '.git'
        if ([System.IO.Directory]::Exists($dotGit) -or [System.IO.File]::Exists($dotGit)) {
            $gitRoot = $cur
            break
        }
        $parent = [System.IO.Path]::GetDirectoryName($cur)
        if (-not $parent -or $parent -eq $cur) { break }
        $cur = $parent
    }
    if (-not $gitRoot) { return '' }

    $normCand = $RelCandidate.Replace('\', '/').TrimStart('/')
    $directGit = Join-Path $gitRoot ($normCand.Replace('/', [System.IO.Path]::DirectorySeparatorChar))
    if ([System.IO.File]::Exists($directGit) -or [System.IO.Directory]::Exists($directGit)) {
        return [System.IO.Path]::GetFullPath($directGit)
    }
    if ($normCand.Contains('/')) {
        $strippedFirst = $normCand.Substring($normCand.IndexOf('/') + 1)
        $altGit = Join-Path $gitRoot ($strippedFirst.Replace('/', [System.IO.Path]::DirectorySeparatorChar))
        if ([System.IO.File]::Exists($altGit) -or [System.IO.Directory]::Exists($altGit)) {
            return [System.IO.Path]::GetFullPath($altGit)
        }
    }

    $suffix = "/$normCand"
    foreach ($gitSubArgs in @(@('ls-files', '--cached'), @('ls-files', '--others', '--exclude-standard'))) {
        try {
            $psi = [System.Diagnostics.ProcessStartInfo]::new($gitApp.Source)
            $psi.ArgumentList.Add('-C')
            $psi.ArgumentList.Add($gitRoot)
            foreach ($ga in $gitSubArgs) { $psi.ArgumentList.Add($ga) }
            $psi.RedirectStandardInput = $true
            $psi.RedirectStandardOutput = $true
            $psi.RedirectStandardError = $true
            $psi.UseShellExecute = $false
            $psi.CreateNoWindow = $true
            $proc = [System.Diagnostics.Process]::Start($psi)
            if (-not $proc) { continue }
            try { $proc.StandardInput.Close() } catch { Write-Verbose 'git ls-files stdin close skipped' }
            $outTask = $proc.StandardOutput.ReadToEndAsync()
            if (-not $proc.WaitForExit(800)) {
                try { $proc.Kill($true) } catch { Write-Verbose 'Timed-out git ls-files terminated' }
                continue
            }
            if ($proc.ExitCode -ne 0) { continue }
            $rawOut = if ($outTask.Wait(200)) { $outTask.Result } else { '' }
            $hits = [System.Collections.Generic.List[string]]::new()
            foreach ($rel in ($rawOut -split "`r?`n")) {
                if (-not $rel) { continue }
                if ([string]::Equals($rel, $normCand, [System.StringComparison]::OrdinalIgnoreCase) -or
                    $rel.EndsWith($suffix, [System.StringComparison]::OrdinalIgnoreCase)) {
                    $fullHit = [System.IO.Path]::GetFullPath((Join-Path $gitRoot ($rel.Replace('/', [System.IO.Path]::DirectorySeparatorChar))))
                    if (-not $hits.Contains($fullHit) -and [System.IO.File]::Exists($fullHit)) {
                        $hits.Add($fullHit)
                        if ($hits.Count -gt 1) { break }
                    }
                }
            }
            if ($hits.Count -eq 1) { return $hits[0] }
            if ($hits.Count -gt 1) { return '' }
        } catch {
            Write-Verbose "git ls-files lookup skipped: $_"
        }
    }
    return ''
}

function Find-WorkspaceLinkFile([string]$Candidate, [string]$PaneCwd, [System.Collections.IDictionary]$Meta) {
    if (-not $Candidate -or $Candidate.StartsWith('//') -or $Candidate.StartsWith('file://', [System.StringComparison]::OrdinalIgnoreCase)) {
        return ''
    }
    $cand = $Candidate
    if ($cand -eq '~') { return (Get-UserHomeDir) }
    if ($cand.StartsWith('~/') -or $cand.StartsWith('~\')) {
        $expandedHome = [System.IO.Path]::GetFullPath((Join-Path (Get-UserHomeDir) $cand.Substring(2)))
        if ([System.IO.File]::Exists($expandedHome) -or [System.IO.Directory]::Exists($expandedHome)) {
            return $expandedHome
        }
        return ''
    }
    if ([System.IO.Path]::IsPathRooted($cand)) {
        $fullAbs = try { [System.IO.Path]::GetFullPath($cand) } catch { '' }
        if ($fullAbs -and ([System.IO.File]::Exists($fullAbs) -or [System.IO.Directory]::Exists($fullAbs))) {
            return $fullAbs
        }
        return ''
    }

    $wdir = if ($Meta -and $Meta['workdir']) { [string]$Meta['workdir'] } else { '' }
    $initRoot = if ($Meta -and $Meta['root']) { [string]$Meta['root'] } else { '' }
    $normRel = $cand.Replace('/', [System.IO.Path]::DirectorySeparatorChar).TrimStart('\')

    foreach ($base in @($PaneCwd, $wdir, $initRoot)) {
        if ($base -and [System.IO.Directory]::Exists($base)) {
            $direct = try { [System.IO.Path]::GetFullPath((Join-Path $base $normRel)) } catch { '' }
            if ($direct -and ([System.IO.File]::Exists($direct) -or [System.IO.Directory]::Exists($direct))) {
                return $direct
            }
        }
    }

    $seenGit = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($base in @($PaneCwd, $wdir, $initRoot)) {
        if (-not $base -or -not [System.IO.Directory]::Exists($base)) { continue }
        $key = $base.TrimEnd('\', '/')
        if (-not $seenGit.Add($key)) { continue }
        $gitHit = Find-GitTrackedUniqueMatch -SearchDir $base -RelCandidate $cand
        if ($gitHit) { return $gitHit }
    }

    $segs = @($cand.Replace('\', '/') -split '/' | Where-Object { $_ -and $_ -ne '.' })
    if ($segs.Count -eq 0 -or ($segs -contains '..')) { return '' }
    $firstSeg = $segs[0]
    $restRel = if ($segs.Count -gt 1) { ($segs[1..($segs.Count - 1)] -join [System.IO.Path]::DirectorySeparatorChar) } else { '' }
    $skipDirs = [System.Collections.Generic.HashSet[string]]::new(
        [string[]]@('.git', '.hg', '.jj', '.svn', 'node_modules', '__pycache__', 'target'),
        [System.StringComparer]::OrdinalIgnoreCase
    )

    $visited = 0
    $seenScan = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($base in @($initRoot, $wdir, $PaneCwd)) {
        if (-not $base -or -not [System.IO.Directory]::Exists($base)) { continue }
        if (-not $seenScan.Add($base.TrimEnd('\', '/'))) { continue }
        $curLevel = [System.Collections.Generic.List[string]]::new()
        try {
            $rootItems = @([System.IO.Directory]::EnumerateFileSystemEntries($base) | Select-Object -First 129)
            if ($rootItems.Count -gt 128) { continue }
            foreach ($ri in $rootItems) {
                $leaf = [System.IO.Path]::GetFileName($ri)
                if ($leaf -and -not $skipDirs.Contains($leaf) -and [System.IO.Directory]::Exists($ri)) {
                    $curLevel.Add($ri)
                }
            }
        } catch {
            continue
        }

        $matchesFound = [System.Collections.Generic.List[string]]::new()
        for ($depth = 1; $depth -le 3; $depth++) {
            if ($curLevel.Count -eq 0 -or $visited -ge 128 -or $matchesFound.Count -gt 1) { break }
            $nextLevel = [System.Collections.Generic.List[string]]::new()
            foreach ($dPath in $curLevel) {
                if ($visited -ge 128) { break }
                $visited++
                try {
                    $entries = @([System.IO.Directory]::EnumerateFileSystemEntries($dPath) | Select-Object -First 129)
                    $capped = ($entries.Count -gt 128)
                    foreach ($ent in ($entries | Select-Object -First 128)) {
                        $eName = [System.IO.Path]::GetFileName($ent)
                        if ([string]::Equals($eName, $firstSeg, [System.StringComparison]::OrdinalIgnoreCase)) {
                            if (-not $restRel) {
                                if ([System.IO.File]::Exists($ent)) { $matchesFound.Add([System.IO.Path]::GetFullPath($ent)) }
                            } elseif ([System.IO.Directory]::Exists($ent)) {
                                $candFull = Join-Path $ent $restRel
                                if ([System.IO.File]::Exists($candFull)) { $matchesFound.Add([System.IO.Path]::GetFullPath($candFull)) }
                            }
                            if ($matchesFound.Count -gt 1) { break }
                        }
                        if (-not $capped -and $depth -lt 3 -and $eName -and -not $skipDirs.Contains($eName) -and [System.IO.Directory]::Exists($ent)) {
                            $nextLevel.Add($ent)
                        }
                    }
                } catch {
                    Write-Verbose "Bounded workspace scan skipped dir: $_"
                }
                if ($matchesFound.Count -gt 1) { break }
            }
            $curLevel = $nextLevel
        }
        if ($matchesFound.Count -eq 1) { return $matchesFound[0] }
        break
    }
    return ''
}

function Find-ZellijPaneLinkContext([string]$SessionName, [string]$PaneId, [string]$ClickedWord) {
    $result = @{ Osc8Href = ''; UnwrappedToken = '' }
    if (-not $ClickedWord) { return $result }
    $zellijBin = Resolve-ZellijExecutable
    if (-not $zellijBin) { return $result }

    $normPane = ConvertTo-ZellijPaneId $PaneId
    $actionArgs = if ($normPane) { @('dump-screen', '--ansi', '--pane-id', $normPane) } else { @('dump-screen', '--ansi') }
    $dumpRaw = try {
        Invoke-ZellijSessionAction -SessionName $SessionName -ActionArgs $actionArgs -PassThru
    } catch {
        ''
    }
    if (-not $dumpRaw) { return $result }

    $esc = [char]27
    $bel = [char]7
    $sgrRe = [regex]::new("${esc}\[[0-9;:]*[ -/]*[@-~]")
    $noSgr = $sgrRe.Replace($dumpRaw, '')
    $cleanWord = Format-CleanLinkToken $ClickedWord
    if (-not $cleanWord) { return $result }

    # 1. OSC 8 hyperlink recovery (\e]8;params;href\e\\label\e]8;;\e\\)
    $osc8Re = [regex]::new("${esc}\]8;[^;${esc}]*;([^${esc}${bel}\r\n]+)(?:${esc}\\|${bel})([^${esc}\r\n]+)${esc}\]8;;(?:${esc}\\|${bel})([^\s()\[\]{}<>`"',;*]*)")
    $oscMatches = @($osc8Re.Matches($noSgr))
    for ($mi = $oscMatches.Count - 1; $mi -ge 0; $mi--) {
        $m = $oscMatches[$mi]
        $href = $m.Groups[1].Value.Trim()
        $lbl = $m.Groups[2].Value
        $sfx = $m.Groups[3].Value
        $combined = Format-CleanLinkToken ($lbl + $sfx)
        $lblClean = Format-CleanLinkToken $lbl
        if ($combined -eq $cleanWord -or $lblClean -eq $cleanWord -or ($cleanWord.Length -ge 4 -and $combined.Contains($cleanWord))) {
            $result.Osc8Href = $href
            return $result
        }
    }

    # 2. Soft-wrapped path or URL stitching across adjacent viewport rows
    $plainText = [regex]::Replace($noSgr, "${esc}\][^\x07\x1b]*(?:${bel}|${esc}\\)", '')
    $rawLines = @($plainText -split "`r?`n")
    for ($li = 0; $li -lt $rawLines.Count; $li++) {
        $line = $rawLines[$li]
        if (-not $line.Contains($cleanWord)) { continue }
        $joined = $line.TrimEnd()
        if ($li -gt 0) {
            $prevTrim = $rawLines[$li - 1].TrimEnd()
            if ($prevTrim.Length -ge 56 -and $line -match '^\s*\S+') {
                $prevTail = ($prevTrim -split '\s+')[-1]
                $headPart = ($line.TrimStart() -split '\s+')[0]
                $candStitched = Format-CleanLinkToken ($prevTail + $headPart)
                if ($candStitched.Length -gt $cleanWord.Length -and $candStitched.Contains($cleanWord)) {
                    $result.UnwrappedToken = $candStitched
                    return $result
                }
            }
        }
        if ($li + 1 -lt $rawLines.Count -and ($joined.Length -ge 56 -or $cleanWord.EndsWith('/') -or $cleanWord.EndsWith('\') -or $cleanWord.EndsWith('-'))) {
            $nextTrim = $rawLines[$li + 1].TrimStart()
            if ($nextTrim -match '^([^\s()\[\]{}<>"`'']+)') {
                $nextHead = Format-CleanLinkToken $Matches[1]
                if ($nextHead -and $nextHead -notmatch '^(?:https?|file)://') {
                    $candForward = Format-CleanLinkToken ($cleanWord + $nextHead)
                    $result.UnwrappedToken = $candForward
                    return $result
                }
            }
        }
    }
    return $result
}

function Invoke-JumpNvimMarkdownAnchor([string]$AnchorSlug, [string]$SessionArg = '', [bool]$FocusEditor = $true) {
    $cleanSlug = if ($AnchorSlug) { $AnchorSlug.Trim().TrimStart('#') } else { '' }
    if (-not $cleanSlug) { return $false }
    try { $cleanSlug = [Uri]::UnescapeDataString($cleanSlug) } catch { Write-Verbose 'Anchor unescape skipped' }
    $sess = Resolve-TargetSession $SessionArg
    $meta = Read-SessionState $sess
    $pipePath = if ($meta -and $meta['pipe']) { [string]$meta['pipe'] } else { Get-SessionPipePath $sess }
    if (-not (Test-IdePipeLive $pipePath)) { return $false }

    $luaCode = @'
local slug = ...
local ok_l, links = pcall(require, "solarized.links")
if not ok_l or not links or not links.find_markdown_anchor_line then return 0 end
local lnum = links.find_markdown_anchor_line(0, slug)
if lnum and lnum > 0 then
    vim.schedule(function()
        pcall(vim.cmd, "silent! normal! m'")
        pcall(vim.cmd, string.format("keepjumps call cursor(%d, 1) | normal! ^zz", lnum))
    end)
    return lnum
end
return 0
'@
    $res = Invoke-NvimLua -PipePath $pipePath -LuaCode $luaCode -LuaArgs @($cleanSlug)
    if ($res.Success -and $res.Output -match '^[1-9][0-9]*$') {
        if ($FocusEditor) {
            [void](Select-IdeRolePane -SessionName $sess -Role 'editor' -EnsureOnly $true)
        }
        return $true
    }
    return $false
}

function Open-IdeExternalUrl([string]$Url) {
    if (-not $Url -or $Url -notmatch '^https?://\S+$') { return }
    if ($env:WS_IDE_DRY_OPEN_URL -eq '1') {
        Write-Output $Url
        return
    }
    if ($env:IDE_BROWSER -and $env:IDE_BROWSER.Trim()) {
        Start-Process -FilePath $env:IDE_BROWSER.Trim() -ArgumentList $Url
    } else {
        Start-Process $Url
    }
}

function Open-ResolvedIdeLinkTarget(
    [string]$TargetPath,
    [int]$LineNum,
    [string]$AnchorSlug,
    [string]$SessionName,
    [System.Collections.IDictionary]$Meta
) {
    if ([System.IO.Directory]::Exists($TargetPath)) {
        Invoke-IdeCd -TargetArg $TargetPath -SessionArg $SessionName
        return $true
    }
    if (-not [System.IO.File]::Exists($TargetPath)) {
        return $false
    }
    $fullTarget = [System.IO.Path]::GetFullPath($TargetPath)
    $batchTargets = @(@{ path = $fullTarget; line = $LineNum })
    $opened = Send-IdeEditorBatch -FileTargets $batchTargets -GlobalLine $LineNum -AnchorSlug $AnchorSlug -FocusEditor $true -SessionArg $SessionName
    if (-not $opened) {
        $pipePath = if ($Meta -and $Meta['pipe']) { [string]$Meta['pipe'] } else { Get-SessionPipePath $SessionName }
        $opened = Invoke-EditorNvimInIdleZellijPane -SessionName $SessionName -PipePath $pipePath -TargetPath $fullTarget -LineNum $LineNum -FocusEditor $true
        if ($opened -and $LineNum -le 0 -and $AnchorSlug) {
            [void](Invoke-JumpNvimMarkdownAnchor -AnchorSlug $AnchorSlug -SessionArg $SessionName -FocusEditor $false)
        }
    }
    return $opened
}

function Invoke-IdeOpenLink([string[]]$LinkArgs) {
    $pos = [System.Collections.Generic.List[string]]::new()
    $afterSep = $false
    foreach ($la in $LinkArgs) {
        $s = [string]$la
        if (-not $afterSep -and $s -eq '--') { $afterSep = $true; continue }
        $pos.Add($s)
    }
    if ($pos.Count -eq 0) { return }

    # Supports both 4-arg ws-bar call (<token> <cwd> <session> <pane_id>)
    # and 4-arg home-settings call (<href> <word> <cwd> [<session>]).
    $hrefArg = ''
    $wordArg = ''
    $cwdArg = ''
    $sessArg = ''
    $paneArg = ''

    if ($pos.Count -ge 4 -and $pos[3] -match '^(?:terminal_)?[0-9]+$' -and ($pos[1] -eq '' -or [System.IO.Path]::IsPathRooted($pos[1]) -or $pos[1].StartsWith('~'))) {
        $wordArg = $pos[0]
        $cwdArg = $pos[1]
        $sessArg = $pos[2]
        $paneArg = $pos[3]
    } elseif ($pos.Count -ge 3 -and ($pos[0] -eq '' -or $pos[0] -match '^(?:https?|file)://|^#') -and ($pos[2] -eq '' -or [System.IO.Path]::IsPathRooted($pos[2]) -or $pos[2].StartsWith('~') -or [System.IO.Directory]::Exists($pos[2]))) {
        $hrefArg = $pos[0]
        $wordArg = $pos[1]
        $cwdArg = $pos[2]
        if ($pos.Count -ge 4) { $sessArg = $pos[3] }
        if ($pos.Count -ge 5) { $paneArg = $pos[4] }
    } else {
        $wordArg = $pos[0]
        if ($pos.Count -ge 2) { $cwdArg = $pos[1] }
        if ($pos.Count -ge 3) { $sessArg = $pos[2] }
        if ($pos.Count -ge 4) { $paneArg = $pos[3] }
    }

    $sess = Resolve-TargetSession $sessArg
    $meta = Read-SessionState $sess
    $effCwd = if ($cwdArg -and [System.IO.Directory]::Exists($cwdArg)) {
        (Resolve-Path -LiteralPath $cwdArg).ProviderPath
    } elseif ($meta -and $meta['workdir'] -and [System.IO.Directory]::Exists([string]$meta['workdir'])) {
        [string]$meta['workdir']
    } elseif ($meta -and $meta['root'] -and [System.IO.Directory]::Exists([string]$meta['root'])) {
        [string]$meta['root']
    } else {
        (Get-Location).ProviderPath
    }

    if (-not (Get-Command Invoke-IdeResolveLinkHook -CommandType Function -ErrorAction SilentlyContinue)) {
        $hooksFile = Join-Path (Get-IdeLibDir) 'Hooks.ps1'
        if ([System.IO.File]::Exists($hooksFile)) { . $hooksFile }
    }

    # Unwrap Markdown `[label](dest)` or tool-call `Read(path)` syntax in $wordArg
    $rawWord = if ($wordArg) { $wordArg.Trim() } else { '' }
    $labelTarget = ''
    $labelLine = 0
    if ($rawWord -match '\[(`[^`\r\n]+`|[^\[\]\r\n]+)\]\(([^()\s]+(?:\([^()\s]*\)[^()\s]*)*)\)') {
        $rawLbl = Format-CleanLinkToken $Matches[1]
        $rawDst = Format-CleanLinkToken $Matches[2]
        $lblSpec = Split-IdeLinkTarget -RawTarget $rawLbl -BaseCwd $effCwd
        $labelTarget = $lblSpec.Path
        $labelLine = [int]$lblSpec.Line
        $rawWord = $rawDst
    } elseif ($rawWord -match '^(?:Read|Edit|Write|View|Update|Create|Bash)\((.+)$') {
        $inner = $Matches[1]
        if ($inner.EndsWith(')')) { $inner = $inner.Substring(0, $inner.Length - 1) }
        $rawWord = Format-CleanLinkToken $inner
    } else {
        $rawWord = Format-CleanLinkToken $rawWord
    }

    $primary = if ($hrefArg -and $hrefArg.Trim()) { Format-CleanLinkToken $hrefArg } else { $rawWord }
    if (-not $primary) { return }

    # 1. Pure `#anchor` jump in current Markdown buffer
    if ($primary.StartsWith('#')) {
        [void](Invoke-JumpNvimMarkdownAnchor -AnchorSlug $primary -SessionArg $sess -FocusEditor $true)
        return
    }

    # 2. Custom `links.ps1` (`Resolve-IdeLink`) rewrite
    if (-not $primary.StartsWith('file://', [System.StringComparison]::OrdinalIgnoreCase)) {
        $hookResolved = Invoke-IdeResolveLinkHook -Word $primary -Cwd $effCwd
        if ($hookResolved) {
            if ($hookResolved.StartsWith('file://', [System.StringComparison]::OrdinalIgnoreCase)) {
                $primary = $hookResolved
            } elseif ($hookResolved -match '^https?://\S+$') {
                Open-IdeExternalUrl $hookResolved
                return
            }
        }
    }

    # 3. Direct web URL
    if ($primary -match '^https?://\S+$') {
        if ($paneArg) {
            $ctx = Find-ZellijPaneLinkContext -SessionName $sess -PaneId $paneArg -ClickedWord $primary
            if ($ctx.UnwrappedToken -and $ctx.UnwrappedToken -match '^https?://\S+$') {
                $primary = $ctx.UnwrappedToken
            }
        }
        Open-IdeExternalUrl $primary
        return
    }

    # 4. Local or workspace file / directory target (checking OSC 8 first on bare filenames in Zellij panes so file:///...#L123 links preserve exact paths and line anchors)
    $spec = Split-IdeLinkTarget -RawTarget $primary -BaseCwd $effCwd
    $lineToUse = if ([int]$spec.Line -gt 0) {
        [int]$spec.Line
    } elseif ($labelLine -gt 0 -and (-not $labelTarget -or [string]::Equals([System.IO.Path]::GetFileName($spec.Path), [System.IO.Path]::GetFileName($labelTarget), [System.StringComparison]::OrdinalIgnoreCase))) {
        $labelLine
    } else {
        0
    }
    $cachedPaneCtx = $null
    if ($paneArg -and -not $hrefArg -and $lineToUse -le 0 -and -not $spec.Anchor -and -not $spec.Path.Contains('\') -and -not $spec.Path.Contains('/')) {
        $cachedPaneCtx = Find-ZellijPaneLinkContext -SessionName $sess -PaneId $paneArg -ClickedWord $primary
        if ($cachedPaneCtx.Osc8Href) {
            if ($cachedPaneCtx.Osc8Href -match '^https?://\S+$') {
                Open-IdeExternalUrl $cachedPaneCtx.Osc8Href
                return
            }
            $oscPreSpec = Split-IdeLinkTarget -RawTarget $cachedPaneCtx.Osc8Href -BaseCwd $effCwd
            $oscPreLine = if ([int]$oscPreSpec.Line -gt 0) { [int]$oscPreSpec.Line } else { $lineToUse }
            $oscPreFile = Find-WorkspaceLinkFile -Candidate $oscPreSpec.Path -PaneCwd $effCwd -Meta $meta
            if ($oscPreFile -and (Open-ResolvedIdeLinkTarget -TargetPath $oscPreFile -LineNum $oscPreLine -AnchorSlug $oscPreSpec.Anchor -SessionName $sess -Meta $meta)) {
                return
            }
        }
    }
    $resolvedFile = Find-WorkspaceLinkFile -Candidate $spec.Path -PaneCwd $effCwd -Meta $meta
    if ($resolvedFile -and (Open-ResolvedIdeLinkTarget -TargetPath $resolvedFile -LineNum $lineToUse -AnchorSlug $spec.Anchor -SessionName $sess -Meta $meta)) {
        return
    }

    # 5. OSC 8 hyperlink or soft-wrapped path recovery from the clicked Zellij pane
    if ($paneArg -or $env:ZELLIJ) {
        $ctx = if ($null -ne $cachedPaneCtx) { $cachedPaneCtx } else { Find-ZellijPaneLinkContext -SessionName $sess -PaneId $paneArg -ClickedWord $primary }
        if ($ctx.Osc8Href) {
            if ($ctx.Osc8Href -match '^https?://\S+$') {
                Open-IdeExternalUrl $ctx.Osc8Href
                return
            }
            $oscSpec = Split-IdeLinkTarget -RawTarget $ctx.Osc8Href -BaseCwd $effCwd
            $oscLine = if ([int]$oscSpec.Line -gt 0) { [int]$oscSpec.Line } else { $lineToUse }
            $oscFile = Find-WorkspaceLinkFile -Candidate $oscSpec.Path -PaneCwd $effCwd -Meta $meta
            if ($oscFile -and (Open-ResolvedIdeLinkTarget -TargetPath $oscFile -LineNum $oscLine -AnchorSlug $oscSpec.Anchor -SessionName $sess -Meta $meta)) {
                return
            }
        }
        if ($ctx.UnwrappedToken -and $ctx.UnwrappedToken -ne $primary) {
            if ($ctx.UnwrappedToken -match '^https?://\S+$') {
                Open-IdeExternalUrl $ctx.UnwrappedToken
                return
            }
            $wrapSpec = Split-IdeLinkTarget -RawTarget $ctx.UnwrappedToken -BaseCwd $effCwd
            $wrapFile = Find-WorkspaceLinkFile -Candidate $wrapSpec.Path -PaneCwd $effCwd -Meta $meta
            if ($wrapFile -and (Open-ResolvedIdeLinkTarget -TargetPath $wrapFile -LineNum ([int]$wrapSpec.Line) -AnchorSlug $wrapSpec.Anchor -SessionName $sess -Meta $meta)) {
                return
            }
        }
    }

    # 6. Fallback to Markdown bracket label if destination could not be resolved
    if ($labelTarget -and $labelTarget -ne $spec.Path) {
        $lblResolved = Find-WorkspaceLinkFile -Candidate $labelTarget -PaneCwd $effCwd -Meta $meta
        if ($lblResolved) {
            [void](Open-ResolvedIdeLinkTarget -TargetPath $lblResolved -LineNum $labelLine -AnchorSlug '' -SessionName $sess -Meta $meta)
        }
    }
}
