# wsl-cloud-init

Provisions fully configured WSL instances from scratch, using cloud-init to apply a consistent developer environment on first boot.

## Project layout

```
config/               — one .ps1 file per instance; defines distro, instance name, and any overrides
distros/<distro>/     — distro-specific cloud-init template and setup scripts, organised by version
  user-data.template  — cloud-init user-data with __PLACEHOLDERS__ substituted at provision time
  scripts/            — numbered shell scripts run by cloud-init on first boot
  tests/              — shell tests to verify the provisioned environment
scripts/              — Windows-side tooling; provision.ps1 drives the full WSL lifecycle
shared/               — files copied into every instance regardless of distro
  zsh/                — reusable zsh functions (gcreate, gclone)
  direnv/lib/         — direnv layout helpers for sdkman, pixi, fnm
```

## How it works

`provision.ps1` reads an instance config, substitutes runtime values into the distro's `user-data.template`, and provisions the WSL instance. On first boot, cloud-init writes config files, installs packages, and runs the numbered scripts in `distros/<distro>/scripts/` in order.

## Running the provisioner

```powershell
.\scripts\provision.ps1 -InstanceConfig myinstance
```

Optionally, a branch can be specified (defaults to `main`):

```powershell
.\scripts\provision.ps1 -InstanceConfig myinstance -Branch my-branch
```

## Running the tests

From inside the provisioned instance:

```zsh
/opt/wsl-cloud-init/distros/ubuntu/24.04/tests/run-tests.sh
```
