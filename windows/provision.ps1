param(
  [Parameter(Mandatory)][string]$DistroTemplatePath,
  [Parameter(Mandatory)][string]$DistroInstallName,
  [string]$InstanceName,
  [switch]$InstallClaudeCode,
  [switch]$InstallGitConfig,
  [switch]$InstallVsCodeInterop,
  [switch]$Force
)

$ErrorActionPreference = "Stop"

# Only pinned LTS distro names are supported. The bare "Ubuntu" name installs whatever
# Ubuntu the Store currently ships, which the in-distro setup does not support
# (e.g. Docker has no apt repo for its codename). Add new names here as they are validated.
$SupportedDistros = @('Ubuntu-26.04', 'Ubuntu-24.04', 'Ubuntu-22.04')
if ($SupportedDistros -notcontains $DistroInstallName) {
  Write-Host @"
Unsupported -DistroInstallName '$DistroInstallName'.
Only these pinned LTS versions are supported: $($SupportedDistros -join ', ')
"@
  exit 1
}

if (-not $InstanceName) { $InstanceName = $DistroInstallName }

. "$PSScriptRoot\lib\Wsl.ps1"
. "$PSScriptRoot\lib\Credentials.ps1"

$exists = Test-WslInstanceExists $InstanceName
if ($exists -and -not $Force) {
  Write-Host "Instance '$InstanceName' already exists. Re-run with -Force to overwrite (this destroys it)."
  exit 1
}

# Claude Code is opt-in. Only when -InstallClaudeCode is passed do we need (and demand)
# the Context7 API key; otherwise it stays empty and the in-distro install self-skips.
$Context7ApiKey = ""
if ($InstallClaudeCode) {
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
}

# Git/gh configuration is opt-in. Only when -InstallGitConfig is passed do we need (and demand)
# the GitHub token; otherwise it stays empty and the in-distro install self-skips.
$GhToken = ""
if ($InstallGitConfig) {
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
}

$WindowsUsername = $env:USERNAME
$TargetUser = $WindowsUsername.ToLower() -replace '[^a-z0-9_-]', ''
if (-not $TargetUser) { Write-Host "Could not derive a valid Linux username from '$WindowsUsername'"; exit 1 }

# Read Git identity from Windows Git installation (only when configuring git in the instance)
$GitName  = ""
$GitEmail = ""
if ($InstallGitConfig) {
  $GitName  = git config --global user.name
  $GitEmail = git config --global user.email
  if (-not $GitName)  { Write-Host "git config --global user.name is not set"; exit 1 }
  if (-not $GitEmail) { Write-Host "git config --global user.email is not set"; exit 1 }
}

# The distro provisions the exact commit this checkout is on. Require a clean tree that is not
# ahead of origin, so cloud-init can reproduce the commit by cloning it from GitHub.
$RepoRoot = Split-Path $PSScriptRoot -Parent
$Branch = (git -C $RepoRoot rev-parse --abbrev-ref HEAD).Trim()
$CommitSha = (git -C $RepoRoot rev-parse HEAD).Trim()

if (git -C $RepoRoot status --porcelain) {
  Write-Host "Working tree has uncommitted changes. Commit or stash them before provisioning."
  exit 1
}

git -C $RepoRoot fetch origin $Branch --quiet 2>$null
$ahead = git -C $RepoRoot rev-list --count "origin/$Branch..HEAD" 2>$null
if ($LASTEXITCODE -ne 0 -or [int]$ahead -gt 0) {
  Write-Host "Branch '$Branch' is ahead of origin. Push it before before provisioning."
  exit 1
}
Write-Host "Provisioning $InstanceName from $Branch @ $($CommitSha.Substring(0, 8))"

# Derive Git credential manager path from the git.exe location (only when configuring git)
$CredManagerWsl = ""
if ($InstallGitConfig) {
  $GitExe = (Get-Command git).Source
  $GitRoot = Split-Path (Split-Path $GitExe -Parent) -Parent
  $CredManager = "$GitRoot\mingw64\bin\git-credential-manager.exe"
  if (-not (Test-Path $CredManager)) { Write-Host "git-credential-manager.exe not found at $CredManager"; exit 1 }
  $CredManagerWsl = ConvertTo-WslPath $CredManager
}

# Derive VS Code path from the installed executable (only when installing the interop wrapper;
# resolve the bash wrapper alongside code.cmd)
$VsCodeWsl = ""
if ($InstallVsCodeInterop) {
  $VsCodeShell = (Get-Command code).Source -replace '\.cmd$', ''
  if (-not (Test-Path $VsCodeShell)) { Write-Host "VS Code shell wrapper not found at $VsCodeShell"; exit 1 }
  $VsCodeWsl = ConvertTo-WslPath $VsCodeShell
}

# Derive PowerShell path from the installed executable
$PwshExe = (Get-Command powershell).Source
if (-not (Test-Path $PwshExe)) { Write-Host "powershell.exe not found at $PwshExe"; exit 1 }
$PwshWsl = ConvertTo-WslPath $PwshExe

# Substitute template
$InstallClaudeCodeValue    = if ($InstallClaudeCode)    { "true" } else { "false" }
$InstallGitConfigValue     = if ($InstallGitConfig)     { "true" } else { "false" }
$InstallVsCodeInteropValue = if ($InstallVsCodeInterop) { "true" } else { "false" }
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
    Replace('__COMMIT__',                  $CommitSha).
    Replace('__INSTALL_CLAUDE_CODE__',     $InstallClaudeCodeValue).
    Replace('__INSTALL_GIT_CONFIG__',      $InstallGitConfigValue).
    Replace('__INSTALL_VS_CODE_INTEROP__', $InstallVsCodeInteropValue).
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

# Terminate so the next launch re-reads /etc/wsl.conf (written by cloud-init this boot).
# Otherwise the first session keeps the pre-config state: appended Windows PATH and the
# wrong default user, until the instance is restarted.
wsl --terminate $InstanceName | Out-Null   # silence "The operation completed successfully."

Write-Host "[4/4] Launching $InstanceName..."
wsl -d $InstanceName
