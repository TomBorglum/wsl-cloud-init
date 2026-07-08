param(
  [Parameter(Mandatory)][string]$Ref,
  [Parameter(Mandatory)][string]$Destination
)

$ErrorActionPreference = "Stop"

# Materialize a specific version of this project so it can provision itself. Provisioning
# a version is one coupled unit (provision.ps1's parameters, the cloud-init template, and
# install.sh must all be the same commit), so version selection lives here rather than as a
# flag on provision.ps1: this clones the chosen ref into its own directory, detached, and
# hands off to *that ref's own* provision.ps1. The user's working tree is never touched.

$RepoUrl = "https://github.com/TomBorglum/wsl-cloud-init.git"

# Don't clobber an existing checkout / non-empty directory.
if (Test-Path $Destination) {
  $hasChildren = Get-ChildItem -Force -Path $Destination -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($hasChildren) {
    Write-Host "Destination '$Destination' already exists and is not empty. Choose an empty or new path."
    exit 1
  }
}

Write-Host "Cloning $RepoUrl into $Destination..."
git clone $RepoUrl $Destination
if ($LASTEXITCODE -ne 0) { Write-Error "Clone failed"; exit 1 }

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
# checkout and print the matching command rather than assuming the current layout.
$entrypoint = @('windows\scripts\provision.ps1', 'windows\provision.ps1') |
  Where-Object { Test-Path (Join-Path $Destination $_) } |
  Select-Object -First 1

Write-Host ""
if ($entrypoint) {
  Write-Host "Next, provision from this version:"
  Write-Host "  cd `"$Destination`""
  Write-Host "  powershell -ExecutionPolicy Bypass -File .\$entrypoint ``"
  Write-Host "    -DistroTemplatePath ubuntu -DistroInstallName Ubuntu-24.04"
  Write-Host "  (add -InstanceName / -Install* / -Force as needed; see that version's README)"
}
else {
  Write-Host "Checked out, but no provision.ps1 was found in this ref's layout. Inspect $Destination and run that version's provisioning entrypoint."
}
