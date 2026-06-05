param(
  [Parameter(Mandatory)][string]$InstanceConfig
)

$ErrorActionPreference = "Stop"

. "$PSScriptRoot\..\config\$InstanceConfig.ps1"

$WindowsUsername = $env:USERNAME
$LinuxUsername = $WindowsUsername.ToLower() -replace '[^a-z0-9_-]', ''
if (-not $LinuxUsername) { Write-Error "Could not derive a valid Linux username from '$WindowsUsername'"; exit 1 }

# Read Git identity from Windows Git installation
$GitName  = git config --global user.name
$GitEmail = git config --global user.email
if (-not $GitName)  { Write-Error "git config --global user.name is not set"; exit 1 }
if (-not $GitEmail) { Write-Error "git config --global user.email is not set"; exit 1 }

# Derive Git credential manager path from the git.exe location
$GitExe = (Get-Command git).Source
$GitRoot = Split-Path (Split-Path $GitExe -Parent) -Parent
$CredManager = "$GitRoot\mingw64\bin\git-credential-manager.exe"
if (-not (Test-Path $CredManager)) { Write-Error "git-credential-manager.exe not found at $CredManager"; exit 1 }
$CredManagerWsl = '/mnt/' + $CredManager[0].ToString().ToLower() + '/' + $CredManager.Substring(3) -replace '\\', '/' -replace ' ', '\ '

# Substitute template
$template = Get-Content "$PSScriptRoot\..\distros\$DistroTemplatePath\user-data.template" -Raw

$template = $template `
    -replace '__LINUX_USERNAME__',      $LinuxUsername `
    -replace '__GIT_NAME__',            $GitName `
    -replace '__GIT_EMAIL__',           $GitEmail `
    -replace '__WINDOWS_USERNAME__',    $WindowsUsername `
    -replace '__GIT_CREDENTIAL_MANAGER__', $CredManagerWsl

$userDataDir = "$PSScriptRoot\..\user-data"
New-Item -ItemType Directory -Force -Path $userDataDir | Out-Null
$userDataPath = "$userDataDir\$InstanceName.user-data"
$template | Set-Content $userDataPath -NoNewline
Write-Host "Generated user-data for $InstanceName"

# Provision
Write-Host "[1/6] Terminating $InstanceName..."
wsl --terminate $InstanceName

Write-Host "[2/6] Unregistering $InstanceName..."
wsl --unregister $InstanceName

Write-Host "[3/6] Copying cloud-init user-data..."
$cloudInitDir = "$env:USERPROFILE\.cloud-init"
New-Item -ItemType Directory -Force -Path $cloudInitDir | Out-Null
Remove-Item -Force "$cloudInitDir\*" -ErrorAction SilentlyContinue
Copy-Item -Force $userDataPath "$cloudInitDir\$InstanceName.user-data"

Write-Host "[4/6] Installing $DistroInstallName as $InstanceName..."
wsl --install $DistroInstallName --name $InstanceName --no-launch
if ($LASTEXITCODE -ne 0) { Write-Error "WSL install failed"; exit 1 }

Write-Host "[5/6] Waiting for cloud-init to finish..."
wsl -d $InstanceName --user root -- cloud-init status --wait

Write-Host "[6/6] Launching $InstanceName..."
wsl -d $InstanceName
