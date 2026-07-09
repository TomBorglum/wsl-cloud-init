# `wsl/` — the WSL guest side

Everything that runs **inside** the WSL Linux instance lives here, mirroring `windows/`, which
holds the PowerShell that runs on the Windows **host**. Two kinds of thing live under `wsl/`:

- **`distros/`** — per-distro *provisioning logic*: the cloud-init entry point, the `install.sh`
  orchestrator, and the ordered `scripts/`. One subfolder per distro (`distros/ubuntu/`).
- **`user/` and `system/`** — the *files* copied onto every distro, laid out as a destination
  mirror. Under these two trees the source path **equals the path the file lands at** on a
  provisioned instance, so you can read the destination straight off the tree.

```
wsl/
├── distros/
│   └── ubuntu/
│       ├── cloud-init/user-data.template   # first-boot entry point (cloud-init only)
│       ├── install.sh                      # orchestrator (cloud-init runcmd OR manual re-run)
│       └── scripts/NN-install-*.sh         # ordered install steps
├── user/                                   # → /home/$TARGET_USER/   (installed owned by the user)
│   ├── .claude/settings.json                   → ~/.claude/settings.json
│   ├── .claude/skills/…                        → ~/.claude/skills/
│   └── .config/direnv/lib/*.sh                 → ~/.config/direnv/lib/
└── system/                                 # → /   (root-owned)
    └── usr/local/
        ├── bin/{gh,open}                       → /usr/local/bin/
        ├── lib/wsl-cloud-init/wsl-interop.sh   → /usr/local/lib/wsl-cloud-init/
        └── share/zsh/site-functions/
            ├── pj-completion.zsh               → /usr/local/share/zsh/site-functions/
            └── git/*.zsh                       → /usr/local/share/zsh/site-functions/ (flattened)
```

## Which script installs what

| Source (`wsl/…`) | Destination | Installed by | Gating |
| --- | --- | --- | --- |
| `user/.claude/settings.json` | `~/.claude/settings.json` | `distros/ubuntu/scripts/08-install-claude-code.sh` | `INSTALL_CLAUDE_CODE` |
| `user/.claude/skills/` | `~/.claude/skills/` | `distros/ubuntu/scripts/08-install-claude-code.sh` | `INSTALL_CLAUDE_CODE` |
| `user/.config/direnv/lib/` | `~/.config/direnv/lib/` | `distros/ubuntu/scripts/14-install-direnv-functions.sh` | — |
| `system/usr/local/bin/gh` | `/usr/local/bin/gh` | `distros/ubuntu/scripts/07-install-git-config.sh` | `INSTALL_GIT_CONFIG` |
| `system/usr/local/bin/open` | `/usr/local/bin/open` | `distros/ubuntu/scripts/09-install-open-interop.sh` | — |
| `system/usr/local/lib/wsl-cloud-init/` | `/usr/local/lib/wsl-cloud-init/` | `distros/ubuntu/install.sh` (bootstrap) | — |
| `system/usr/local/share/zsh/site-functions/` | `/usr/local/share/zsh/site-functions/` | `distros/ubuntu/scripts/13-install-zsh-functions.sh` | — (`git/` needs `INSTALL_GIT_CONFIG`) |

`wsl-interop.sh` is installed by `install.sh` directly rather than by a numbered script: `install.sh`
sources it to derive the path to `powershell.exe` before any script runs, and the `gh` wrapper
re-sources it at runtime, so neither can depend on the `/opt` checkout still being present.

## Two places the mirror is not literal

**`git/` is flattened.** The `git/` subfolder under `system/usr/local/share/zsh/site-functions/` is a
source-side grouping, not a real destination subdirectory. It holds the helpers installed only when
`INSTALL_GIT_CONFIG=true`, and `13-install-zsh-functions.sh` copies them into the parent directory —
so `git/rebase-branch.zsh` lands at `/usr/local/share/zsh/site-functions/rebase-branch.zsh`.

**`/usr/local/lib/wsl-cloud-init/` also receives files from `windows/`.** Alongside `wsl-interop.sh`,
`install.sh` installs `windows/lib/Wsl.ps1` and `windows/lib/Credentials.ps1` there, co-locating the
shell helper with the PowerShell it dot-sources.
