& powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Setup.ps1')
exit $LASTEXITCODE
