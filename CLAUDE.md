# wsl-cloud-init
The project automates WSL instance provisioning using cloud init.

## Windows Entry Point
The script `scripts/provision.ps1` is the entry point in Windows to kick off the provisioning of a WSL instance.

Invoke from a CMD shell:
```cmd
powershell -ExecutionPolicy Bypass -File scripts\provision.ps1 -InstanceConfig myinstance
```

The configuration file at `config/myinstance.ps1` must contain:
```powershell
$DistroTemplatePath   = "ubuntu\24.04"
$DistroInstallName    = "Ubuntu-24.04"
$InstanceName         = "MyInstance"
```

## Cloud Init templates
Cloud Init templates must be located at `distros/$DistroTemplatePath/user-data.template` and must be named `user-data.template`.

The script fetches the Cloud Init template specified by `$DistroTemplatePath` in the configuration file and processes it by replacing all placeholders with actual values.
A placeholder must have the form `__UPPER_SNAKE_CASE__` and only placeholders present in the script may be used in the template file.

The result is the `user-data/$InstanceName.user-data` file that will be used by Cloud Init when configuring the WSL instance.

### Cloud Init Scripts
The `user-data` file runs scripts from `distros/$DistroTemplatePath/scripts/` to install tools in the WSL instance. Scripts must be self-contained, should only have one concern, and are prefixed with a number to control execution order.

Tools should be downloaded to the `/tmp/` folder and installed like this:
```bash
#!/bin/bash
set -e
source /opt/wsl-cloud-init-config.sh

curl -fsSL https://pixi.sh/install.sh -o /tmp/pixi-install.sh
sudo -u "$LINUX_USERNAME" PIXI_NO_PATH_UPDATE=1 bash /tmp/pixi-install.sh
rm -f /tmp/pixi-install.sh
```

Each script must install exactly one tool. A script must not install any dependencies (e.g. runtimes, package managers) as a prerequisite — if the tool's installer requires a dependency, find a bundled or standalone installer that includes everything needed.

## Cloud Init Test Scripts
To verify the WSL instance has been provisioned as expected the `user-data` file places a number of test scripts in `/opt/wsl-cloud-init/distros/ubuntu/24.04/tests/`. 
Invoke `run-tests.sh` to run all tests. If all pass the WSL instance has been provisioned as expected.

## Shared
The `shared` folder contains functionality that is not coupled to a specific distro but rather to the tools being installed.

Shared `zsh` functions must be placed in the `shared/zsh/` folder. All `*.zsh` files in this folder are sourced by `.zshrc` in the WSL instance.

Shared `direnv` functions must be placed in the `shared/direnv/lib/` folder. All `*.sh` files in this folder are activated by `direnv` in the WSL instance.

### Direnv
Tools to be used with `direnv` must only be added to the path when activated by `direnv`, i.e. when explicitly activated in `.envrc`.

Activating a tool must ensure that it is only added to the path as long as `direnv` is loaded. This can typically be controlled using `PATH_add`.