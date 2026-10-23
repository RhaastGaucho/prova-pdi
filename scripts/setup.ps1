$ErrorActionPreference = 'Stop'
$ProjectDir = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $ProjectDir
$LocalNode = Join-Path $ProjectDir '.tools\node'
$env:Path = "$LocalNode;$env:Path"

function Test-Node {
    if (!(Get-Command node -ErrorAction SilentlyContinue) -or !(Get-Command npm.cmd -ErrorAction SilentlyContinue)) { return $false }
    & node -e 'const [major, minor] = process.versions.node.split(".").map(Number); process.exit(major >= 22 && (major !== 22 || minor >= 12) ? 0 : 1)'
    return $LASTEXITCODE -eq 0
}

if (!(Test-Node)) {
    $MachineArch = $env:PROCESSOR_ARCHITECTURE
    if ($env:PROCESSOR_ARCHITEW6432) { $MachineArch = $env:PROCESSOR_ARCHITEW6432 }
    $Arch = switch ($MachineArch) { 'AMD64' { 'x64' } 'ARM64' { 'arm64' } default { 'unsupported' } }
    if ($Arch -notin @('x64', 'arm64')) { throw 'Instale Node.js 22.12+ e npm manualmente para esta arquitetura e execute novamente.' }
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $TempDir = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())
    New-Item -ItemType Directory -Path $TempDir | Out-Null
    try {
        $BaseUrl = 'https://nodejs.org/dist/latest-v22.x'
        Write-Host 'Baixando Node.js 22 e npm do site oficial...'
        $Manifest = (Invoke-WebRequest "$BaseUrl/SHASUMS256.txt" -UseBasicParsing).Content
        if ($Manifest -is [byte[]]) { $Manifest = [Text.Encoding]::UTF8.GetString($Manifest) }
        $Entry = ($Manifest -split "`n" | Where-Object { $_.Trim() -match "\s+node-v[0-9.]+-win-$Arch\.zip$" } | Select-Object -First 1)
        if (!$Entry) { throw 'Arquivo do Node nao encontrado.' }
        $ExpectedHash, $Archive = $Entry.Trim() -split '\s+'
        $ZipPath = Join-Path $TempDir $Archive
        Invoke-WebRequest "$BaseUrl/$Archive" -OutFile $ZipPath -UseBasicParsing
        if ((Get-FileHash $ZipPath -Algorithm SHA256).Hash -ne $ExpectedHash) { throw 'Checksum do Node invalido; execute novamente.' }
        Expand-Archive -LiteralPath $ZipPath -DestinationPath $TempDir
        New-Item -ItemType Directory -Path $LocalNode -Force | Out-Null
        Copy-Item -Path (Join-Path $TempDir ($Archive -replace '\.zip$', '') '*') -Destination $LocalNode -Recurse -Force
    } finally {
        Remove-Item -LiteralPath $TempDir -Recurse -Force
    }
}
if (!(Test-Node)) { throw 'Nao foi possivel configurar Node.js 22.12+ e npm.' }
Write-Host "Node $(& node --version) / npm $(& npm.cmd --version)"
$LockHash = (Get-FileHash package-lock.json -Algorithm SHA256).Hash
$Marker = 'node_modules/.setup-lock.sha256.windows'
$PreviousPreference = $ErrorActionPreference
try {
    $ErrorActionPreference = 'Continue'
    & npm.cmd ls --include=dev --all *> $null
    $DependenciesOk = $LASTEXITCODE -eq 0
} finally {
    $ErrorActionPreference = $PreviousPreference
}
foreach ($Tool in @('vite', 'tsc', 'vitest')) {
    if (!(Test-Path "node_modules/.bin/$Tool.cmd")) { $DependenciesOk = $false }
}
if (!(Test-Path $Marker) -or (Get-Content $Marker -ErrorAction SilentlyContinue) -ne $LockHash) { $DependenciesOk = $false }
if (!$DependenciesOk) {
    Write-Host 'Instalando dependencias do projeto...'
    & npm.cmd ci --include=dev
    if ($LASTEXITCODE -ne 0) { throw 'Falha ao instalar dependencias. Confira sua conexao e execute novamente.' }
    Set-Content -Path $Marker -Value $LockHash
} else {
    Write-Host 'As dependencias do projeto ja estao instaladas.'
}
Write-Host "`nPreparacao concluida. Para iniciar neste terminal: npm.cmd run dev"
Write-Host 'Abra o endereco informado pelo Vite (normalmente http://127.0.0.1:5173/).'
