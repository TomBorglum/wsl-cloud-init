param(
  [Parameter(Mandatory)][string]$DistroTemplatePath,
  [Parameter(Mandatory)][string]$DistroInstallName,
  [Parameter(Mandatory)][string]$InstanceName,
  [string]$Branch = "main",
  [switch]$Force
)

$ErrorActionPreference = "Stop"

function Test-WslInstanceExists([string]$name) {
  # WSL_UTF8=1 makes `wsl --list` emit clean UTF-8 (avoids the UTF-16/null-byte mangling
  # that otherwise breaks string matching on the output).
  $prev = $env:WSL_UTF8
  $env:WSL_UTF8 = "1"
  try {
    $names = (wsl --list --quiet) | ForEach-Object { $_.Trim() }
  } finally {
    if ($null -eq $prev) { Remove-Item Env:\WSL_UTF8 -ErrorAction SilentlyContinue }
    else { $env:WSL_UTF8 = $prev }
  }
  return $names -contains $name
}

if ((Test-WslInstanceExists $InstanceName) -and -not $Force) {
  Write-Host "Instance '$InstanceName' already exists. Re-run with -Force to overwrite (this destroys it)."
  exit 1
}

# Read API keys from Windows Credential Manager
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public class CredManager {
  [DllImport("advapi32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
  public static extern bool CredRead(string target, int type, int flags, out IntPtr credential);

  [DllImport("advapi32.dll")]
  public static extern void CredFree(IntPtr buffer);
}
'@

function Get-WindowsCredential([string]$target) {
  $ptr = [IntPtr]::Zero
  if (-not [CredManager]::CredRead($target, 1, 0, [ref]$ptr)) {
    throw "Credential '$target' not found in Windows Credential Manager."
  }
  try {
    # CREDENTIAL struct offsets on 64-bit Windows:
    #   +32 CredentialBlobSize (DWORD)
    #   +40 CredentialBlob (IntPtr, after 4-byte padding for alignment)
    $blobSize = [System.Runtime.InteropServices.Marshal]::ReadInt32($ptr, 32)
    $blobPtr  = [System.Runtime.InteropServices.Marshal]::ReadIntPtr($ptr, 40)
    return [System.Runtime.InteropServices.Marshal]::PtrToStringUni($blobPtr, $blobSize / 2)
  } finally {
    [CredManager]::CredFree($ptr)
  }
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
$CredManagerWsl = '/mnt/' + $CredManager[0].ToString().ToLower() + '/' + $CredManager.Substring(3) -replace '\\', '/' -replace ' ', '\ '

# Derive VS Code path from the installed executable (resolve the bash wrapper alongside code.cmd)
$VsCodeShell = (Get-Command code).Source -replace '\.cmd$', ''
if (-not (Test-Path $VsCodeShell)) { Write-Error "VS Code shell wrapper not found at $VsCodeShell"; exit 1 }
$VsCodeWsl = '/mnt/' + $VsCodeShell[0].ToString().ToLower() + '/' + $VsCodeShell.Substring(3) -replace '\\', '/' -replace ' ', '\ '

# Derive PowerShell path from the installed executable
$PwshExe = (Get-Command powershell).Source
if (-not (Test-Path $PwshExe)) { Write-Error "powershell.exe not found at $PwshExe"; exit 1 }
$PwshWsl = '/mnt/' + $PwshExe[0].ToString().ToLower() + '/' + $PwshExe.Substring(3) -replace '\\', '/' -replace ' ', '\ '

# Substitute template
$template = Get-Content "$PSScriptRoot\..\distros\$DistroTemplatePath\user-data.template" -Raw

$template = $template `
    -replace '__TARGET_USER__',            $TargetUser `
    -replace '__GIT_NAME__',                  $GitName `
    -replace '__GIT_EMAIL__',                 $GitEmail `
    -replace '__GIT_CREDENTIAL_MANAGER__',    $CredManagerWsl `
    -replace '__VSCODE__',                    $VsCodeWsl `
    -replace '__POWERSHELL__',               $PwshWsl `
    -replace '__BRANCH__',                    $Branch `
    -replace '__CONTEXT7_API_KEY__',          $Context7ApiKey `
    -replace '__GH_TOKEN__',                  $GhToken

$userDataDir = "$PSScriptRoot\..\user-data"
New-Item -ItemType Directory -Force -Path $userDataDir | Out-Null
$userDataPath = "$userDataDir\$InstanceName.user-data"
$template | Set-Content $userDataPath -NoNewline
Write-Host "Generated user-data for $InstanceName"

# Provision
Write-Host "[1/5] Unregistering $InstanceName..."
$result = Start-Process wsl -ArgumentList "--unregister", $InstanceName -Wait -PassThru -WindowStyle Hidden
if ($result.ExitCode -ne 0 -and $result.ExitCode -ne -1) {
    Write-Error "Unexpected error unregistering $InstanceName (exit code $($result.ExitCode))"; exit 1
}

Write-Host "[2/5] Copying cloud-init user-data..."
$cloudInitDir = "$env:USERPROFILE\.cloud-init"
New-Item -ItemType Directory -Force -Path $cloudInitDir | Out-Null
Copy-Item -Force $userDataPath "$cloudInitDir\$InstanceName.user-data"

Write-Host "[3/5] Installing $DistroInstallName as $InstanceName..."
wsl --install $DistroInstallName --name $InstanceName --no-launch
if ($LASTEXITCODE -ne 0) { Write-Error "WSL install failed"; exit 1 }

Write-Host "[4/5] Waiting for cloud-init to finish..."
wsl -d $InstanceName --user root -- cloud-init status --wait

Write-Host "[5/5] Launching $InstanceName..."
wsl -d $InstanceName
