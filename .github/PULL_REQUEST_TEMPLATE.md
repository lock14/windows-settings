## Summary

Explain the problem or limitation in the prior code and why this design was chosen.

## Architecture and safety checklist

- [ ] **Portability and zero personal paths**: Uses canonical environment variables (`$HOME`, `$env:LOCALAPPDATA`, `$env:APPDATA`, `$PROFILE`) and `Join-Path`; contains zero hardcoded personal paths.
- [ ] **Line-ending discipline**: `.ps1`, `.psm1`, `.psd1`, `.cmd`, `.bat`, and `.doskey` use `CRLF`; `.md`, `.json`, `.kdl`, `.yml`, `.yaml`, `.toml`, `.lua`, `.scm`, `.theme`, `.txt`, and `LICENSE` use `LF`.
- [ ] **Idempotency, backups, and dry-run**: Provisioning, theme, IDE, and update mutations preserve unrelated user settings, create `.bak_<timestamp>` backups only when content differs, and honor `-DryRun` or `--dry-run`.
- [ ] **Dual-execution and shell parity**: Any `bin/` utility changes keep `<name>.ps1`, `<name>.cmd`, PowerShell wrappers, tab completions, and `cmd.exe` `doskey` macros synchronized.
- [ ] **Shell startup performance**: Introduces zero `Get-ChildItem -Recurse` traversals, `Get-Command` `PATH` scans, or synchronous child-process spawns on the `WindowsSettings` module import path.
- [ ] **Universal color contract**: Any theme, syntax, or query updates adhere to the 3-tier semantic color contract across all 17 palettes.

## Verification

- [ ] Ran `Invoke-ScriptAnalyzer -Path . -Recurse -Settings ./PSScriptAnalyzerSettings.psd1` with zero errors or warnings.
- [ ] Ran `$null | pwsh -NoProfile -File ./tests/test_settings.ps1` and verified all 8 test modules pass.
- [ ] Added or updated automated validation tests in `tests/test_settings.ps1` for new or modified behavior.
- [ ] Updated and synchronized documentation (`README.md`, `CONTRIBUTING.md`, `AGENTS.md`, `llms.txt`).
