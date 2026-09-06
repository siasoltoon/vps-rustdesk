$ErrorActionPreference = "Stop"

# RustDesk password can be supplied through RUSTDESK_PASSWORD. The workflow falls back
# to the existing RDP_PASSWORD secret so no second credential is mandatory.
if ([string]::IsNullOrWhiteSpace($env:RUSTDESK_PASSWORD)) {
    throw "RUSTDESK_PASSWORD or RDP_PASSWORD repository secret is required."
}
if ($env:RUSTDESK_PASSWORD.Length -lt 6) {
    throw "RustDesk password must contain at least 6 characters."
}

$installDir = "C:\Program Files\RustDesk"
$rustdesk = "$installDir\rustdesk.exe"
$download = "$env:TEMP\rustdesk.exe"

Write-Host "Resolving latest RustDesk Windows x64 release..."
$release = Invoke-RestMethod -Uri "https://api.github.com/repos/rustdesk/rustdesk/releases/latest" -Headers @{ "User-Agent" = "GitHub-Actions-RustDesk-Installer" }
$asset = $release.assets | Where-Object { $_.name -match '(?i)(x86_64|x64).*\.exe$' } | Select-Object -First 1
if (-not $asset) {
    throw "Could not find a RustDesk Windows x64 installer in the latest release."
}

Write-Host "Downloading RustDesk $($release.tag_name)..."
Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $download
if (-not (Test-Path $download)) { throw "RustDesk download failed." }

New-Item -ItemType Directory -Path $installDir -Force | Out-Null
Copy-Item -Path $download -Destination $rustdesk -Force

Write-Host "Installing RustDesk service..."
& $rustdesk --install-service
$installExit = $LASTEXITCODE
if ($installExit -ne 0) {
    Write-Host "RustDesk service install returned exit code $installExit; checking service state."
}

Start-Sleep -Seconds 8
$service = Get-Service | Where-Object { $_.Name -like "RustDesk*" -or $_.DisplayName -like "RustDesk*" } | Select-Object -First 1
if (-not $service) { throw "RustDesk Windows service was not found after installation." }

if ($service.Status -ne "Running") {
    Start-Service -Name $service.Name -ErrorAction Stop
    Start-Sleep -Seconds 5
}

Write-Host "Setting RustDesk permanent password..."
& $rustdesk --password "$env:RUSTDESK_PASSWORD"
if ($LASTEXITCODE -ne 0) { throw "RustDesk password configuration failed." }

Start-Sleep -Seconds 5
$id = (& $rustdesk --get-id 2>$null | Out-String).Trim()
if ([string]::IsNullOrWhiteSpace($id)) { throw "RustDesk ID could not be obtained." }

Write-Host "============================================"
Write-Host "RustDesk Remote Access"
Write-Host "============================================"
Write-Host "RustDesk ID : $id"
Write-Host "Password    : stored in GitHub Secrets"
Write-Host "Service     : $($service.Name) / $((Get-Service -Name $service.Name).Status)"
Write-Host "============================================"
