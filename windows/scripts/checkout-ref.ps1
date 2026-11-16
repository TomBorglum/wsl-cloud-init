param(
  [Parameter(Mandatory)][string]$Ref,
  [string]$Destination
)

$ErrorActionPreference = "Stop"

# Provisioning a version is one coupled unit: provision.ps1's parameters, the cloud-init
# template and install.sh must all be the same commit. So version selection lives here rather
# than as a flag on provision.ps1, and the hand-off below is to that ref's own provision.ps1.
# The user's working tree is never touched.

$RepoUrl = "https://github.com/TomBorglum/wsl-cloud-init.git"

# An explicit -Destination is taken as-is with no prompt, so the script stays scriptable.
if (-not $Destination) {
  $safeRef = $Ref -replace '[\\/:*?"<>|]', '-'
  $Destination = Join-Path $env:TEMP "wsl-cloud-init-$safeRef"
  $answer = Read-Host "Check out '$Ref' into '$Destination'? [Y/n]"
  if ($answer -and $answer -notmatch '^(y|yes)$') {
    Write-Host "Aborted. Pass -Destination to choose your own path."
    exit 0
  }
}

# This script exists to produce a pristine, ref-exact tree, so an occupied destination is
# deleted and re-cloned rather than reused. That is destructive, hence the default of No.
if (Test-Path $Destination) {
  $hasChildren = Get-ChildItem -Force -Path $Destination -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($hasChildren) {
    # Never delete the checkout this script is running from, e.g. -Destination . at the repo root.
    $destFull = (Resolve-Path -LiteralPath $Destination).Path
    $selfRepo = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
    $sep = [System.IO.Path]::DirectorySeparatorChar
    if ($destFull -eq $selfRepo -or $selfRepo.StartsWith($destFull + $sep, [System.StringComparison]::OrdinalIgnoreCase)) {
      Write-Host "Refusing to delete '$destFull' - it contains the checkout-ref.ps1 you're running. Choose another -Destination."
      exit 1
    }
    $answer = Read-Host "Destination '$Destination' already exists and is not empty. Delete it and re-clone? [y/N]"
    if ($answer -notmatch '^(y|yes)$') {
      Write-Host "Aborted. Choose an empty or new path with -Destination."
      exit 0
    }
    Remove-Item -Recurse -Force -LiteralPath $Destination
  }
}

Write-Host "Cloning $RepoUrl into $Destination..."
git clone $RepoUrl $Destination
if ($LASTEXITCODE -ne 0) { Write-Error "Clone failed"; exit 1 }

# Resolve to an absolute path so the hint below runs from any working directory.
$Destination = (Resolve-Path $Destination).Path

# Whatever resolves here is on origin, since the clone came from there, so cloud-init can
# reproduce it by cloning from GitHub.
$CommitSha = (git -C $Destination rev-parse --verify --quiet "$Ref^{commit}")
if (-not $CommitSha) {
  Write-Host "Ref '$Ref' did not resolve to a commit in $RepoUrl. Check the name (tag, branch, or full commit SHA)."
  exit 1
}
$CommitSha = $CommitSha.Trim()

git -C $Destination checkout --detach $CommitSha --quiet
if ($LASTEXITCODE -ne 0) { Write-Error "Checkout of $Ref failed"; exit 1 }

Write-Host "Checked out '$Ref' @ $($CommitSha.Substring(0, 8)) (detached) in $Destination"

# Both layouts are probed because the script moved in #43, from windows/provision.ps1 to
# windows/scripts/provision.ps1, and an older ref ships the former.
$entrypoint = @('windows\scripts\provision.ps1', 'windows\provision.ps1') |
  Where-Object { Test-Path (Join-Path $Destination $_) } |
  Select-Object -First 1

Write-Host ""
if (-not $entrypoint) {
  Write-Host "Checked out, but no provision.ps1 was found in this ref's layout. Inspect $Destination and run that version's provisioning entrypoint."
  return
}

$absEntrypoint = Join-Path $Destination $entrypoint

# Built from the checked-out script's own parameter declaration, so the hint is correct for
# whatever version was checked out.
$knownDefaults = @{ DistroTemplatePath = 'ubuntu'; DistroInstallName = 'Ubuntu-26.04' }
$common = [System.Management.Automation.PSCmdlet]::CommonParameters +
          [System.Management.Automation.PSCmdlet]::OptionalCommonParameters

$mandatoryArgs = @()
$optionalFlags = @()
try {
  $params = (Get-Command $absEntrypoint).Parameters.Values |
    Where-Object { $common -notcontains $_.Name }
  foreach ($p in $params) {
    $isMandatory = $p.Attributes |
      Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
      ForEach-Object { $_.Mandatory } |
      Where-Object { $_ } |
      Select-Object -First 1
    $isSwitch = $p.ParameterType -eq [switch]
    if ($isMandatory) {
      $value = if ($knownDefaults.ContainsKey($p.Name)) { $knownDefaults[$p.Name] } else { "<$($p.Name)>" }
      $mandatoryArgs += "-$($p.Name) $value"
    }
    # Never suggest -Force: it destroys an existing instance and is irrelevant to a fresh run.
    elseif ($p.Name -eq 'Force') { continue }
    elseif ($isSwitch) { $optionalFlags += "-$($p.Name)" }
    else { $optionalFlags += "-$($p.Name) <value>" }
  }
}
catch {
  # Introspection failed (unexpected script shape) -- fall back to the known baseline params.
  $mandatoryArgs = @('-DistroTemplatePath ubuntu', '-DistroInstallName Ubuntu-26.04')
  $optionalFlags = @('-InstanceName <value>', '-InstallClaudeCode', '-InstallGitConfig', '-InstallVsCodeInterop')
}

# The optional flags must stay on a SINGLE trailing comment line: pasting a backtick-continued
# command with two or more comment lines makes PowerShell run it on paste, whereas one comment
# line (or none) waits for the user to press Enter.
$block = @("powershell -ExecutionPolicy Bypass -File `"$absEntrypoint`"") + $mandatoryArgs
if ($optionalFlags) { $block += "# optional: $($optionalFlags -join '  ')" }
Write-Host "Next, to provision this version run"
Write-Host ""
for ($i = 0; $i -lt $block.Count; $i++) {
  $indent = if ($i -eq 0) { '  ' } else { '    ' }
  $cont = if ($i -lt $block.Count - 1) { ' `' } else { '' }
  Write-Host "$indent$($block[$i])$cont"
}
