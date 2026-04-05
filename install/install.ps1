$ErrorActionPreference = "Stop"

$BaseUrl = if ($env:CODEDB_URL) { $env:CODEDB_URL } else { "https://codedb.codegraff.com" }
$InstallDir = if ($env:CODEDB_DIR) { $env:CODEDB_DIR } else { Join-Path $env:LOCALAPPDATA "codedb\bin" }

function Get-Platform {
  $arch = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString().ToLowerInvariant()
  switch ($arch) {
    "x64" { $a = "x86_64" }
    "arm64" { $a = "arm64" }
    default { throw "Unsupported architecture: $arch" }
  }
  return "windows-$a"
}

function Get-Version {
  if ($env:CODEDB_VERSION) { return $env:CODEDB_VERSION }
  $resp = Invoke-WebRequest -UseBasicParsing -Uri "$BaseUrl/latest.json"
  $obj = $resp.Content | ConvertFrom-Json
  if (-not $obj.version) { throw "Could not fetch latest version" }
  return $obj.version
}

function Register-JsonConfig($path, $bin) {
  $obj = @{}
  if (Test-Path $path) {
    try { $obj = Get-Content $path -Raw | ConvertFrom-Json -AsHashtable } catch { $obj = @{} }
  }
  if (-not $obj.ContainsKey("mcpServers")) { $obj["mcpServers"] = @{} }
  $obj["mcpServers"]["codedb"] = @{ command = $bin; args = @("mcp") }
  New-Item -ItemType Directory -Force -Path (Split-Path $path -Parent) | Out-Null
  ($obj | ConvertTo-Json -Depth 10) + "`n" | Set-Content -Path $path -Encoding UTF8
}

function Register-TomlConfig($path, $bin) {
  New-Item -ItemType Directory -Force -Path (Split-Path $path -Parent) | Out-Null
  if (Test-Path $path -and (Get-Content $path -Raw) -match "\[mcp_servers\.codedb\]") { return }
  Add-Content -Path $path -Value @"

[mcp_servers.codedb]
command = "$bin"
args = ["mcp"]
startup_timeout_sec = 30
"@
}

$platform = Get-Platform
$version = Get-Version
$ext = ".exe"
$asset = "codedb-$platform$ext"
$url = "$BaseUrl/v$version/$asset"
$checksumUrl = "$BaseUrl/v$version/checksums.sha256"

New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
$tmp = Join-Path $env:TEMP "codedb.tmp.$PID.exe"
$dest = Join-Path $InstallDir "codedb.exe"

Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $tmp

try {
  $checksums = Invoke-WebRequest -UseBasicParsing -Uri $checksumUrl
  $line = ($checksums.Content -split "`n" | Where-Object { $_ -match [regex]::Escape($asset) } | Select-Object -First 1)
  if ($line) {
    $expected = ($line -split "\s+")[0].Trim()
    $actual = (Get-FileHash -Algorithm SHA256 -Path $tmp).Hash.ToLowerInvariant()
    if ($actual -ne $expected.ToLowerInvariant()) {
      Remove-Item -Force $tmp -ErrorAction SilentlyContinue
      throw "Checksum mismatch"
    }
  }
} catch {}

Move-Item -Force $tmp $dest

Register-JsonConfig (Join-Path $env:USERPROFILE ".claude.json") $dest
Register-TomlConfig (Join-Path $env:APPDATA "codex\config.toml") $dest

$gemini = Join-Path $env:APPDATA "gemini\settings.json"
if (Test-Path (Split-Path $gemini -Parent)) { Register-JsonConfig $gemini $dest }
$cursor = Join-Path $env:APPDATA "Cursor\User\mcp.json"
if (Test-Path (Split-Path $cursor -Parent)) { Register-JsonConfig $cursor $dest }

Write-Host "installed -> $dest"
Write-Host "Add to PATH if needed: $InstallDir"
