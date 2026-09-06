$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($env:RUSTDESK_PASSWORD)) { throw "RUSTDESK_PASSWORD or RDP_PASSWORD repository secret is required." }
if ($env:RUSTDESK_PASSWORD.Length -lt 6) { throw "RustDesk password must contain at least 6 characters." }

$release = Invoke-RestMethod -Uri "https://api.github.com/repos/rustdesk/rustdesk/releases/latest" -Headers @{ "User-Agent" = "GitHub-Actions-RustDesk-Installer" }
$asset = $release.assets | Where-Object { $_.name -match '(?i)(x86_64|x64)\.msi$' } | Select-Object -First 1
if (-not $asset) { throw "Could not find a RustDesk Windows x64 MSI in the latest release." }

$download = "$env:TEMP\rustdesk.msi"
Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $download
if (-not (Test-Path $download)) { throw "RustDesk MSI download failed." }

Get-Process -Name "rustdesk" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

$log = "$env:TEMP\rustdesk-msi.log"
$arguments = "/i `"$download`" /qn /norestart /l*v `"$log`""
$installer = Start-Process -FilePath "msiexec.exe" -ArgumentList $arguments -Wait -PassThru -WindowStyle Hidden
if ($installer.ExitCode -ne 0) {
    if (Test-Path $log) { Get-Content $log -Tail 80 }
    throw "RustDesk MSI installation failed with exit code $($installer.ExitCode)."
}

$rustdesk = "C:\Program Files\RustDesk\rustdesk.exe"
Start-Sleep -Seconds 8
if (-not (Test-Path $rustdesk)) { throw "RustDesk executable was not found after MSI installation." }

$service = Get-Service | Where-Object { $_.Name -like "RustDesk*" -or $_.DisplayName -like "RustDesk*" } | Select-Object -First 1
if (-not $service) { throw "RustDesk service was not created by the MSI installer." }

for ($attempt = 1; $attempt -le 4; $attempt++) {
    $service = Get-Service -Name $service.Name
    if ($service.Status -eq "Running") { break }
    try { Start-Service -Name $service.Name -ErrorAction Stop } catch { Write-Host "Service start attempt $attempt failed: $($_.Exception.Message)" }
    Start-Sleep -Seconds 5
}
$service = Get-Service -Name $service.Name
if ($service.Status -ne "Running") { throw "RustDesk service is not running. Final status: $($service.Status)." }

$passwordResult = Start-Process -FilePath $rustdesk -ArgumentList "--password `"$env:RUSTDESK_PASSWORD`"" -Wait -PassThru -WindowStyle Hidden
if ($passwordResult.ExitCode -ne 0) { throw "RustDesk password configuration failed with exit code $($passwordResult.ExitCode)." }

$idFile = "$env:TEMP\rustdesk-id.txt"
$idErr = "$env:TEMP\rustdesk-id-error.txt"
Remove-Item $idFile,$idErr -Force -ErrorAction SilentlyContinue
Start-Process -FilePath $rustdesk -ArgumentList "--get-id" -Wait -PassThru -WindowStyle Hidden -RedirectStandardOutput $idFile -RedirectStandardError $idErr | Out-Null
$id = if (Test-Path $idFile) { (Get-Content $idFile -Raw).Trim() } else { "" }
if ([string]::IsNullOrWhiteSpace($id)) { throw "RustDesk ID could not be obtained." }

Write-Host "============================================"
Write-Host "RustDesk Remote Access"
Write-Host "RustDesk ID : $id"
Write-Host "Password    : stored in GitHub Secrets"
Write-Host "Service     : $($service.Name) / $((Get-Service -Name $service.Name).Status)"
Write-Host "============================================"
