param(
  [Parameter(Mandatory)][string]$InstanceConfig,
  [string]$Branch = "main"
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

# Derive VS Code path from the installed executable (resolve the bash wrapper alongside code.cmd)
$VsCodeShell = (Get-Command code).Source -replace '\.cmd$', ''
if (-not (Test-Path $VsCodeShell)) { Write-Error "VS Code shell wrapper not found at $VsCodeShell"; exit 1 }
$VsCodeWsl = '/mnt/' + $VsCodeShell[0].ToString().ToLower() + '/' + $VsCodeShell.Substring(3) -replace '\\', '/' -replace ' ', '\ '

# Derive gh.exe path from the installed executable
$GhExe = (Get-Command gh).Source
if (-not (Test-Path $GhExe)) { Write-Error "gh.exe not found at $GhExe"; exit 1 }
$GhWsl = '/mnt/' + $GhExe[0].ToString().ToLower() + '/' + $GhExe.Substring(3) -replace '\\', '/' -replace ' ', '\ '

# Derive Edge path from the installed executable
$EdgeExe = "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe"
if (-not $EdgeExe) { Write-Error "msedge.exe not found"; exit 1 }
$EdgeWsl = '/mnt/' + $EdgeExe[0].ToString().ToLower() + '/' + $EdgeExe.Substring(3) -replace '\\', '/' -replace ' ', '\ ' -replace '\(', '\(' -replace '\)', '\)'

# Substitute template
$template = Get-Content "$PSScriptRoot\..\distros\$DistroTemplatePath\user-data.template" -Raw

$template = $template `
    -replace '__LINUX_USERNAME__',            $LinuxUsername `
    -replace '__GIT_NAME__',                  $GitName `
    -replace '__GIT_EMAIL__',                 $GitEmail `
    -replace '__GIT_CREDENTIAL_MANAGER__',    $CredManagerWsl `
    -replace '__VSCODE__',                    $VsCodeWsl `
    -replace '__GH__',                        $GhWsl `
    -replace '__EDGE__',                      $EdgeWsl `
    -replace '__BRANCH__',                    $Branch

$userDataDir = "$PSScriptRoot\..\user-data"
New-Item -ItemType Directory -Force -Path $userDataDir | Out-Null
$userDataPath = "$userDataDir\$InstanceName.user-data"
$template | Set-Content $userDataPath -NoNewline
Write-Host "Generated user-data for $InstanceName"

# Provision
Write-Host "[1/6] Terminating $InstanceName..."
$result = Start-Process wsl -ArgumentList "--terminate", $InstanceName -Wait -PassThru -WindowStyle Hidden
if ($result.ExitCode -ne 0 -and $result.ExitCode -ne -1) {
    Write-Error "Unexpected error terminating $InstanceName (exit code $($result.ExitCode))"; exit 1
}

Write-Host "[2/6] Unregistering $InstanceName..."
$result = Start-Process wsl -ArgumentList "--unregister", $InstanceName -Wait -PassThru -WindowStyle Hidden
if ($result.ExitCode -ne 0 -and $result.ExitCode -ne -1) {
    Write-Error "Unexpected error unregistering $InstanceName (exit code $($result.ExitCode))"; exit 1
}

Write-Host "[3/6] Copying cloud-init user-data..."
$cloudInitDir = "$env:USERPROFILE\.cloud-init"
New-Item -ItemType Directory -Force -Path $cloudInitDir | Out-Null
Copy-Item -Force $userDataPath "$cloudInitDir\$InstanceName.user-data"

Write-Host "[4/6] Installing $DistroInstallName as $InstanceName..."
wsl --install $DistroInstallName --name $InstanceName --no-launch
if ($LASTEXITCODE -ne 0) { Write-Error "WSL install failed"; exit 1 }

Write-Host "[5/6] Waiting for cloud-init to finish..."
wsl -d $InstanceName --user root -- cloud-init status --wait

Write-Host "[6/6] Launching $InstanceName..."
wsl -d $InstanceName
