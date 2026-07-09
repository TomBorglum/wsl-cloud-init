param(
  [Parameter(Mandatory)][string]$Ref,
  [string]$Destination
)

$ErrorActionPreference = "Stop"

# Materialize a specific version of this project so it can provision itself. Provisioning
# a version is one coupled unit (provision.ps1's parameters, the cloud-init template, and
# install.sh must all be the same commit), so version selection lives here rather than as a
# flag on provision.ps1: this clones the chosen ref into its own directory, detached, and
# hands off to *that ref's own* provision.ps1. The user's working tree is never touched.

$RepoUrl = "https://github.com/TomBorglum/wsl-cloud-init.git"

# Default the destination to a temp path named after the ref, and confirm before cloning.
# An explicit -Destination is taken as-is with no prompt (explicit intent; also scriptable).
if (-not $Destination) {
  $safeRef = $Ref -replace '[\\/:*?"<>|]', '-'
  $Destination = Join-Path $env:TEMP "wsl-cloud-init-$safeRef"
  $answer = Read-Host "Check out '$Ref' into '$Destination'? [Y/n]"
  if ($answer -and $answer -notmatch '^(y|yes)$') {
    Write-Host "Aborted. Pass -Destination to choose your own path."
    exit 0
  }
}

# If the destination already holds files, offer to wipe it and re-clone. checkout-ref exists to
# produce a pristine, ref-exact tree, so overwrite means delete-and-re-clone rather than reusing
# a possibly-dirty or foreign directory. It's destructive, so default to No.
if (Test-Path $Destination) {
  $hasChildren = Get-ChildItem -Force -Path $Destination -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($hasChildren) {
    # Never delete the checkout this script is running from (e.g. -Destination . at the repo root).
    # The destination exists here (Test-Path above), so Resolve-Path gives a normalized absolute path.
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

# Resolve the ref to a commit. Cloning from origin means whatever resolves here is inherently
# on origin, so cloud-init can reproduce it by cloning from GitHub.
$CommitSha = (git -C $Destination rev-parse --verify --quiet "$Ref^{commit}")
if (-not $CommitSha) {
  Write-Host "Ref '$Ref' did not resolve to a commit in $RepoUrl. Check the name (tag, branch, or full commit SHA)."
  exit 1
}
$CommitSha = $CommitSha.Trim()

git -C $Destination checkout --detach $CommitSha --quiet
if ($LASTEXITCODE -ne 0) { Write-Error "Checkout of $Ref failed"; exit 1 }

Write-Host "Checked out '$Ref' @ $($CommitSha.Substring(0, 8)) (detached) in $Destination"

# Point the user at that ref's own provision.ps1. The script location moved in #43
# (windows/provision.ps1 -> windows/scripts/provision.ps1), so detect which exists in the
# checkout and drive off whichever this ref actually ships.
$entrypoint = @('windows\scripts\provision.ps1', 'windows\provision.ps1') |
  Where-Object { Test-Path (Join-Path $Destination $_) } |
  Select-Object -First 1

Write-Host ""
if (-not $entrypoint) {
  Write-Host "Checked out, but no provision.ps1 was found in this ref's layout. Inspect $Destination and run that version's provisioning entrypoint."
  return
}

$absEntrypoint = Join-Path $Destination $entrypoint

# Build a copy-paste-runnable command from the checked-out script's *own* parameter
# declaration, so the hint is correct for whatever version was checked out. Fill the
# mandatory parameters with sensible defaults; list the optional ones for the user to append.
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

# Print the command wrapped across lines with backtick continuation. The mandatory args form the
# runnable command; the optional flags follow on a SINGLE trailing comment line. Keep it to one
# comment line: pasting a continued command with two or more comment lines makes PowerShell run it
# on paste, whereas one comment line (or none) waits for the user to press Enter.
$block = @("powershell -ExecutionPolicy Bypass -File `"$absEntrypoint`"") + $mandatoryArgs
if ($optionalFlags) { $block += "# optional: $($optionalFlags -join '  ')" }
Write-Host "Next, to provision this version run"
Write-Host ""
for ($i = 0; $i -lt $block.Count; $i++) {
  $indent = if ($i -eq 0) { '  ' } else { '    ' }
  $cont = if ($i -lt $block.Count - 1) { ' `' } else { '' }
  Write-Host "$indent$($block[$i])$cont"
}
