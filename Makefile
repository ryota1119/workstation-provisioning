SHELL := /bin/zsh

.PHONY: help
help:
	@echo "Usage: make [target]"
	@echo ""
	@echo "Main Targets:"
	@echo "  all                 - 新規PC初回セットアップ（mac-bootstrap + install-deps + provision）"
	@echo "  provision           - 全ロールを一括インストール（--tags install）"
	@echo "  upgrade             - パッケージとdotfilesを一括更新（--tags upgrade）"
	@echo ""
	@echo "Individual Roles:"
	@echo "  homebrew            - Homebrewパッケージのインストール"
	@echo "  mas                 - Mac App Storeアプリのインストール"
	@echo "  mise                - miseでツールバージョンをインストール"
	@echo "  mise-prune          - 未使用かつ同一ツールに複数あるmiseのバージョンを削除（dry-run）"
	@echo "  mise-prune-apply    - 上記を実際に削除（対話確認あり）"
	@echo "  chezmoi             - chezmoiのセットアップ（dotfiles管理）"
	@echo "  mac-setting         - macOSシステム設定の適用"
	@echo ""
	@echo "Bootstrap & Utilities:"
	@echo "  mac-bootstrap       - Xcode CLT、Homebrew、Ansibleの導入"
	@echo "  install-deps        - Ansibleコレクションのインストール"
	@echo "  doctor              - 必須ツールの事前チェック"
	@echo "  check               - Ansible構文チェック"
	@echo "  clean               - 一時ファイルのクリーンアップ"

# ============================================================
# Main Targets
# ============================================================

.PHONY: all
all: mac-bootstrap install-deps provision

.PHONY: provision
provision:
	@echo "Running full provisioning (install)..."
	@ansible-playbook site.yml --tags "install"

.PHONY: upgrade
upgrade:
	@echo "Upgrading packages and dotfiles..."
	@ansible-playbook site.yml --tags "upgrade"

# ============================================================
# Individual Roles
# ============================================================

.PHONY: homebrew
homebrew:
	@echo "Running homebrew role..."
	@ansible-playbook site.yml --tags "homebrew"

.PHONY: mas
mas:
	@echo "Running mas role..."
	@ansible-playbook site.yml --tags "mas"

.PHONY: mise
mise:
	@echo "Running mise role..."
	@ansible-playbook site.yml --tags "mise"

.PHONY: mise-prune
mise-prune:
	@sh ./scripts/mise-prune.sh

.PHONY: mise-prune-apply
mise-prune-apply:
	@sh ./scripts/mise-prune.sh --apply

.PHONY: chezmoi
chezmoi:
	@echo "Running chezmoi role..."
	@ansible-playbook site.yml --tags "chezmoi"

.PHONY: mac-setting
mac-setting:
	@echo "Running mac-setting role..."
	@ansible-playbook site.yml --tags "mac-setting"

# ============================================================
# Bootstrap & Utilities
# ============================================================

.PHONY: mac-bootstrap
mac-bootstrap:
	@echo "Running mac bootstrap script..."
	@sh ./scripts/mac-bootstrap.sh

.PHONY: install-deps
install-deps:
	@echo "Installing Ansible collections..."
	@ansible-galaxy collection install -r requirements.yml

.PHONY: doctor
doctor:
	@command -v brew >/dev/null 2>&1 || echo "⚠️  Homebrew未導入（make mac-bootstrap で導入）"
	@command -v ansible >/dev/null 2>&1 || echo "⚠️  Ansible未導入（make mac-bootstrap で導入）"

.PHONY: check
check:
	@echo "Checking Ansible syntax..."
	@ansible-playbook site.yml --syntax-check

.PHONY: clean
clean:
	@echo "Cleaning up temporary files..."
	@rm -rf .ansible/tmp/ logs/
