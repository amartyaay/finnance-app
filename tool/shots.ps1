# Captures screenshots of the web build for visual review.
# The app is loaded inside a fixed-size iframe: headless Chrome's --window-size
# alone does not make Flutter web re-layout, which clipped the right edge.
# Usage: powershell -File tool/shots.ps1
$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $PSScriptRoot
$web = Join-Path $root 'build\web'
if (-not (Test-Path $web)) { throw 'Build the web app first: flutter build web' }

$chrome = 'C:\Program Files\Google\Chrome\Application\chrome.exe'
if (-not (Test-Path $chrome)) { throw 'Chrome not found' }

$outDir = Join-Path $root 'docs\shots'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$width = 412
$height = 915

$server = Start-Process -FilePath 'python' -ArgumentList '-m','http.server','8123','--directory',$web -PassThru -WindowStyle Hidden
Start-Sleep -Seconds 2
try {
  $tabs = [ordered]@{ 'home' = 0; 'activity' = 1; 'cards' = 2; 'insights' = 3 }
  foreach ($name in $tabs.Keys) {
    $frame = @"
<!doctype html><html><head><meta charset="utf-8"><style>
html,body{margin:0;padding:0;background:#ffffff}
iframe{border:0;display:block;width:${width}px;height:${height}px}
</style></head><body>
<iframe src="index.html?demo=1&v=$((Get-Date).Ticks)&tab=$($tabs[$name])"></iframe>
</body></html>
"@
    $framePath = Join-Path $web "shot-$name.html"
    [System.IO.File]::WriteAllText($framePath, $frame, (New-Object System.Text.UTF8Encoding($false)))

    $url = "http://127.0.0.1:8123/shot-$name.html"
    $out = Join-Path $outDir "$name.png"
    & $chrome --headless=new --incognito --disable-gpu --hide-scrollbars --window-size=$width,$height `
      --virtual-time-budget=30000 --screenshot=$out $url 2>&1 | Out-Null
    Write-Output "captured $out"
  }
} finally {
  Stop-Process -Id $server.Id -Force -ErrorAction SilentlyContinue
}
