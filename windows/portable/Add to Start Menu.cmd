@echo off
REM Runs setup-shortcuts.ps1 beside this file. -ExecutionPolicy Bypass is scoped
REM to this one process: it does not change the machine's policy.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup-shortcuts.ps1"
