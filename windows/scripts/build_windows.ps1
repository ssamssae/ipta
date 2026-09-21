param([string]$Version = "0.1.23", [string]$TestModel = "", [string]$TestAudio = "")
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root
if (!(Test-Path "Helpers/whisper-cli.exe")) { throw "Place whisper-cli.exe and its DLLs in windows/Helpers first" }
python -m pip install -r requirements-windows.txt pyinstaller
if ($LASTEXITCODE -ne 0) { throw "Dependency install failed" }
python -m PyInstaller --noconfirm --clean --onefile --windowed --name "Ipta-$Version-windows" --icon ipta.ico --add-data "ipta.ico;." --add-binary "Helpers/*;Helpers" ipta_win/__main__.py
if ($LASTEXITCODE -ne 0) { throw "Build failed" }
$Exe = Join-Path $Root "dist/Ipta-$Version-windows.exe"
$Report = Join-Path $Root "dist/selftest.txt"
$env:IPTA_SUPPORT_DIR = Join-Path $env:TEMP "ipta-package-selftest"
$TestArgs = @("--selftest-output", "`"$Report`"")
if ($TestModel -or $TestAudio) {
    if (!(Test-Path $TestModel) -or !(Test-Path $TestAudio)) { throw "Both test model and audio are required" }
    $TestArgs += @("--selftest-model", "`"$TestModel`"", "--selftest-audio", "`"$TestAudio`"")
}
$Test = Start-Process -FilePath $Exe -ArgumentList $TestArgs -Wait -PassThru
if ($Test.ExitCode -ne 0) { throw "Packaged selftest failed: $($Test.ExitCode)" }
Get-Content $Report
(Get-FileHash $Exe -Algorithm SHA256).Hash.ToLower() + "  " + (Split-Path $Exe -Leaf) | Set-Content "$Exe.sha256"
Write-Host $Exe
