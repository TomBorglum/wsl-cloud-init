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

$WindowsDir = Split-Path $PSScriptRoot -Parent   # windows/
$RepoRoot   = Split-Path $WindowsDir  -Parent    # repo root

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

. "$WindowsDir\lib\Wsl.ps1"

$exists = Test-WslInstanceExists $InstanceName
if ($exists -and -not $Force) {
  Write-Host "Instance '$InstanceName' already exists. Re-run with -Force to overwrite (this destroys it)."
  exit 1
}

# Opt-in installations are provisioned by install.sh inside the distro: it derives the
# Windows paths/identity and fetches secrets from Credential Manager at runtime,
# and is also the sole validator of those prerequisites. So nothing secret or
# Windows-derived is read here. A missing secret / git identity / VS Code surfaces
# at first boot as a cloud-init failure (see /var/log/cloud-init-output.log).

$WindowsUsername = $env:USERNAME
$TargetUser = $WindowsUsername.ToLower() -replace '[^a-z0-9_-]', ''
if (-not $TargetUser) { Write-Host "Could not derive a valid Linux username from '$WindowsUsername'"; exit 1 }

# Provision the commit this checkout is on. cloud-init reproduces it by cloning from GitHub,
# so the commit must exist on origin. This holds for a normal clone (a branch tip) and for a
# detached checkout produced by checkout-ref.ps1 (a released tag), so a single path covers
# both: verify HEAD's commit is on origin rather than reasoning about branches.
$CommitSha = (git -C $RepoRoot rev-parse HEAD).Trim()
if (git -C $RepoRoot status --porcelain) {
  Write-Host "Working tree has uncommitted changes. Commit or stash them before provisioning."
  exit 1
}
git -C $RepoRoot fetch origin --tags --quiet 2>$null
if (-not (git -C $RepoRoot branch -r --contains $CommitSha 2>$null)) {
  Write-Host "Commit $($CommitSha.Substring(0, 8)) is not on origin. Push it before provisioning, or use windows\scripts\checkout-ref.ps1 to provision a released version."
  exit 1
}
# Display label: the branch name, or the short SHA when HEAD is detached.
$Branch = (git -C $RepoRoot rev-parse --abbrev-ref HEAD).Trim()
$SourceLabel = if ($Branch -eq 'HEAD') { $CommitSha.Substring(0, 8) } else { $Branch }
Write-Host "Provisioning $InstanceName from $SourceLabel @ $($CommitSha.Substring(0, 8))"

# Substitute template. The template carries no secrets and no derived Windows
# paths: install.sh fetches/derives those at runtime inside the distro.
$InstallClaudeCodeValue    = if ($InstallClaudeCode)    { "true" } else { "false" }
$InstallGitConfigValue     = if ($InstallGitConfig)     { "true" } else { "false" }
$InstallVsCodeInteropValue = if ($InstallVsCodeInterop) { "true" } else { "false" }
$template = Get-Content "$RepoRoot\wsl\distros\$DistroTemplatePath\cloud-init\user-data.template" -Raw

# String.Replace (literal) rather than -replace (regex), so a value containing
# '$' is never interpreted as a regex backreference.
$template = $template.
    Replace('__TARGET_USER__',             $TargetUser).
    Replace('__COMMIT__',                  $CommitSha).
    Replace('__INSTALL_CLAUDE_CODE__',     $InstallClaudeCodeValue).
    Replace('__INSTALL_GIT_CONFIG__',      $InstallGitConfigValue).
    Replace('__INSTALL_VS_CODE_INTEROP__', $InstallVsCodeInteropValue)

$userDataDir = "$RepoRoot\user-data"
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
