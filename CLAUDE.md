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

make check          # Ansible syntax check
make doctor         # Verify required tools are installed
make install-deps   # Install Ansible collections (requirements.yml)

make mise-prune         # Dry-run: list unused mise versions to delete
make mise-prune-apply   # Interactive: delete unused mise versions
```

## Architecture

The playbook (`site.yml`) runs four roles in dependency order. Chezmoi is managed separately by `scripts/chezmoi.sh`, invoked through the Makefile after Ansible completes:

1. **homebrew** — Installs Formula and Cask packages. Casks requiring sudo are printed as manual instructions rather than installed automatically.
2. **mas** — Mac App Store installs via `mas` CLI. Can be disabled per-machine with `enable_mas: false`.
3. **mise** — Language runtime installs (Node, Python, PHP, Go, etc.). Only runs on `install` tag, never on `upgrade` (to avoid unexpected upgrades).
4. **mac-setting** — Applies `defaults write` macOS system settings. Only runs on `install` tag, not `upgrade` (triggers Finder/Dock restart).

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
| `install` | homebrew, mas, mise, mac-setting |
| `upgrade` | homebrew, mas |
| `homebrew` / `mas` / `mise` / `mac-setting` | individual role only |

Chezmoi is not an Ansible tag. Use the Makefile targets described above.

### inventory.ini

Generated automatically by `mac-bootstrap.sh` from `scutil --get LocalHostName`. It is `.gitignore`d. Use `inventory.ini.example` as a reference if needed.
