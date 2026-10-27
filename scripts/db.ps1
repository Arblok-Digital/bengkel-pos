# Jembatan Windows -> WSL untuk mengelola Supabase lokal project bengkel-pos.
#
#   npm run db:up      nyalakan database + relay (dipakai otomatis oleh npm run dev)
#   npm run db:down    matikan container bengkel-pos, data tetap aman
#   npm run db:status  lihat container, kesehatan API/relay, pemakaian RAM
#   npm run db:reset   migrasi + seed ulang (dipakai sebelum e2e)
#   npm run wsl:off    db:down lalu matikan seluruh WSL (bebaskan RAM penuh)
#
# Logika sebenarnya ada di scripts/db.sh (dijalankan di dalam WSL).
# Catatan: file ini sengaja ASCII saja agar aman dibaca Windows PowerShell 5.1.

param(
  [Parameter(Position = 0)]
  [ValidateSet("up", "down", "status", "reset", "off")]
  [string]$Action = "status"
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$distro = if ($env:BENGKEL_WSL_DISTRO) { $env:BENGKEL_WSL_DISTRO } else { "Ubuntu" }

function ConvertTo-WslPath {
  param([string]$WindowsPath)

  $full = (Resolve-Path -LiteralPath $WindowsPath).Path
  if ($full -match '^([A-Za-z]):(.*)$') {
    $drive = $Matches[1].ToLowerInvariant()
    $rest = $Matches[2] -replace '\\', '/'
    return "/mnt/$drive$rest"
  }
  throw "Path bukan drive Windows, tidak bisa dipetakan ke WSL: $full"
}

$wslRoot = ConvertTo-WslPath $root
$dbScript = "$wslRoot/scripts/db.sh"

if ($Action -eq "off") {
  & wsl -d $distro -e bash $dbScript down
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

  Write-Host "Mematikan WSL ($distro): semua service di dalamnya ikut berhenti ..."
  wsl --shutdown
  Write-Host "WSL mati. Nyalakan lagi dengan 'npm run db:up' atau 'npm run dev'."
  exit 0
}

& wsl -d $distro -e bash $dbScript $Action
exit $LASTEXITCODE
