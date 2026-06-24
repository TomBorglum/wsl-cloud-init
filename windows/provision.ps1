param(
  [Parameter(Mandatory)][string]$DistroTemplatePath,
  [Parameter(Mandatory)][string]$DistroInstallName,
  [Parameter(Mandatory)][string]$InstanceName,
  [string]$Branch = "main",
  [switch]$Force
)

$ErrorActionPreference = "Stop"

# Only pinned LTS distro names are supported. The bare "Ubuntu" name installs whatever
# Ubuntu the Store currently ships, which the in-distro setup does not support
# (e.g. Docker has no apt repo for its codename). Add new names here as they are validated.
$SupportedDistros = @('Ubuntu-24.04', 'Ubuntu-22.04')
if ($SupportedDistros -notcontains $DistroInstallName) {
  Write-Error @"
Unsupported -DistroInstallName '$DistroInstallName'.
Only pinned LTS versions are supported. Supported: $($SupportedDistros -join ', ')
"@
  exit 1
}

. "$PSScriptRoot\lib\Wsl.ps1"
. "$PSScriptRoot\lib\Credentials.ps1"

$exists = Test-WslInstanceExists $InstanceName
if ($exists -and -not $Force) {
  Write-Host "Instance '$InstanceName' already exists. Re-run with -Force to overwrite (this destroys it)."
  exit 1
}

try {
  $Context7ApiKey = Get-WindowsCredential "wsl-cloud-init:CONTEXT7_API_KEY"
} catch {
  Write-Error @"
$_
Add it via: Control Panel -> Credential Manager -> Windows Credentials -> Add a generic credential
  Internet or network address : wsl-cloud-init:CONTEXT7_API_KEY
  Username                    : wsl-cloud-init
  Password                    : <your-key>
"@
  exit 1
}

try {
  $GhToken = Get-WindowsCredential "wsl-cloud-init:GH_TOKEN"
} catch {
  Write-Error @"
$_
Add it via: Control Panel -> Credential Manager -> Windows Credentials -> Add a generic credential
  Internet or network address : wsl-cloud-init:GH_TOKEN
  Username                    : wsl-cloud-init
  Password                    : <your-token>
"@
  exit 1
}

$WindowsUsername = $env:USERNAME
$TargetUser = $WindowsUsername.ToLower() -replace '[^a-z0-9_-]', ''
if (-not $TargetUser) { Write-Error "Could not derive a valid Linux username from '$WindowsUsername'"; exit 1 }

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
$CredManagerWsl = ConvertTo-WslPath $CredManager

# Derive VS Code path from the installed executable (resolve the bash wrapper alongside code.cmd)
$VsCodeShell = (Get-Command code).Source -replace '\.cmd$', ''
if (-not (Test-Path $VsCodeShell)) { Write-Error "VS Code shell wrapper not found at $VsCodeShell"; exit 1 }
$VsCodeWsl = ConvertTo-WslPath $VsCodeShell

# Derive PowerShell path from the installed executable
$PwshExe = (Get-Command powershell).Source
if (-not (Test-Path $PwshExe)) { Write-Error "powershell.exe not found at $PwshExe"; exit 1 }
$PwshWsl = ConvertTo-WslPath $PwshExe

# Substitute template
$template = Get-Content "$PSScriptRoot\..\distros\$DistroTemplatePath\user-data.template" -Raw

# Use String.Replace (literal) rather than -replace (regex): a secret containing
# '$' would otherwise be interpreted as a regex group backreference and corrupted.
$template = $template.
    Replace('__TARGET_USER__',             $TargetUser).
    Replace('__GIT_NAME__',                $GitName).
    Replace('__GIT_EMAIL__',               $GitEmail).
    Replace('__GIT_CREDENTIAL_MANAGER__',  $CredManagerWsl).
    Replace('__VSCODE__',                  $VsCodeWsl).
    Replace('__POWERSHELL__',              $PwshWsl).
    Replace('__BRANCH__',                  $Branch).
    Replace('__CONTEXT7_API_KEY__',        $Context7ApiKey).
    Replace('__GH_TOKEN__',                $GhToken)

$userDataDir = "$PSScriptRoot\..\user-data"
New-Item -ItemType Directory -Force -Path $userDataDir | Out-Null
$userDataPath = "$userDataDir\$InstanceName.user-data"
$template | Set-Content $userDataPath -NoNewline
Write-Host "Generated user-data for $InstanceName"

# Provision
if ($exists) {
    Write-Host "Unregistering existing $InstanceName..."
    $result = Start-Process wsl -ArgumentList "--unregister", $InstanceName -Wait -PassThru -WindowStyle Hidden
    if ($result.ExitCode -ne 0) {
        Write-Error "Failed to unregister $InstanceName (exit code $($result.ExitCode))"; exit 1
    }
}

Write-Host "[1/4] Copying cloud-init user-data..."
$cloudInitDir = "$env:USERPROFILE\.cloud-init"
New-Item -ItemType Directory -Force -Path $cloudInitDir | Out-Null
Copy-Item -Force $userDataPath "$cloudInitDir\$InstanceName.user-data"

Write-Host "[2/4] Installing $DistroInstallName as $InstanceName..."
wsl --install $DistroInstallName --name $InstanceName --no-launch
if ($LASTEXITCODE -ne 0) { Write-Error "WSL install failed"; exit 1 }

Write-Host "[3/4] Waiting for cloud-init to finish..."
wsl -d $InstanceName --user root -- cloud-init status --wait

Write-Host "[4/4] Launching $InstanceName..."
wsl -d $InstanceName
