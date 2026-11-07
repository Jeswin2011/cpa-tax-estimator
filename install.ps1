# CPA Tax Estimator installer for Windows.
#   irm https://jeswin2011.github.io/cpa-tax-estimator/install.ps1 | iex
# Downloads the latest release from GitHub, checks its SHA-256, and installs it for the current user (no admin needed).
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue' # Invoke-WebRequest is much faster without the progress bar
$repo = 'Jeswin2011/cpa-tax-estimator'
$app = 'CPA Tax Estimator'

function Fail($msg) { Write-Host "Error: $msg" -ForegroundColor Red; throw $msg }

if (-not [Environment]::Is64BitOperatingSystem) { Fail 'only 64-bit Windows is supported.' }

Write-Host "Finding the latest version of $app..."
try {
  $release = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/releases/latest" -Headers @{ Accept = 'application/vnd.github+json' }
} catch { Fail 'could not reach GitHub. Check your internet connection.' }
$asset = $release.assets | Where-Object { $_.name -match 'Setup.*\.exe$' } | Select-Object -First 1
if (-not $asset) { Fail 'no Windows installer was found in the latest release.' }

$setup = Join-Path $env:TEMP $asset.name
Write-Host "Downloading $($asset.name) ($($release.tag_name), $([math]::Round($asset.size / 1MB)) MB)..."
Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $setup -UseBasicParsing

try {
  if ($asset.digest -match '^sha256:([0-9a-f]+)$') {
    $actual = (Get-FileHash $setup -Algorithm SHA256).Hash.ToLower()
    if ($actual -ne $Matches[1]) { Fail "the download's checksum doesn't match GitHub's. Nothing was installed." }
    Write-Host 'Checksum verified.'
  } else {
    Write-Host 'Warning: GitHub did not publish a checksum for this file, so it could not be verified.' -ForegroundColor Yellow
  }

  Write-Host 'Installing...'
  $p = Start-Process -FilePath $setup -ArgumentList '/S' -Wait -PassThru
  if ($p.ExitCode -ne 0) { Fail "the installer exited with code $($p.ExitCode)." }
} finally {
  Remove-Item $setup -Force -ErrorAction SilentlyContinue
}

$exe = Get-ChildItem "$env:LOCALAPPDATA\Programs" -Recurse -Filter "$app.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
Write-Host ''
Write-Host "Installed $app $($release.tag_name)." -ForegroundColor Green
if ($exe) {
  Write-Host "Starting it now. Next time, open it from the Start menu."
  Start-Process $exe.FullName
}
