#!/bin/bash
set -euo pipefail

if [[ "${INSTALL_GIT_CONFIG:-}" != "true" ]]; then
  echo "INSTALL_GIT_CONFIG not set, skipping gh auth wrapper"
  exit 0
fi

: "${POWERSHELL:?POWERSHELL is required}"

# Install the gh wrapper ahead of the apt-provided /usr/bin/gh on PATH. It reads the
# Windows "git:https://github.com" credential (via powershell.exe) and authenticates gh
# on demand — on first use and after a token rotation — so no gh token is provisioned.
#
# The wrapper is written verbatim from a quoted here-doc (so its many $ and the embedded
# C#/PowerShell stay literal), then the one Windows-derived value, POWERSHELL, is
# substituted in. The powershell.exe path is derived only in install.sh and passed here
# via the environment; nothing else hard-codes it. Idempotent: overwrites on each run.
tee /usr/local/bin/gh > /dev/null <<'GHWRAPPER'
#!/bin/bash
# gh wrapper: authenticates gh from the Windows "git:https://github.com" credential
# (the one Git Credential Manager stores on Windows sign-in). No token is provisioned;
# the wrapper signs gh in whenever it is needed. Installed ahead of the apt-provided
# /usr/bin/gh on PATH so it wraps every gh invocation.
#
# Lazy: it runs your command directly, so there is no added latency on the common path.
# If the command fails because gh isn't authenticated (fresh, rotated, or invalidated
# token), it prints "Authenticating with...", signs in from the Windows credential, and
# retries the command once. Any non-auth failure passes straight through untouched.
#
# Note: gh cannot make Git Credential Manager re-prompt — only a git HTTPS operation
# refreshes the stored credential after a rotation. The wrapper signs in with whatever
# token Windows currently holds; if that is missing or stale it says so, rather than
# leaving gh's misleading "run gh auth login".
#
# No `set -e`: failures are handled explicitly below and $? must survive capture.

GH=/usr/bin/gh
# Path to Windows powershell.exe, baked in at install time from install.sh's $POWERSHELL
# (the one place that derives it). Windows PATH isn't on the WSL PATH
# (wsl.conf appendWindowsPath=false), so the full path is required.
POWERSHELL="__POWERSHELL__"

# Read git:https://github.com from Windows and sign gh in. Announces itself, then is
# silent; returns non-zero on failure with a one-line reason. Neutral wording ("Authen-
# ticating") covers both first use and a later re-auth after a token rotation.
__gh_authenticate() {
  echo "" >&2
  echo "Authenticating with the GitHub token from your Windows Git credential..." >&2

  if [[ ! -x "$POWERSHELL" ]]; then
    echo "gh: authentication failed — Windows powershell.exe not found at $POWERSHELL." >&2
    return 1
  fi

  # Embedded CredRead — the SAME marshalling as windows/lib/Credentials.ps1
  # (blob size @ +32, blob ptr @ +40, read as UTF-16). Passed via -EncodedCommand
  # (base64 UTF-16LE) so powershell.exe never sees a secret on argv.
  local ps='$ProgressPreference = "SilentlyContinue"
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class CredManager {
  [DllImport("advapi32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
  public static extern bool CredRead(string target, int type, int flags, out IntPtr credential);
  [DllImport("advapi32.dll")]
  public static extern void CredFree(IntPtr buffer);
}
"@
$ptr = [IntPtr]::Zero
if (-not [CredManager]::CredRead("git:https://github.com", 1, 0, [ref]$ptr)) { exit 1 }
try {
  $blobSize = [System.Runtime.InteropServices.Marshal]::ReadInt32($ptr, 32)
  $blobPtr  = [System.Runtime.InteropServices.Marshal]::ReadIntPtr($ptr, 40)
  [Console]::Out.Write([System.Runtime.InteropServices.Marshal]::PtrToStringUni($blobPtr, $blobSize / 2))
} finally { [CredManager]::CredFree($ptr) }'

  local encoded token
  encoded="$(printf '%s' "$ps" | iconv -t UTF-16LE | base64 | tr -d '\n')"
  token="$("$POWERSHELL" -NoProfile -NonInteractive -EncodedCommand "$encoded" 2>/dev/null)"
  token="${token%$'\r'}"
  if [[ -z "$token" ]]; then
    echo "gh: authentication failed — no 'git:https://github.com' credential in Windows Credential Manager." >&2
    return 1
  fi
  if ! "$GH" auth login --with-token <<< "$token" >/dev/null 2>&1; then
    echo "gh: authentication failed — the GitHub token stored in Windows was rejected (likely stale)." >&2
    return 1
  fi
}

# Auth check: a real authenticated request. Reliable across gh versions — unlike
# `gh auth status`, whose exit code can be 0 (gh 2.45) even when the token is invalid.
# Used to tell an auth failure (needs sign-in) apart from any other command failure.
__gh_authed() { "$GH" api user >/dev/null 2>&1; }

# Help and version are local and can't be auth failures — run them directly.
[[ $# -eq 0 ]] && exec "$GH"
case "$1" in
  --version|-v|version|--help|-h|help) exec "$GH" "$@" ;;
esac
for arg in "$@"; do
  case "$arg" in --help|-h) exec "$GH" "$@" ;; esac
done

# Piped stdin: a retry can't re-read a drained pipe, so verify auth up front (signing
# in if needed) and run exactly once.
if [[ ! -t 0 ]]; then
  __gh_authed || __gh_authenticate
  exec "$GH" "$@"
fi

# Interactive / no stdin: lazy — run directly (no added latency). If it fails only
# because gh isn't authenticated, authenticate and retry once; any other failure
# (bad repo, usage, network) passes straight through.
"$GH" "$@"
ret=$?
(( ret == 0 )) && exit 0
__gh_authed && exit $ret
__gh_authenticate && exec "$GH" "$@"
exit $ret
GHWRAPPER

sed -i "s|__POWERSHELL__|${POWERSHELL}|" /usr/local/bin/gh
chmod 755 /usr/local/bin/gh
