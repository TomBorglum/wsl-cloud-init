param(
  [Parameter(Mandatory)][string]$DistroTemplatePath,
  [Parameter(Mandatory)][string]$DistroInstallName,
  [string]$InstanceName,
  [switch]$InstallClaudeCode,
  [switch]$InstallGitConfig,
  [switch]$InstallVsCodeInterop,
  [switch]$InstallZedInterop,
  [switch]$SkipPackageUpgrade,
  [switch]$ShowAllOutput,
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
# The ref this instance is based on, recorded in /etc/wsl-cloud-init-release by the
# in-distro 01-install-release-info.sh. It must be resolved here: checkout-ref.ps1 and
# cloud-init both leave a detached HEAD, so a branch name is unrecoverable in the distro.
# Prefer an exact tag, so a version laid down by checkout-ref.ps1 reads as 'v1.0.0' rather
# than a bare SHA; a normal clone of a branch reads as that branch.
#
# `tag --points-at` rather than `describe --tags --exact-match`: describe fails loudly on an
# untagged commit, and $ErrorActionPreference = "Stop" turns a native command's stderr into a
# terminating NativeCommandError even when it is redirected to $null. points-at just prints
# nothing and exits 0. Newest tag wins when a commit carries more than one.
$Tag = git -C $RepoRoot tag --points-at $CommitSha --sort=-v:refname | Select-Object -First 1
$Branch = (git -C $RepoRoot rev-parse --abbrev-ref HEAD).Trim()
$Ref = if ($Tag) { $Tag.Trim() } elseif ($Branch -ne 'HEAD') { $Branch } else { $CommitSha.Substring(0, 8) }

# $Ref and $InstanceName are substituted into shell `export` lines in the cloud-init
# runcmd. Git allows '$', '"' and '`' in ref names, so reject anything that would break out
# of the quoting rather than emitting user-data that executes a branch name.
foreach ($pair in @(@{ Name = 'Ref'; Value = $Ref }, @{ Name = 'InstanceName'; Value = $InstanceName })) {
  if ($pair.Value -notmatch '^[A-Za-z0-9._/-]+$') {
    Write-Host "$($pair.Name) '$($pair.Value)' contains characters that cannot be embedded in cloud-init user-data. Use only letters, digits, '.', '_', '/', and '-'."
    exit 1
  }
}

Write-Host "Provisioning $InstanceName from $Ref @ $($CommitSha.Substring(0, 8))"

# Substitute template. The template carries no secrets and no derived Windows
# paths: install.sh fetches/derives those at runtime inside the distro.
$InstallClaudeCodeValue    = if ($InstallClaudeCode)    { "true" } else { "false" }
$InstallGitConfigValue     = if ($InstallGitConfig)     { "true" } else { "false" }
$InstallVsCodeInteropValue = if ($InstallVsCodeInterop) { "true" } else { "false" }
$InstallZedInteropValue    = if ($InstallZedInterop)    { "true" } else { "false" }
# Inverted relative to the switch: the flag opts *out*, so the default (switch absent)
# must render the upgrade on.
$PackageUpgradeValue       = if ($SkipPackageUpgrade)   { "false" } else { "true" }
$template = Get-Content "$RepoRoot\wsl\distros\$DistroTemplatePath\cloud-init\user-data.template" -Raw

# String.Replace (literal) rather than -replace (regex), so a value containing
# '$' is never interpreted as a regex backreference.
$template = $template.
    Replace('__TARGET_USER__',             $TargetUser).
    Replace('__COMMIT__',                  $CommitSha).
    Replace('__REF__',                     $Ref).
    Replace('__INSTANCE_NAME__',           $InstanceName).
    Replace('__INSTALL_CLAUDE_CODE__',     $InstallClaudeCodeValue).
    Replace('__INSTALL_GIT_CONFIG__',      $InstallGitConfigValue).
    Replace('__INSTALL_VS_CODE_INTEROP__', $InstallVsCodeInteropValue).
    Replace('__INSTALL_ZED_INTEROP__',     $InstallZedInteropValue).
    Replace('__PACKAGE_UPGRADE__',         $PackageUpgradeValue)

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

# `cloud-init status --wait` emits one dot per poll and nothing else: enough to show the run is
# alive, nothing about where its time goes. Poll instead and stream the lines of
# /var/log/cloud-init-output.log that carry signal -- cloud-init's stage transitions, apt's
# upgrade summary, and the per-step banners install.sh writes. Anything resembling an error is
# printed whatever the filter says, so nothing alarming is ever hidden; -ShowAllOutput prints
# the log verbatim instead, which is the setting to reach for when a provision is failing.
#
# The `===> ` / `<=== ` prefixes come from wsl/distros/ubuntu/install.sh: the two files are
# coupled and have to change together. Stage banners are not listed here; they get their own
# handling below.
$InterestingLine = "^===> |^<=== |^install\.sh: |^\d+ upgraded, |error|failed|Traceback|^E: "

# cloud-init announces each stage with a banner carrying the package version, a wall-clock
# timestamp and an uptime, e.g.
#
#   Cloud-init v. 26.1-0ubuntu2 running 'modules:config' at Tue, 28 Jul 2026 12:28:38 +0000. Up 8.28 seconds.
#   Cloud-init v. 26.1-0ubuntu2 finished at Tue, 28 Jul 2026 12:29:39 +0000. Datasource DataSourceWSL.  Up 69.53 seconds
#
# Printed as-is that is actively misleading: the only number on it is /proc/uptime, and under WSL2
# every distro shares one utility VM and one kernel, so it is the VM's uptime and has nothing to do
# with how long this instance has been provisioning. Start a second instance on a machine that has
# been up an hour and the first banner claims 3600 seconds.
#
# The uptimes are still useful as *differences*, which is what gets reported instead: subtracting
# consecutive banners gives an exact per-stage duration, free of the 2s poll granularity. The
# closing 'finished at' line supplies the end of the last stage. Both patterns stay tolerant of
# spacing -- the finish line uses two spaces before `Up` and drops the trailing period.
$StageStart  = "^Cloud-init v\.\s+\S+\s+running\s+'([^']+)'.*?\bUp\s+([\d.]+)\s+seconds"
$StageFinish = "^Cloud-init v\..*?\bfinished at\b.*?\bUp\s+([\d.]+)\s+seconds"

# Two lines apt's dpkg triggers emit on every single provision: systemd and dbus are not fully up
# inside a WSL container while packages are configuring, so postinst scripts probing them fail
# harmlessly (they sit between "Processing triggers for systemd" and "Processing triggers for
# dbus"). They match the error catch-all above, and printing known-benign errors every time is how
# people learn to ignore the real ones. Both patterns are anchored end to end so nothing broader
# is ever suppressed.
$BenignNoise = "^Failed to get properties: Transport endpoint is not connected$" +
               "|^Failed to connect to system scope bus via local transport: Connection refused$"

# Both probes below are expected to fail early on -- the log does not exist until cloud-init
# starts, and an exec can fail outright while the instance is still coming up. The redirect and
# `|| true` run inside the distro rather than on this side because $ErrorActionPreference =
# "Stop" turns a native command's stderr into a terminating NativeCommandError even when it is
# redirected here (the same trap documented on `git tag --points-at` above). The try/catch
# covers wsl.exe itself failing before bash is ever reached.
function Invoke-InDistro([string]$Command) {
    try { return @(wsl -d $InstanceName --user root -- bash -c "{ $Command ; } 2>/dev/null || true") }
    catch { return @() }
}

function Format-Duration([double]$Seconds) {
    # Sub-second stages are normal (init and init-local both run in well under a second), so keep
    # a decimal below a minute or they all report as 0s. Formatted against InvariantCulture so the
    # separator stays a period: `-f` would render "1,1s" on a machine set to nb-NO or de-DE, which
    # would not match the periods in the `analyze blame` output printed a few lines further down.
    if ($Seconds -lt 60) { return $Seconds.ToString('0.0', [cultureinfo]::InvariantCulture) + "s" }
    $span = [TimeSpan]::FromSeconds($Seconds)
    # Floor, not [int]: PowerShell's [int] cast rounds, so 90 seconds would read as "2m30s".
    # Minutes can exceed 59, so TotalMinutes rather than the Minutes component.
    return ("{0}m{1:00}s" -f [int][Math]::Floor($span.TotalMinutes), $span.Seconds)
}

# A stage line is written in two tempi: the name appears the moment the stage starts, and the
# result is appended when it ends, so a stage that is taking a while is visibly in progress rather
# than absent. modules:final breaks that pattern -- it holds both apt and the whole of install.sh,
# well over a thousand log lines -- so when a stage emits output its line is terminated, the output
# streams live and indented beneath it, and the stage is restated when it closes. Waiting until the
# end to print anything would hide progress during the one stage where the waiting happens.
$stageName   = $null    # stage currently open, or $null
$stageUp     = 0.0      # uptime reported by that stage's banner
$stageBroken = $false   # has streamed output already terminated the opening line?

# Column the '-> ok' marker lines up in, wide enough for the longest name cloud-init uses
# ('modules:config').
$StageLabelWidth = 24

function Close-Stage([double]$UpNow) {
    if (-not $script:stageName) { return }
    $duration = Format-Duration ($UpNow - $script:stageUp)
    $label    = "Running '$($script:stageName)'"
    if ($script:stageBroken) {
        # The opener was terminated by streamed output, so restate the stage rather than leave a
        # bare "-> ok" dangling underneath a wall of text.
        Write-Host ("  {0,-$StageLabelWidth} -> ok ({1})" -f $label, $duration)
    } else {
        # Completing the opener in place. The padding is applied here rather than when the label
        # was written, so a stage that breaks does not leave trailing whitespace on its line.
        $pad = [Math]::Max(1, $StageLabelWidth + 1 - $label.Length)
        Write-Host ((" " * $pad) + ("-> ok ({0})" -f $duration))
    }
    $script:stageName   = $null
    $script:stageBroken = $false
}

function Write-StreamedLines($Lines) {
    foreach ($line in $Lines) {
        # -ShowAllOutput is the "show me exactly what the log says" mode, so it prints raw and
        # skips the banner rewriting entirely; reformatting as well would double every stage up.
        if ($ShowAllOutput) { Write-Host "  $line"; continue }

        if ($line -match $StageStart) {
            $name = $Matches[1]
            $up   = [double]$Matches[2]
            Close-Stage $up
            $script:stageName = $name
            $script:stageUp   = $up
            Write-Host "  Running '$name'" -NoNewline
            continue
        }

        if ($line -match $StageFinish) { Close-Stage ([double]$Matches[1]); continue }

        if ($line -match $InterestingLine -and $line -notmatch $BenignNoise) {
            if ($script:stageName -and -not $script:stageBroken) {
                Write-Host ""
                $script:stageBroken = $true
            }
            Write-Host "      $line"
        }
    }
}

$stopwatch     = [Diagnostics.Stopwatch]::StartNew()
$nextLine      = 1      # 1-indexed line of cloud-init-output.log to resume the tail from
$probeFailures = 0
$status        = $null

while ($true) {
    # Advance by the raw line count and let the filter decide only what is *printed*: advancing
    # by the filtered count would re-print or skip lines on the next pass.
    $lines = Invoke-InDistro "tail -n +$nextLine /var/log/cloud-init-output.log"
    if ($lines.Count) {
        $nextLine += $lines.Count
        Write-StreamedLines $lines
    }

    $json   = (Invoke-InDistro "cloud-init status --format=json") -join "`n"
    $parsed = $null
    if ($json.Trim()) { try { $parsed = $json | ConvertFrom-Json } catch { $parsed = $null } }

    if ($null -eq $parsed) {
        # Never let a problem with this loop wedge provisioning: after a run of unreadable
        # probes, hand back to the blocking wait this replaced.
        if (++$probeFailures -ge 15) {
            Write-Host "  (progress polling unavailable; falling back to 'cloud-init status --wait')"
            wsl -d $InstanceName --user root -- cloud-init status --wait
            # Normalize the documented exit codes (0 success, 1 unrecoverable, 2 recoverable)
            # into the shape the JSON probe returns, so the result check below covers this
            # path too rather than silently skipping it.
            $waitExit = $LASTEXITCODE
            $status = [pscustomobject]@{
                status          = if ($waitExit -eq 1) { 'error' } else { 'done' }
                extended_status = switch ($waitExit) { 0 { 'done' } 1 { 'error' } default { 'degraded done' } }
            }
            break
        }
    } else {
        $probeFailures = 0
        $status = $parsed
        if ($status.status -in @('done', 'error', 'disabled')) { break }
    }

    Start-Sleep -Seconds 2
}
$stopwatch.Stop()

# Drain whatever was written between the last poll and the run reaching a terminal state. This is
# also what picks up the closing 'finished at' banner and so closes the last stage.
Write-StreamedLines (Invoke-InDistro "tail -n +$nextLine /var/log/cloud-init-output.log")

# A failed run may never write that closing banner, which would leave the last stage open with an
# unterminated -NoNewline opener for the next Write-Host to run into. Close it from a live uptime
# reading -- one extra probe, and only on this path.
if ($stageName) {
    $uptime = "$(Invoke-InDistro "cut -d' ' -f1 /proc/uptime" | Select-Object -First 1)".Trim()
    # [double] parses culture-invariantly (unlike [double]::TryParse, which would reject "7.49" on
    # a comma-decimal machine), but it yields 0 for an empty string instead of throwing -- which
    # would report a confident, wrong duration. So require a non-empty reading first.
    $parsedUptime = $null
    if ($uptime) { try { $parsedUptime = [double]$uptime } catch { $parsedUptime = $null } }

    if ($null -ne $parsedUptime) {
        Close-Stage $parsedUptime
    } else {
        # No usable reading, so drop the duration rather than invent one. The newline still has to
        # be emitted or the following output lands on the opener's line.
        Write-Host ""
        $stageName = $null
    }
}

Write-Host ("[3/4] done in {0}" -f (Format-Duration $stopwatch.Elapsed.TotalSeconds))

# Per-module timing, so a slow provision explains itself without anyone opening a second
# terminal. package_upgrade surfaces here whenever the Store image has drifted far from the
# archive, which is the usual reason one provision takes markedly longer than the last. All of
# install.sh collapses into a single modules-final/config-scripts_user entry -- the per-step
# banners streamed above are the other half of that picture.
$blame = Invoke-InDistro "cloud-init analyze blame | grep -E '^[[:space:]]+[0-9]' | head -n 5"
if ($blame.Count) {
    Write-Host "  slowest modules:"
    foreach ($line in $blame) { if ($line.Trim()) { Write-Host "    $($line.Trim())" } }
}

# Check how the run actually ended. cloud-init reports 'error' for an unrecoverable failure and
# a 'degraded ...' extended status when it finished but hit a recoverable one; neither used to
# be looked at here, so a failed first boot went on to launch as though it had succeeded.
# extended_status is not reported by every cloud-init the supported LTS releases ship, so fall
# back to the plain status when it is absent.
if ($status) {
    $extended = if ($status.PSObject.Properties['extended_status']) { $status.extended_status } else { $status.status }

    if ($status.status -eq 'error') {
        Write-Host ""
        Write-Host "cloud-init failed (status: $extended). The instance is left registered so it can be"
        Write-Host "inspected; re-provision with -Force once the cause is fixed."
        Invoke-InDistro "cloud-init status --long"                  | ForEach-Object { Write-Host "  $_" }
        Invoke-InDistro "tail -n 40 /var/log/cloud-init-output.log" | ForEach-Object { Write-Host "  $_" }
        Write-Error "cloud-init failed; not launching $InstanceName"; exit 1
    }

    if ($extended -ne 'done') {
        Write-Host "Warning: cloud-init finished with status '$extended'. The instance is usable, but part of"
        Write-Host "the setup did not complete -- see /var/log/cloud-init-output.log."
        Invoke-InDistro "cloud-init status --long" | ForEach-Object { Write-Host "  $_" }
    }
}

# Terminate so the next launch re-reads /etc/wsl.conf (written by cloud-init this boot).
# Otherwise the first session keeps the pre-config state: appended Windows PATH and the
# wrong default user, until the instance is restarted.
wsl --terminate $InstanceName | Out-Null   # silence "The operation completed successfully."

Write-Host "[4/4] Launching $InstanceName..."
wsl -d $InstanceName
