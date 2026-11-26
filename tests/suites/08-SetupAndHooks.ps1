# =============================================================
# Suite 8: Modular Setup, Zellij Deploy, 3-Agent AI Hooks & Dry-Run
# =============================================================
Write-Host "`n[8/8] Testing Modular Setup, Backup Policy, 3-Agent AI Hooks & Dry-Run..." -ForegroundColor Yellow

$sandboxDir = Join-Path ([System.IO.Path]::GetTempPath()) ("ws_sandbox_" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $sandboxDir | Out-Null

try {
    # 1. Verify modular setup/{lib,modules}/ structure
    $expectedSetupFiles = @(
        'setup\lib\Log.ps1',
        'setup\lib\Deploy.ps1',
        'setup\lib\Env.ps1',
        'setup\modules\00-Packages.ps1',
        'setup\modules\10-Dotfiles.ps1',
        'setup\modules\20-Bin.ps1',
        'setup\modules\30-Fonts.ps1',
        'setup\modules\40-Mise.ps1',
        'setup\modules\50-Nvim.ps1',
        'setup\modules\60-Shell.ps1',
        'setup\modules\70-Terminal.ps1',
        'setup\modules\75-AiHooks.ps1',
        'setup\modules\99-Uninstall.ps1'
    )
    $missingSetup = @($expectedSetupFiles | Where-Object { -not (Test-Path -LiteralPath (Join-Path $RootDir $_) -PathType Leaf) })
    if ($missingSetup.Count -eq 0) {
        Add-TestPass 'Modular setup/lib/ (3 files) and setup/modules/ (10 stages: 00 through 99) present'
    } else {
        Add-TestFail 'Modular setup/ structure' "Missing: $($missingSetup -join ', ')"
    }

    # 2. Deploy-ConfigFile backup & idempotency test
    . (Join-Path $RootDir 'setup\lib\Log.ps1')
    . (Join-Path $RootDir 'setup\lib\Deploy.ps1')

    $mockTarget = Join-Path $sandboxDir 'settings.json'
    Set-Content -LiteralPath $mockTarget -Value 'initial configuration'
    $srcFrag = Join-Path $RootDir 'config\terminal\windows-settings.json'
    Deploy-ConfigFile -Name 'Test Fragment' -SourcePath $srcFrag -DestinationPath $mockTarget *>$null
    $baks1 = @(Get-ChildItem -LiteralPath $sandboxDir -Filter 'settings.json.bak_*')
    Deploy-ConfigFile -Name 'Test Fragment' -SourcePath $srcFrag -DestinationPath $mockTarget *>$null
    $baks2 = @(Get-ChildItem -LiteralPath $sandboxDir -Filter 'settings.json.bak_*')
    if ($baks1.Count -eq 1 -and $baks2.Count -eq 1) {
        Add-TestPass 'Deploy-ConfigFile creates .bak_<timestamp> on diff and skips redundant backups on identical re-run'
    } else {
        Add-TestFail 'Deploy-ConfigFile backup idempotency' "baks1=$($baks1.Count), baks2=$($baks2.Count)"
    }

    # 3. Sync-ZellijPluginPermission & Deploy-ZellijConfig
    $mockPermFile = Join-Path $sandboxDir 'permissions.kdl'
    [System.IO.File]::WriteAllText($mockPermFile, "`"other-plugin`" {`n    ReadApplicationState`n}`n", [System.Text.UTF8Encoding]::new($false))
    Sync-ZellijPluginPermission -PermissionsPath $mockPermFile *>$null
    $permRaw1 = [System.IO.File]::ReadAllText($mockPermFile)
    $permBackups1 = @(Get-ChildItem -LiteralPath $sandboxDir -Filter 'permissions.kdl.bak_*')
    Sync-ZellijPluginPermission -PermissionsPath $mockPermFile *>$null
    $permBackups2 = @(Get-ChildItem -LiteralPath $sandboxDir -Filter 'permissions.kdl.bak_*')
    Sync-ZellijPluginPermission -PermissionsPath $mockPermFile -Remove *>$null
    $permRawRemoved = [System.IO.File]::ReadAllText($mockPermFile)
    if (-not $permRaw1.Contains("`r`n") -and $permRaw1 -match 'windows-settings-bar' -and
        $permBackups1.Count -eq 1 -and $permBackups2.Count -eq 1 -and
        $permRawRemoved -match '"other-plugin"' -and $permRawRemoved -notmatch 'windows-settings-bar') {
        Add-TestPass 'Sync-ZellijPluginPermission pre-seeds LF permissions idempotently and removes cleanly'
    } else {
        Add-TestFail 'Sync-ZellijPluginPermission' "Unexpected content or backup counts ($($permBackups1.Count), $($permBackups2.Count))"
    }

    $srcZellijConfig = Join-Path $RootDir 'config\zellij\config.kdl'
    $mockZellijConfig = Join-Path $sandboxDir 'config.kdl'
    Deploy-ZellijConfig -SourcePath $srcZellijConfig -DestinationPath $mockZellijConfig -UseWasmBar $false *>$null
    $cfgFallback = [System.IO.File]::ReadAllText($mockZellijConfig)
    Deploy-ZellijConfig -SourcePath $srcZellijConfig -DestinationPath $mockZellijConfig -UseWasmBar $true *>$null
    $cfgWasm = [System.IO.File]::ReadAllText($mockZellijConfig)
    if (-not $cfgFallback.Contains("`r`n") -and $cfgFallback -match 'location="zellij:bars"' -and
        -not $cfgWasm.Contains("`r`n") -and $cfgWasm -match 'location="file:windows-settings-bar"' -and $cfgWasm -match 'name\s+"ws-ide-role"') {
        Add-TestPass 'Deploy-ZellijConfig switches cleanly between zellij:bars fallback and file:windows-settings-bar WASM bar'
    } else {
        Add-TestFail 'Deploy-ZellijConfig bar switching' 'Fallback or WASM bar rewrite failed'
    }

    # 4. 75-AiHooks.ps1 3-Agent Reconciliation, Idempotency & Clean Removal
    $aiHooksScript = Join-Path $RootDir 'setup\modules\75-AiHooks.ps1'
    $mockAgy = Join-Path $sandboxDir 'hooks.json'
    $mockClaude = Join-Path $sandboxDir 'claude-settings.json'
    $mockCodex = Join-Path $sandboxDir 'codex-config.toml'

    [System.IO.File]::WriteAllText($mockAgy, '{"windows-settings-ide":{"Stop":[{"type":"command","command":"old"}]},"custom-hook":{"Stop":[]}}', [System.Text.UTF8Encoding]::new($false))
    [System.IO.File]::WriteAllText($mockClaude, '{"theme":"dark","hooks":{"Stop":[{"hooks":[{"type":"command","command":"echo user-stop"},{"type":"command","command":"ide.cmd --agent-state done"}]}]}}', [System.Text.UTF8Encoding]::new($false))
    [System.IO.File]::WriteAllText($mockCodex, "[model]`nname = `"o3`"`n", [System.Text.UTF8Encoding]::new($false))

    & $aiHooksScript -RepoRoot $RootDir -AgyHooksPath $mockAgy -ClaudeSettingsPath $mockClaude -CodexConfigPath $mockCodex *>$null
    $agyAfter = [System.IO.File]::ReadAllText($mockAgy)
    $claudeAfter = [System.IO.File]::ReadAllText($mockClaude)
    $codexAfter = [System.IO.File]::ReadAllText($mockCodex)
    $hookBaks1 = @(Get-ChildItem -LiteralPath $sandboxDir -Filter '*.bak_*').Count

    & $aiHooksScript -RepoRoot $RootDir -AgyHooksPath $mockAgy -ClaudeSettingsPath $mockClaude -CodexConfigPath $mockCodex *>$null
    $hookBaks2 = @(Get-ChildItem -LiteralPath $sandboxDir -Filter '*.bak_*').Count

    & $aiHooksScript -RepoRoot $RootDir -AgyHooksPath $mockAgy -ClaudeSettingsPath $mockClaude -CodexConfigPath $mockCodex -Remove *>$null
    $agyRemoved = [System.IO.File]::ReadAllText($mockAgy)
    $claudeRemoved = [System.IO.File]::ReadAllText($mockClaude)
    $codexRemoved = [System.IO.File]::ReadAllText($mockCodex)

    if ($agyAfter -match '"ide-state"' -and $agyAfter -notmatch '"windows-settings-ide"' -and $agyAfter -match '"ask_question"' -and $agyAfter -match '"custom-hook"' -and
        $claudeAfter -match 'cmd\.exe /d /c ide\.cmd state approval' -and $claudeAfter -match 'echo user-stop' -and $claudeAfter -notmatch '--agent-state' -and
        $codexAfter -match '(?m)^notify\s*=\s*\[.*ide\.ps1",\s*"state",\s*"done"\]' -and
        $hookBaks1 -eq $hookBaks2 -and
        $agyRemoved -notmatch '"ide-state"' -and $agyRemoved -match '"custom-hook"' -and
        $claudeRemoved -match 'echo user-stop' -and $claudeRemoved -notmatch 'ide\.cmd state' -and
        $codexRemoved -notmatch 'notify\s*=' -and $codexRemoved -match '\[model\]') {
        Add-TestPass '75-AiHooks.ps1 idempotently reconciles and cleanly removes Antigravity (5 events), Claude Code, and Codex hooks'
    } else {
        Add-TestFail '75-AiHooks.ps1 reconciliation' 'Unexpected hook merge, idempotency, or -Remove output'
    }

    # 5. Consolidated setup.ps1 & bootstrap.ps1 -DryRun matrix + invalid flag rejection
    $setupScriptPath = Join-Path $RootDir 'setup.ps1'
    $bootstrapScriptPath = Join-Path $RootDir 'bootstrap.ps1'

    foreach ($cliSpec in @(
        @{ Label = '-DryRun (full default)';           Args = @('-DryRun') },
        @{ Label = '-DryRun -User';                    Args = @('-DryRun', '-User') },
        @{ Label = '-DryRun -SystemOnly';              Args = @('-DryRun', '-SystemOnly') },
        @{ Label = '-DryRun -UseDSC';                  Args = @('-DryRun', '-UseDSC') },
        @{ Label = '-DryRun -Gui vscode,terminal';     Args = @('-DryRun', '-Gui', 'vscode,terminal') },
        @{ Label = '-DryRun -Skip cmd,hooks';          Args = @('-DryRun', '-Skip', 'cmd,hooks') },
        @{ Label = '-DryRun -Theme dracula';           Args = @('-DryRun', '-Theme', 'dracula') },
        @{ Label = '-DryRun -Theme holiday';           Args = @('-DryRun', '-Theme', 'holiday') },
        @{ Label = '-DryRun -Uninstall';               Args = @('-DryRun', '-Uninstall') },
        @{ Label = '-DryRun -Uninstall dotfiles,bin';  Args = @('-DryRun', '-Uninstall', 'dotfiles,bin') }
    )) {
        $cliArgs = $cliSpec.Args
        & $setupScriptPath @cliArgs *>$null
        if ($LASTEXITCODE -eq 0) {
            Add-TestPass "setup.ps1 executes cleanly in $($cliSpec.Label) mode"
        } else {
            Add-TestFail "setup.ps1 $($cliSpec.Label)" "Exited with code $LASTEXITCODE"
        }
    }

    & pwsh -NoProfile -File $setupScriptPath -DotfilesOnly 2>$null
    $legacyFlagExit = $LASTEXITCODE
    if ($legacyFlagExit -ne 0) {
        Add-TestPass 'setup.ps1 rejects retired legacy flags (-DotfilesOnly fails fast)'
    } else {
        Add-TestFail 'setup.ps1 strict CLI hygiene' 'Expected retired -DotfilesOnly flag to fail fast'
    }

    & $bootstrapScriptPath -DryRun -User -Skip fonts,hooks *>$null
    if ($LASTEXITCODE -eq 0) {
        Add-TestPass 'bootstrap.ps1 executes cleanly in -DryRun -User -Skip fonts,hooks mode'
    } else {
        Add-TestFail 'bootstrap.ps1 -DryRun' "Exited with code $LASTEXITCODE"
    }
} finally {
    if (Test-Path -LiteralPath $sandboxDir) {
        Remove-Item -Recurse -Force -LiteralPath $sandboxDir -ErrorAction SilentlyContinue
    }
}
