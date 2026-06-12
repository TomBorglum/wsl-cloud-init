# wsl-cloud-init

## Conventions

Placeholders in `user-data.template` and instance configs use the `__UPPER_SNAKE_CASE__` double-underscore pattern (e.g. `__INSTANCE_NAME__`). `provision.ps1` substitutes these at provision time.

## How it works

`provision.ps1` reads an instance config, substitutes runtime values into the distro's `user-data.template`, and provisions the WSL instance. On first boot, cloud-init performs a sparse checkout of this repository, writes config files, installs packages, and runs the numbered scripts in `distros/<distro>/<version>/scripts/` in order. Files from `shared/` are installed into the instance as part of this process.
