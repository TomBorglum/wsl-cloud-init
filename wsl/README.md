# `wsl/` — the WSL guest side

Everything that runs **inside** the WSL Linux instance lives here, mirroring `windows/`, which
holds the PowerShell that runs on the Windows **host**. Two kinds of thing live under `wsl/`:

- **`distros/`** — per-distro *provisioning logic*: the cloud-init entry point, the `install.sh`
  orchestrator, and the ordered `scripts/`. One subfolder per distro (`distros/ubuntu/`).
- **`user/` and `system/`** — the *files* copied onto **every** distro, laid out as a
  destination mirror. They sit beside `distros/` (not inside it) precisely because they are not
  distro-specific — anything outside `distros/` applies to all of them.

```
wsl/
├── distros/
│   └── ubuntu/
│       ├── cloud-init/user-data.template   # first-boot entry point (cloud-init only)
│       ├── install.sh                      # orchestrator (cloud-init runcmd OR manual re-run)
│       └── scripts/NN-install-*.sh         # ordered install steps
├── user/                                   # → /home/$TARGET_USER/   (installed owned by the user)
│   ├── .claude/skills/…                        → ~/.claude/skills/
│   └── .config/direnv/lib/*.sh                 → ~/.config/direnv/lib/
└── system/                                 # → /   (root-owned)
    └── usr/local/share/zsh/site-functions/
        ├── *.zsh                               → /usr/local/share/zsh/site-functions/
        └── git/*.zsh
```

## The mirror: path here = path on the instance

Under `user/` and `system/`, the path **equals the path the file lands at** on a provisioned
instance, so you can read the destination straight off the tree. Two roots stand in for the two
filesystem roots:

- **`user/`** → `/home/$TARGET_USER/…` — installed owned by the target user.
- **`system/`** → `/…` — installed root-owned.

## Which script installs what

Every tree is copied into place by one Ubuntu install script under `distros/ubuntu/scripts/`:

| Source (`wsl/…`)                                | Destination                             | Installed by                          | Gating |
| ----------------------------------------------- | --------------------------------------- | ------------------------------------- | ------ |
| `user/.claude/skills/`                          | `~/.claude/skills/`                     | `distros/ubuntu/scripts/07-install-claude-code.sh`   | `INSTALL_CLAUDE_CODE` |
| `user/.config/direnv/lib/`                      | `~/.config/direnv/lib/`                 | `distros/ubuntu/scripts/13-install-direnv-functions.sh` | — |
| `system/usr/local/share/zsh/site-functions/`    | `/usr/local/share/zsh/site-functions/` | `distros/ubuntu/scripts/12-install-zsh-functions.sh`    | — |

## The one place the mirror is not literal: `git/`

The `git/` subfolder under `system/usr/local/share/zsh/site-functions/` is a **source-side
grouping**, not a real destination subdirectory. It holds the helpers installed only when
`INSTALL_GIT_CONFIG=true`, and the install script **flattens** it into the parent directory (e.g.
`system/usr/local/share/zsh/site-functions/git/update-branch.zsh` lands at
`/usr/local/share/zsh/site-functions/update-branch.zsh`, not in a `git/` subdir). Everything
outside `git/` is always installed.
