# Changelog

## [1.2.0](https://github.com/TomBorglum/wsl-cloud-init/compare/v1.1.0...v1.2.0) (2026-07-13)


### Features

* opt-in SonarQube Cloud MCP helper (shareable, secret-free) ([#57](https://github.com/TomBorglum/wsl-cloud-init/issues/57)) ([6d7c663](https://github.com/TomBorglum/wsl-cloud-init/commit/6d7c663f289e0da10126968e7b896ce294892b6f))

## [1.1.0](https://github.com/TomBorglum/wsl-cloud-init/compare/v1.0.0...v1.1.0) (2026-07-09)


### Features

* add -Ref flag to provision.ps1 for selecting a version ([#46](https://github.com/TomBorglum/wsl-cloud-init/issues/46)) ([da99dc3](https://github.com/TomBorglum/wsl-cloud-init/commit/da99dc3e0db691f70f40f88307e91a84818e142f))
* add prune-branches helper and enable fetch.prune ([#45](https://github.com/TomBorglum/wsl-cloud-init/issues/45)) ([27151b9](https://github.com/TomBorglum/wsl-cloud-init/commit/27151b9f0d1eac7411fad12d454e95cd0fb2b06b))
* add setup-direnv action with use_sdk ([#19](https://github.com/TomBorglum/wsl-cloud-init/issues/19)) ([1a99ea6](https://github.com/TomBorglum/wsl-cloud-init/commit/1a99ea6b41d59451ae961880991eddaf7a4a4c2b))
* add use_fnm directive to setup-direnv action ([#21](https://github.com/TomBorglum/wsl-cloud-init/issues/21)) ([cbce1e7](https://github.com/TomBorglum/wsl-cloud-init/commit/cbce1e782627b62b4fd7e08f44a62f10a36728bf))
* add use_pixi directive to setup-direnv ([#24](https://github.com/TomBorglum/wsl-cloud-init/issues/24)) ([ea42feb](https://github.com/TomBorglum/wsl-cloud-init/commit/ea42febc88718b8926f5be6142aa4d56cc81c122))
* authenticate gh from the Windows git credential on first use ([#23](https://github.com/TomBorglum/wsl-cloud-init/issues/23)) ([b5925ab](https://github.com/TomBorglum/wsl-cloud-init/commit/b5925ab3eb02314cf14f0d8e0e5d58a37fcc35c4))
* move claude settings to wsl/user/.claude, disable feedback survey ([#50](https://github.com/TomBorglum/wsl-cloud-init/issues/50)) ([5c89c26](https://github.com/TomBorglum/wsl-cloud-init/commit/5c89c26bd1882042e038bbc7ff6aa820cd334508))
* provision released versions via checkout-ref.ps1, drop provision.ps1 -Ref ([#47](https://github.com/TomBorglum/wsl-cloud-init/issues/47)) ([9a6addd](https://github.com/TomBorglum/wsl-cloud-init/commit/9a6addd609649a6f5581ba9b98d42c2ea8a6d520))
* record the provisioned ref in /etc/wsl-cloud-init-release ([#48](https://github.com/TomBorglum/wsl-cloud-init/issues/48)) ([3e3b26a](https://github.com/TomBorglum/wsl-cloud-init/commit/3e3b26a3b43bebf142da7a75bb0d57558c1912c9))


### Bug Fixes

* check out only the install paths into /opt ([#49](https://github.com/TomBorglum/wsl-cloud-init/issues/49)) ([c23d018](https://github.com/TomBorglum/wsl-cloud-init/commit/c23d01872cf76c015562848fc9ad18ed5b8301a3))
* correct drifted documentation claims and restructure docs ([#52](https://github.com/TomBorglum/wsl-cloud-init/issues/52)) ([9ec7fdc](https://github.com/TomBorglum/wsl-cloud-init/commit/9ec7fdc53a844d103b6fbd3384f800ee4fa37bb3))
* make clone-repo completion usable when repo list overflows terminal ([#41](https://github.com/TomBorglum/wsl-cloud-init/issues/41)) ([1971460](https://github.com/TomBorglum/wsl-cloud-init/commit/197146056bd2c00237343a5244bf5e68ff73783b))
* stop pj Tab-completion repeatedly appending project names ([#37](https://github.com/TomBorglum/wsl-cloud-init/issues/37)) ([9fd59c2](https://github.com/TomBorglum/wsl-cloud-init/commit/9fd59c2d7325670f00361cfa06327d3d58993ce5))

## 1.0.0 (2026-06-29)


### Features

* initial release ([#7](https://github.com/TomBorglum/wsl-cloud-init/issues/7)) ([688aaec](https://github.com/TomBorglum/wsl-cloud-init/commit/688aaece618ad61042fced6f6f52067b8f87ead1))

<!-- Maintained automatically by release-please from Conventional Commit messages. -->
