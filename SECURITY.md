# Security Policy

## Supported Versions

Security updates are maintained for the latest `main` branch of `windows-settings`:

| Version | Supported          |
| ------- | ------------------ |
| `main`  | :white_check_mark: |

## Reporting a Vulnerability

We take the security of workstation automation, shell initialization, and developer tooling seriously. If you discover a security vulnerability in `windows-settings` (for example, command injection, unsafe path resolution, unintended file overwrites, credential exposure, or Named Pipe / hook execution flaws), please report it responsibly:

1. **Do not** report security vulnerabilities through public GitHub issues, pull requests, or discussions.
2. Submit a report privately using [GitHub Private Vulnerability Reporting](https://github.com/lock14/windows-settings/security/advisories/new).
3. If private vulnerability reporting is unavailable, contact the repository maintainer directly via GitHub.

### What to Include in Your Report

To help triage and resolve the issue quickly, please include:

* A clear description of the vulnerability and affected component (e.g., `setup.ps1`, `bootstrap.ps1`, `module/WindowsSettings.psm1`, `config/cmd/autorun.cmd`, `bin/ide.ps1`, `bin/theme.ps1`, or GitHub Actions workflows).
* Minimal steps or PowerShell / `cmd.exe` commands to reproduce the issue.
* Impact assessment (e.g., arbitrary command execution, configuration clobbering, environment or token exposure).
* Any suggested fixes or mitigations.

### Response Timeline

* Receipt of your vulnerability report will be acknowledged within 48 hours.
* A status update and remediation plan will be provided within 7 days.
* Once a fix is verified on `main`, a security advisory will be published crediting the reporter (unless anonymity is requested).
