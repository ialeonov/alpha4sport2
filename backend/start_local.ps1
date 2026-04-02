$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root

$dataDir = Join-Path $root "data"
$uploadsDir = Join-Path $root "uploads"

New-Item -ItemType Directory -Force -Path $dataDir | Out-Null
New-Item -ItemType Directory -Force -Path $uploadsDir | Out-Null

$env:DATABASE_URL = "sqlite:///" + ($dataDir -replace "\\", "/") + "/alpha4sport-dev.db"
$env:UPLOAD_DIR = $uploadsDir
$env:ALLOWED_ORIGINS = "http://localhost:3000,http://localhost:5173,http://localhost:8080"

Write-Host "Using DATABASE_URL=$env:DATABASE_URL"
Write-Host "Applying migrations..."
python -m alembic upgrade head

Write-Host "Starting backend on http://localhost:8000"
python -m uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
