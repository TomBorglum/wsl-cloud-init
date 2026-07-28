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

# install.sh brackets each numbered script with these markers, carrying the step's own measured
# duration so it does not have to be inferred from the poll interval. Kept as two lines in the log
# so the file still reads sequentially; paired back into a single line for display.
$StepStart  = "^===> (.+)$"
$StepFinish = "^<=== \S+ ok \(([\d.]+)s\)$"

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
#
# Callers that index the result must wrap the call in @(): PowerShell unwraps a single-element
# array on its way out of a function, so a one-line result arrives as a bare string and `[0]`
# would index its first *character* rather than the line.
function Invoke-InDistro([string]$Command) {
    try { return @(wsl -d $InstanceName --user root -- bash -c "{ $Command ; } 2>/dev/null || true") }
    catch { return @() }
}

$CloudInitLog = "/var/log/cloud-init-output.log"

# Read the log from $FirstLine on, and have the distro report how many lines it actually holds.
#
# The obvious version of this -- tail, then advance the offset by however many elements came back
# -- is wrong, and wrong in a way that silently eats whole lines. PowerShell splits native command
# output on carriage returns as well as newlines, so `printf 'a\rb\nc\n'` arrives as three
# elements for two lines. A real provisioning log is full of them: 634 of 1191 lines carry a `\r`,
# 1023 in total, nearly all from dpkg's "(Reading database ... 5%\r10%\r...)" progress. Counting
# elements therefore runs the offset past the end of the file and never comes back, which is how
# entire install steps went missing.
#
# So the count comes from `wc -l` instead, and the offset is derived from that and never from the
# payload. `wc -l` counts only newline-terminated lines, and the `sed` range stops at that count,
# so a line still being written is left for the next poll rather than displayed half-formed.
#
# Deliberately two calls rather than one clever shell one-liner. A `bash -c` sent through wsl.exe
# does not survive assigning a shell variable and reading it back -- `x=abc; echo $x` comes back
# empty -- so the count cannot be captured and reused inside the distro. Every other command in
# this script is variable-free for the same reason. Both halves here interpolate on the PowerShell
# side, so no `$` ever reaches bash.
function Read-LogFrom([int]$FirstLine) {
    $countOut = @(Invoke-InDistro "wc -l < $CloudInitLog")
    $total = $null
    if ($countOut.Count) { try { $total = [int]$countOut[0].Trim() } catch { $total = $null } }

    # No usable reading -- instance still booting, or the log not created yet. Report the offset
    # unchanged so the caller retries the same range rather than advancing past unread lines.
    if ($null -eq $total) { return @{ Total = $FirstLine - 1; Lines = @() } }
    if ($total -lt $FirstLine) { return @{ Total = $total; Lines = @() } }

    # Both the command and the call are hoisted out of the hashtable on purpose. Written inline as
    # `@{ Lines = @(Invoke-InDistro "sed -n $FirstLine,${total}p ...") }` this returned a single
    # line instead of the whole range; assigning to a variable first returns all of it.
    $sedCommand = "sed -n " + $FirstLine + "," + $total + "p " + $CloudInitLog
    $payload = @(Invoke-InDistro $sedCommand)
    return @{ Total = $total; Lines = $payload }
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

# Progress lines are written in two tempi: the label appears the moment the thing it names starts,
# and "-> ok (duration)" is appended when it finishes, so something slow is visibly in progress
# rather than simply absent. cloud-init's boot stages and install.sh's numbered steps are the same
# construct at different depths, so they share one stack.
#
# A line cannot always be completed in place. modules:final holds the apt work and the whole of
# install.sh -- well over a thousand log lines -- so when output arrives the open line is
# terminated, the output streams live and indented beneath it, and the line is restated when it
# closes. Waiting until the end to print anything would hide progress during exactly the stage
# where the waiting happens.
#
# Invariant: only the top of the stack can be unbroken, because opening a child always terminates
# its parent's line first.
$pendingLines = [System.Collections.Generic.List[hashtable]]::new()

# Columns the '-> ok' marker lines up in. The stage width fits cloud-init's longest name
# ('modules:config'); the step width fits '[14/16] 14-install-direnv-functions.sh', the longest
# label install.sh can produce.
$StageLabelWidth = 24
$StepLabelWidth  = 38

# Indent follows depth, so a label and the content nested under its parent line up: nothing open
# gives 2, an open stage gives 6, an open stage plus step gives 10.
function Get-PendingIndent { return "  " + ("    " * $pendingLines.Count) }

function Split-PendingLine {
    if ($pendingLines.Count -eq 0) { return }
    $top = $pendingLines[$pendingLines.Count - 1]
    if (-not $top.Broken) { Write-Host ""; $top.Broken = $true }
}

function Open-PendingLine([string]$Kind, [string]$Label, [int]$Width) {
    $indent = Get-PendingIndent
    Split-PendingLine
    $pendingLines.Add(@{ Kind = $Kind; Label = $Label; Indent = $indent; Width = $Width; Broken = $false })
    Write-Host "$indent$Label" -NoNewline
}

# $Kind guards which line this completes. Without it a stray marker closes whatever happens to be
# on top: a `<===` arriving with no step open used to complete the *stage* instead, printing
# "Running 'modules:final' -> ok (0.0s)" halfway through the run and leaving every later step
# orphaned at the wrong depth.
function Complete-PendingLine([string]$Kind, [double]$Seconds) {
    if ($pendingLines.Count -eq 0) { return }
    $top = $pendingLines[$pendingLines.Count - 1]
    if ($top.Kind -ne $Kind) { return }
    $pendingLines.RemoveAt($pendingLines.Count - 1)
    $duration = Format-Duration $Seconds
    if ($top.Broken) {
        # The opener was terminated by streamed output, so restate the label rather than leave a
        # bare "-> ok" dangling underneath a wall of text.
        Write-Host ("{0}{1} -> ok ({2})" -f $top.Indent, $top.Label.PadRight($top.Width), $duration)
    } else {
        # Completing the opener in place. The padding is applied here rather than when the label
        # was written, so a line that breaks does not leave trailing whitespace behind.
        $pad = [Math]::Max(1, $top.Width + 1 - $top.Label.Length)
        Write-Host ((" " * $pad) + ("-> ok ({0})" -f $duration))
    }
}

# Give up on open lines without inventing a duration for them -- install.sh dying mid-step never
# writes its `<===`, and a failed run never writes cloud-init's 'finished' banner. The newline
# still has to go out or the next line is glued onto the abandoned opener.
#
# Unwinding is by kind rather than by a depth number: a depth said what to keep only indirectly,
# and stopped meaning the right thing the moment the stack was one entry off.
function Reset-PendingLines([string[]]$Kinds) {
    while ($pendingLines.Count -and $pendingLines[$pendingLines.Count - 1].Kind -in $Kinds) {
        $idx = $pendingLines.Count - 1
        if (-not $pendingLines[$idx].Broken) { Write-Host "" }
        $pendingLines.RemoveAt($idx)
    }
}

# Abandon any open install.sh step, leaving an open stage alone.
function Reset-OpenSteps { Reset-PendingLines @('step') }

# Abandon everything, whatever it is.
function Reset-AllPendingLines { Reset-PendingLines @('stage', 'step') }

$stageUp = 0.0   # uptime from the open stage's banner; steps carry their own duration

function Write-StreamedLines($Lines) {
    foreach ($line in $Lines) {
        # -ShowAllOutput is the "show me exactly what the log says" mode, so it prints raw and
        # skips the rewriting entirely; reformatting as well would double every line up.
        if ($ShowAllOutput) { Write-Host "  $line"; continue }

        # Splitting on carriage returns (see Read-LogFrom) leaves empty fragments behind. They are
        # harmless but carry nothing, so drop them before classifying.
        if (-not $line.Trim()) { continue }

        if ($line -match $StageStart) {
            $name = $Matches[1]
            $up   = [double]$Matches[2]
            Reset-OpenSteps
            Complete-PendingLine 'stage' ($up - $script:stageUp)
            $script:stageUp = $up
            Open-PendingLine 'stage' "Running '$name'" $StageLabelWidth
            continue
        }

        if ($line -match $StageFinish) {
            Reset-OpenSteps
            Complete-PendingLine 'stage' ([double]$Matches[1] - $script:stageUp)
            continue
        }

        # install.sh's step markers, paired into one line the same way. The `===> ` / `<=== `
        # prefixes are its side of the contract; see wsl/distros/ubuntu/install.sh.
        if ($line -match $StepStart) {
            Reset-OpenSteps                                       # a step whose `<===` never came
            Open-PendingLine 'step' $Matches[1] $StepLabelWidth
            continue
        }

        if ($line -match $StepFinish) { Complete-PendingLine 'step' ([double]$Matches[1]); continue }

        if ($line -match $InterestingLine -and $line -notmatch $BenignNoise) {
            $indent = Get-PendingIndent
            Split-PendingLine
            Write-Host "$indent$line"
        }
    }
}

$stopwatch     = [Diagnostics.Stopwatch]::StartNew()
$nextLine      = 1      # 1-indexed line of cloud-init-output.log to resume the tail from
$probeFailures = 0
$status        = $null

while ($true) {
    # The offset advances by the line count the distro reports, never by how many elements came
    # back -- see Read-LogFrom. The filter decides only what is *printed*.
    $chunk = Read-LogFrom $nextLine
    if ($chunk.Lines.Count) { Write-StreamedLines $chunk.Lines }
    $nextLine = $chunk.Total + 1

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
Write-StreamedLines (Read-LogFrom $nextLine).Lines

# A failed run may never write that closing banner, which would leave lines open with unterminated
# -NoNewline openers for the next Write-Host to run into. Abandon any open step, then close the
# stage from a live uptime reading -- one extra probe, and only on this path.
if ($pendingLines.Count) {
    Reset-OpenSteps

    $uptime = "$(Invoke-InDistro "cut -d' ' -f1 /proc/uptime" | Select-Object -First 1)".Trim()
    # [double] parses culture-invariantly (unlike [double]::TryParse, which would reject "7.49" on
    # a comma-decimal machine), but it yields 0 for an empty string instead of throwing -- which
    # would report a confident, wrong duration. So require a non-empty reading first.
    $parsedUptime = $null
    if ($uptime) { try { $parsedUptime = [double]$uptime } catch { $parsedUptime = $null } }

    if ($null -ne $parsedUptime) {
        Complete-PendingLine 'stage' ($parsedUptime - $stageUp)
    }
    # Whatever is still open here either had no usable reading or was not a stage, so drop it
    # rather than invent a duration. A stuck step must never be handed a stage-shaped one.
    Reset-AllPendingLines
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
