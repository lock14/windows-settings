@echo off
pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0repeat-until-success.ps1" %*
