param(
    [string]$Server = "root@109.196.102.140",
    [string]$ServerProjectPath = "/opt/alpha4sport",
    [string]$ServerFrontendPath = "/var/www/fit.ileonov.ru",
    [string]$Branch = "main",
    [string]$CommitMessage = "",
    [switch]$SkipFlutterBuild,
    [switch]$SkipGitCommit,
    [switch]$SkipFrontendUpload,
    [switch]$SkipBackendDeploy
)

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$frontendPath = Join-Path $projectRoot "frontend"
$frontendBuildPath = Join-Path $frontendPath "build\web"

function Invoke-Step {
    param(
        [string]$Message,
        [scriptblock]$Action
    )

    Write-Host ""
    Write-Host "==> $Message" -ForegroundColor Cyan
    & $Action
}

Invoke-Step "Switching to project root: $projectRoot" {
    Set-Location $projectRoot
}

if (-not $SkipFlutterBuild) {
    Invoke-Step "Building Flutter web frontend" {
        Set-Location $frontendPath
        flutter pub get
        flutter build web
        Set-Location $projectRoot
    }
}

Invoke-Step "Checking Git status" {
    git status --short
}

Invoke-Step "Pushing code to GitHub" {
    git add .

    $hasStagedOrModifiedChanges = git status --porcelain
    if ($hasStagedOrModifiedChanges) {
        if ($SkipGitCommit) {
            Write-Host "Skipping commit because -SkipGitCommit was provided." -ForegroundColor Yellow
        }
        else {
            $message = $CommitMessage
            if ([string]::IsNullOrWhiteSpace($message)) {
                $message = "Deploy update $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
            }

            git commit -m $message
        }
    }
    else {
        Write-Host "No local changes to commit." -ForegroundColor Yellow
    }

    git push origin $Branch
}

if (-not $SkipFrontendUpload) {
    Invoke-Step "Uploading frontend build to VPS" {
        if (-not (Test-Path $frontendBuildPath)) {
            throw "Frontend build folder not found: $frontendBuildPath"
        }

        ssh $Server "mkdir -p $ServerFrontendPath"
        scp -r "$frontendBuildPath\*" "${Server}:$ServerFrontendPath/"
    }
}

if (-not $SkipBackendDeploy) {
    Invoke-Step "Updating backend on VPS" {
        $remoteCommand = "cd $ServerProjectPath && git pull origin $Branch && docker compose -f deploy/docker-compose.prod.yml up -d --build"
        ssh $Server $remoteCommand
    }
}

Write-Host ""
Write-Host "Deployment completed." -ForegroundColor Green
