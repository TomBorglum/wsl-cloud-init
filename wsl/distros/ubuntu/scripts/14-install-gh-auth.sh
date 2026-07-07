#!/bin/bash
set -euo pipefail

source /usr/local/lib/wsl-cloud-init/wsl-interop.sh

if [[ "${INSTALL_GIT_CONFIG:-}" != "true" ]]; then
  echo "INSTALL_GIT_CONFIG not set, skipping gh auth wrapper"
  exit 0
fi

# Install the gh wrapper ahead of the apt-provided /usr/bin/gh on PATH. The wrapper
# authenticates gh on demand from the Windows "git:https://github.com" credential — on
# first use and after a token rotation — via the shared wsl_interop_credential helper,
# so no gh token is provisioned here. No eager sign-in: the wrapper handles it lazily on
# first use (mirroring 10, which likewise only installs its wrapper). The credential is
# the Git Credential Manager one, hence the INSTALL_GIT_CONFIG gate above.
#
# The wrapper is a real file under wsl/system, installed (idempotent overwrite) with the
# executable bit; sparse-checkout add makes it available in the /opt checkout at install.
git -C /opt/wsl-cloud-init sparse-checkout add wsl/system/usr/local/bin >/dev/null
install -D -m 755 /opt/wsl-cloud-init/wsl/system/usr/local/bin/gh /usr/local/bin/gh
