# Run / build the Flutter port with the same env as the Expo app.
#
#   .\run_dev.ps1                       -> flutter run
#   .\run_dev.ps1 build apk --debug     -> flutter build apk --debug
#   .\run_dev.ps1 -EnvFile C:\x\.env run -d emulator-5554
#   .\run_dev.ps1 -Target production build apk --debug
#                                       -> live servers, whatever .env's ENVIRONMENT says
#                                          (a phone can't reach the dev PC's 192.168.x URLs)
#   .\run_dev.ps1 -DevHost 192.168.137.73 build apk --debug
#                                       -> dev URLs' http://<ipv4> host swapped for the PC's
#                                          current Wi-Fi IP (phone on the same Wi-Fi)
#
# Reads ..\mobile\.env, strips the EXPO_PUBLIC_ prefix and passes the variables
# as dart-defines (read by lib\core\env.dart via String.fromEnvironment).
#   * *_SECRET variables are ALWAYS skipped: secrets must never ship in a client.
#   * Only names declared in lib\core\env.dart are passed.
#   * Only the half matching ENVIRONMENT is passed (plain names in "development",
#     *_LIVE names otherwise) - Env/Api pick the same half at runtime.
# Flutter forwards every define (base64) on the gradlew.bat command line, and
# all ~157 .env entries exceed cmd.exe's 8191-char limit ("The command line is
# too long."). Defines travel through a temp JSON file in %TEMP%
# (--dart-define-from-file) that is deleted afterwards.
[CmdletBinding(PositionalBinding = $false)]
param(
  [Parameter()][string]$EnvFile = (Join-Path $PSScriptRoot "..\mobile\.env"),
  [Parameter()][string]$Target = "",
  [Parameter()][string]$DevHost = "",
  [Parameter(ValueFromRemainingArguments = $true)][string[]]$FlutterArgs
)
$ErrorActionPreference = "Stop"
if (-not (Test-Path $EnvFile)) { throw "env file not found: $EnvFile" }

$envDart = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot "lib\core\env.dart")
$allowed = @{}
foreach ($m in [regex]::Matches($envDart, "fromEnvironment\('([A-Z0-9_]+)'\)")) { $allowed[$m.Groups[1].Value] = $true }

$all = [ordered]@{}
foreach ($raw in Get-Content -LiteralPath $EnvFile) {
  $line = $raw.Trim()
  if ($line -eq "" -or $line.StartsWith("#") -or -not $line.Contains("=")) { continue }
  $idx = $line.IndexOf("=")
  $key = $line.Substring(0, $idx).Trim() -replace "^EXPO_PUBLIC_", ""
  $value = $line.Substring($idx + 1)
  if ($key -eq "") { continue }
  if ($key -like "*_SECRET") { Write-Host "skipping secret $key"; continue }
  if ($value -match '^"(.*)"$' -or $value -match "^'(.*)'$") { $value = $Matches[1] }
  if ($DevHost) { $value = $value -replace '^(https?://)\d{1,3}(\.\d{1,3}){3}(?=[:/]|$)', "`${1}$DevHost" }
  $all[$key] = $value
}
if ($Target) { $all["ENVIRONMENT"] = $Target }
$environment = $all["ENVIRONMENT"]

$defines = [ordered]@{}
# .PSBase.Keys: .env has a KEYS variable, and $all.Keys would return that entry.
foreach ($key in @($all.PSBase.Keys)) {
  if (-not $allowed.ContainsKey($key)) { continue }
  if ($key -ne "ENVIRONMENT") {
    if ($environment -eq "development") {
      if ($key -like "*_LIVE") { continue }
    } elseif ($key -notlike "*_LIVE" -and $allowed.ContainsKey("${key}_LIVE")) { continue }
  }
  $defines[$key] = $all[$key]
}

$tmp = Join-Path ([IO.Path]::GetTempPath()) ("uko_defines_" + [Guid]::NewGuid().ToString("N") + ".json")
try {
  $json = $defines | ConvertTo-Json -Compress
  [IO.File]::WriteAllText($tmp, $json, (New-Object Text.UTF8Encoding($false)))
  if (-not $FlutterArgs -or $FlutterArgs.Count -eq 0) { $FlutterArgs = @("run") }
  Push-Location $PSScriptRoot
  try {
    Write-Host "flutter $($FlutterArgs -join ' ') --dart-define-from-file=<$($defines.Count) defines from $EnvFile, ENVIRONMENT=$environment>"
    & flutter @FlutterArgs "--dart-define-from-file=$tmp"
    exit $LASTEXITCODE
  } finally { Pop-Location }
} finally {
  Remove-Item -LiteralPath $tmp -ErrorAction SilentlyContinue
}
