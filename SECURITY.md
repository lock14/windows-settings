# Security policy

## Supported versions

Security updates are maintained for the latest `main` branch of `windows-settings`:

| Version | Supported |
| :--- | :--- |
| `main` | Yes |

## Reporting a vulnerability

If you discover a security vulnerability in `windows-settings` (such as command injection, unsafe path resolution, unintended file overwrites, credential exposure, or Named Pipe and hook execution flaws), report it privately using the following steps:

1. Do not report security vulnerabilities through public GitHub issues, pull requests, or discussions.
2. Submit a report using [GitHub Private Vulnerability Reporting](https://github.com/lock14/windows-settings/security/advisories/new) on this repository.
3. If private vulnerability reporting is unavailable, contact the repository maintainer directly via GitHub.

### What to include in your report

Include the following details to help triage and resolve the issue:

* A clear description of the vulnerability and affected component (such as `setup.ps1`, `bootstrap.ps1`, `module/WindowsSettings.psm1`, `config/cmd/autorun.cmd`, `bin/ide.ps1`, `bin/theme.ps1`, or GitHub Actions workflows).
* Numbered steps or a minimal PowerShell or `cmd.exe` command sequence to reproduce the issue.
* An impact assessment (such as arbitrary command execution, configuration clobbering, or environment and token exposure).
* Any suggested fixes or mitigations.

### Response timeline

* Receipt of a vulnerability report is acknowledged within 48 hours.
* A status update and remediation timeline are provided within 7 days.
* Once a fix is verified on `main`, a security advisory is published crediting the reporter unless anonymity is requested.
