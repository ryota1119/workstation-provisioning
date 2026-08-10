# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Ansible-based macOS provisioning project. Manages Homebrew packages, Mac App Store apps, mise language runtimes, chezmoi dotfiles, and macOS system settings across multiple machines.

## Commands

```bash
make all            # New machine: mac-bootstrap + install-deps + provision
make provision      # Install all roles, then initialize and apply dotfiles
make upgrade        # Daily update: Homebrew + MAS only (chezmoi is not run)

make homebrew       # Run only the homebrew role
make mas            # Run only the mas role
make mise           # Run only the mise role
make chezmoi        # Run the chezmoi script (init + apply)
make mac-setting    # Run only the mac-setting role
make launchd        # Register the LaunchAgent that runs `make upgrade` on a schedule

make check          # Ansible syntax check
make doctor         # Verify required tools are installed
make install-deps   # Install Ansible collections (requirements.yml)

make mise-prune         # Dry-run: list unused mise versions to delete
make mise-prune-apply   # Interactive: delete unused mise versions
```

## Architecture

The playbook (`site.yml`) runs the roles below in dependency order. Chezmoi is managed separately by `scripts/chezmoi.sh`, invoked through the Makefile after Ansible completes:

1. **homebrew** — Installs Formula and Cask packages. Casks requiring sudo are printed as manual instructions rather than installed automatically.
2. **mas** — Mac App Store installs via `mas` CLI. Can be disabled per-machine with `enable_mas: false`.
3. **mise** — Language runtime installs (Node, Python, PHP, Go, etc.). Only runs on `install` tag, never on `upgrade` (to avoid unexpected upgrades).
4. **mac-setting** — Applies `defaults write` macOS system settings. Only runs on `install` tag, not `upgrade` (triggers Finder/Dock restart).
5. **chezmoi-config-bootstrap** — Pre-generates `chezmoi.toml` so `chezmoi init` does not prompt for 1Password interactively. `install` tag only.
6. **workspace-base** — Clones/updates the base repositories under `~/Workspace`. Runs on both `install` and `upgrade`.
7. **launchd** — Deploys the LaunchAgent that runs `make upgrade` on a schedule. Never runs on `upgrade` (its `launchctl bootout` would kill the very job invoking it).

**chezmoi** — Dotfiles management outside Ansible. `make provision` runs `init` + `apply`; `make chezmoi` runs `init` + `apply`. `make upgrade` does NOT touch chezmoi (dotfiles are only initialized/applied during provisioning). `chezmoi-init`/`chezmoi-upgrade`/`chezmoi-apply` targets remain available for manual use. Init/apply skip successfully if 1Password CLI is not authenticated.

### Variable layering

- `group_vars/all.yml` — base package lists shared by all machines
- `host_vars/{hostname}.yml` — machine-specific overrides/additions (generated from `_template.yml` by `mac-bootstrap.sh`)

Package lists are merged: `brew_formula` + `brew_formula_extra`, `brew_casks_normal` + `brew_casks_normal_extra`, etc.

### Adding packages

- **All machines**: edit `group_vars/all.yml`
- **One machine only**: edit `host_vars/{hostname}.yml` using the `_extra` suffix variables
- **Needs sudo to install**: add to `brew_casks_sudo_required` / `brew_casks_sudo_required_extra` — these print a manual install message instead of running automatically

### Tag design

| Tag | Roles included |
|-----|----------------|
| `install` | homebrew, mas, mise, mac-setting, chezmoi-config-bootstrap, workspace-base, launchd |
| `upgrade` | homebrew, mas, workspace-base |
| `homebrew` / `mas` / `mise` / `mac-setting` / `workspace-base` / `launchd` | individual role only |

Chezmoi is not an Ansible tag. Use the Makefile targets described above.

### Scheduled `make upgrade` (launchd)

`scripts/upgrade-scheduled.sh` is the wrapper the LaunchAgent runs. It writes the full log to `logs/upgrade-<timestamp>.log` (keeping the last 20), summarizes it with `claude -p --model haiku` over stdin, and posts the result to the macOS notification centre. It never calls sudo — sudo-required Casks only surface as the Ansible guidance text, which the script detects by grepping the log for `手動` and appends a warning to the notification.

The plist is generated from `roles/launchd/templates/workstation-upgrade.plist.j2`; do not hand-edit the deployed file under `~/Library/LaunchAgents/`. Schedule and on/off live in `group_vars/all.yml`:

- `launchd_upgrade_schedule` — list of `hour`/`minute` entries. Add entries to run more than twice a day.
- `enable_launchd_upgrade` — set to `false` (per machine via `host_vars`) to bootout the agent and delete the plist.

Apply changes with `make launchd`. Note that `launchctl` fires missed calendar events once on wake from sleep, but days when the machine was powered off are skipped entirely.

### inventory.ini

Generated automatically by `mac-bootstrap.sh` from `scutil --get LocalHostName`. It is `.gitignore`d. Use `inventory.ini.example` as a reference if needed.
