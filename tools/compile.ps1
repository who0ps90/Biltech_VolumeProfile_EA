param(
 [string]$MetaEditor = 'C:\Program Files\XM Global MT5\MetaEditor64.exe'
)
$ErrorActionPreference = 'Stop'
$bvpRoot = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path -LiteralPath $MetaEditor)) { throw "MetaEditor missing: $MetaEditor. Pass -MetaEditor with your installed path." }
$bvpTargets = @(
 @{ Source = 'Biltech_VolumeProfile_EA.mq5'; Log = 'compile-main.log' },
 @{ Source = 'tests\BiltechVP_Tests.mq5'; Log = 'compile-native-tests.log' }
)
foreach ($bvpTarget in $bvpTargets) {
 $bvpSource = Join-Path $bvpRoot $bvpTarget.Source
 $bvpLog = Join-Path (Join-Path $bvpRoot 'logs') $bvpTarget.Log
 $bvpStarted = Get-Date
 $bvpArgs = @('/compile:"' + $bvpSource + '"', '/log:"' + $bvpLog + '"')
 $bvpProcess = Start-Process -FilePath $MetaEditor -ArgumentList $bvpArgs -WindowStyle Hidden -PassThru -Wait
 if (-not (Test-Path -LiteralPath $bvpLog)) { throw "Compiler did not produce $bvpLog" }
 $bvpOutput = Get-Content -LiteralPath $bvpLog -Raw
 $bvpBinary = [IO.Path]::ChangeExtension($bvpSource, '.ex5')
 if ($bvpOutput -notmatch 'Result: 0 errors, 0 warnings' -or -not (Test-Path -LiteralPath $bvpBinary) -or (Get-Item -LiteralPath $bvpBinary).LastWriteTime -lt $bvpStarted) {
  Write-Output $bvpOutput
  throw "Compilation failed, warnings present, or binary is not fresh: $bvpSource"
 }
 Write-Output "$($bvpTarget.Source): 0 errors, 0 warnings; fresh EX5 verified"
}
# This script only runs MetaEditor. It never starts terminal64 or logs into an account.
