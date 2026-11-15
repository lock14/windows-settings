## Description

Please provide a concise summary of the changes introduced in this pull request, including motivation and context.

## Type of Change

- [ ] 🐛 Bug fix (non-breaking change which fixes an issue)
- [ ] ✨ New feature (non-breaking change which adds functionality)
- [ ] 💥 Breaking change (fix or feature that alters existing commands, flags, or configuration paths)
- [ ] ⚡ Performance optimization (shell startup latency, disk caching, or non-blocking prompt improvements)
- [ ] 🎨 Theme / Syntax / UI refinement (17-theme palette engine, `bat` grammars, Tree-sitter `.scm` queries, or Zellij layouts)
- [ ] 📝 Documentation update
- [ ] 🔧 Tooling / CI / Setup configuration

## Repository Architecture & Safety Checklist

- [ ] **Portability & Zero Personal Paths:** Uses canonical environment variables (`$HOME`, `$env:LOCALAPPDATA`, `$env:APPDATA`, `$PROFILE`) and `Join-Path`; contains zero hardcoded personal paths.
- [ ] **Line-Ending Discipline:** `.ps1`, `.psm1`, `.psd1`, `.cmd`, and `.bat` use `CRLF`; `.md`, `.json`, `.kdl`, `.yml`, `.yaml`, `.toml`, `.lua`, `.scm`, `.theme`, and `.txt` use `LF`.
- [ ] **Idempotency, Backups & `-DryRun`:** Provisioning/theme/IDE/update mutations preserve unrelated user settings, create `.bak_<timestamp>` backups only when content differs, and honor `-DryRun` / `--dry-run`.
- [ ] **Dual-Execution & Shell Parity:** Any `bin/` utility changes keep `<name>.ps1` + `<name>.cmd`, PowerShell wrappers, tab completions, and `cmd.exe` `doskey` macros synchronized.
- [ ] **Shell Startup Performance:** Introduces zero `Get-ChildItem -Recurse` traversals, `Get-Command` PATH loops, or synchronous child-process spawns on the `WindowsSettings` module import path.
- [ ] **Universal Color Contract:** Any theme, syntax, or query updates adhere to the 3-Tier Semantic Color Contract across all 17 palettes.

## Verification & Testing

- [ ] Ran `Invoke-ScriptAnalyzer -Path . -Recurse -Settings ./PSScriptAnalyzerSettings.psd1` with zero errors or warnings.
- [ ] Ran `$null | pwsh -NoProfile -File ./tests/test_settings.ps1` and verified all 8 test modules pass.
- [ ] Added or updated automated validation tests in `tests/test_settings.ps1` for new or modified behavior.
- [ ] Synchronized documentation (`README.md`, `AGENTS.md`, and `llms.txt`) in the same pull request.
