# Captures the four tabs from the real phone.
#
# Android is the only supported target. This replaces the web/Chrome harness:
# the emulator/browser render path was costing build time and producing
# findings that never applied to the device (dart2js integer limits, canvas
# font differences).
#
# Usage: powershell -File tool/device_shots.ps1
$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $PSScriptRoot
$adb = Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe'
$serial = $env:DSH_DEVICE_SERIAL
if (-not $serial) { $serial = 'RZCY10WA89M' }
$pkg = 'com.amartyaay.finnance_app'

if (-not (Test-Path $adb)) { throw "adb not found at $adb" }
$devices = & $adb devices
if (-not ($devices -match $serial)) { throw "Device $serial not connected. Run: adb devices" }

$outDir = Join-Path $root 'docs\shots'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

& $adb -s $serial shell am force-stop $pkg | Out-Null
& $adb -s $serial shell am start -n "$pkg/.MainActivity" | Out-Null
Start-Sleep -Seconds 12

# The four destinations sit on the bottom bar; these are 1080-wide coordinates.
$tabs = [ordered]@{
  'home'     = 135
  'activity' = 405
  'cards'    = 675
  'insights' = 945
}
$navY = 2143

foreach ($name in $tabs.Keys) {
  & $adb -s $serial shell input tap $tabs[$name] $navY | Out-Null
  Start-Sleep -Seconds 3
  $remote = "/sdcard/shot_$name.png"
  & $adb -s $serial shell screencap -p $remote | Out-Null
  & $adb -s $serial pull $remote (Join-Path $outDir "device-$name.png") 2>$null | Out-Null
  & $adb -s $serial shell rm -f $remote | Out-Null
  Write-Output "captured docs/shots/device-$name.png"
}

# Settings is a pushed route from the Home avatar.
& $adb -s $serial shell input tap 135 $navY | Out-Null
Start-Sleep -Seconds 2
& $adb -s $serial shell input tap 867 173 | Out-Null
Start-Sleep -Seconds 3
& $adb -s $serial shell screencap -p /sdcard/shot_settings.png | Out-Null
& $adb -s $serial pull /sdcard/shot_settings.png (Join-Path $outDir 'device-settings.png') 2>$null | Out-Null
& $adb -s $serial shell rm -f /sdcard/shot_settings.png | Out-Null
Write-Output 'captured docs/shots/device-settings.png'
