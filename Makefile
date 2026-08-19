SHELL := /bin/zsh
PYTHON_VERSION := $(shell awk -F'"' '/^python =/ { print $$2; exit }' mise.toml)
MISE_EXEC := mise exec python@$(PYTHON_VERSION) --
ANSIBLE_PLAYBOOK := $(MISE_EXEC) ansible-playbook
ANSIBLE_GALAXY := $(MISE_EXEC) ansible-galaxy
export PATH := /opt/homebrew/bin:/opt/homebrew/sbin:$(HOME)/.local/share/mise/shims:$(PATH)

.PHONY: help
help:
	@echo "Usage: make [target]"
	@echo ""
	@echo "Main Targets:"
	@echo "  all                 - 新規PC初回セットアップ（mac-bootstrap + install-deps + provision）"
	@echo "  provision           - 全ロールのインストール後、dotfilesを初期化・適用"
	@echo "  upgrade             - パッケージとdotfilesを一括更新（--tags upgrade）"
	@echo ""
	@echo "Individual Roles:"
	@echo "  homebrew                   - Homebrewパッケージのインストール"
	@echo "  mas                        - Mac App Storeアプリのインストール"
	@echo "  mise                       - miseでツールバージョンをインストール"
	@echo "  mise-prune                 - 未使用かつ同一ツールに複数あるmiseのバージョンを削除（dry-run）"
	@echo "  mise-prune-apply           - 上記を実際に削除（対話確認あり）"
	@echo "  chezmoi                    - chezmoiを初期化してdotfilesを適用"
	@echo "  chezmoi-config-bootstrap   - chezmoi.tomlの事前生成のみ(1Password対話プロンプト回避)"
	@echo "  workspace-base             - workspace-base(~/Workspace)のclone/更新のみ"
	@echo "  workspace-repositories     - ghq配下のMCPリポジトリのclone/更新と依存同期"
	@echo "  mac-setting                - macOSシステム設定の適用"
	@echo ""
	@echo "Bootstrap & Utilities:"
	@echo "  mac-bootstrap       - Xcode CLT、Homebrew、Ansibleの導入"
	@echo "  install-deps        - Ansibleコレクションのインストール"
	@echo "  doctor              - 必須ツールの事前チェック"
	@echo "  check               - Ansible構文チェック"
	@echo "  clean               - 一時ファイルのクリーンアップ"

# ============================================================
# メインターゲット
# ============================================================

.PHONY: all
all: mac-bootstrap install-deps provision

.PHONY: provision
provision:
	@echo "Running full provisioning (install)..."
	@$(ANSIBLE_PLAYBOOK) site.yml --tags "install"
	@$(MAKE) chezmoi-init
	@$(MAKE) chezmoi-apply

.PHONY: upgrade
upgrade:
	@echo "Upgrading packages..."
	@$(ANSIBLE_PLAYBOOK) site.yml --tags "upgrade"

# ============================================================
# 個別ロール
# ============================================================

.PHONY: homebrew
homebrew:
	@echo "Running homebrew role..."
	@$(ANSIBLE_PLAYBOOK) site.yml --tags "homebrew"

.PHONY: mas
mas:
	@echo "Running mas role..."
	@$(ANSIBLE_PLAYBOOK) site.yml --tags "mas"

.PHONY: mise
mise:
	@echo "Running mise role..."
	@$(ANSIBLE_PLAYBOOK) site.yml --tags "mise"

.PHONY: mise-prune
mise-prune:
	@sh ./scripts/mise-prune.sh

.PHONY: mise-prune-apply
mise-prune-apply:
	@sh ./scripts/mise-prune.sh --apply

.PHONY: chezmoi
chezmoi:
	@echo "Running chezmoi script..."
	@bash ./scripts/chezmoi.sh

.PHONY: chezmoi-init
chezmoi-init:
	@bash ./scripts/chezmoi.sh init

.PHONY: chezmoi-upgrade
chezmoi-upgrade:
	@bash ./scripts/chezmoi.sh upgrade

.PHONY: chezmoi-apply
chezmoi-apply:
	@bash ./scripts/chezmoi.sh apply

.PHONY: chezmoi-config-bootstrap
chezmoi-config-bootstrap:
	@echo "Running chezmoi-config-bootstrap role..."
	@$(ANSIBLE_PLAYBOOK) site.yml --tags "chezmoi-config-bootstrap"

.PHONY: workspace-base
workspace-base:
	@echo "Running workspace-base role..."
	@$(ANSIBLE_PLAYBOOK) site.yml --tags "workspace-base"

.PHONY: workspace-repositories
workspace-repositories:
	@echo "Running workspace-repositories role..."
	@$(ANSIBLE_PLAYBOOK) site.yml --tags "workspace-repositories"


.PHONY: mac-setting
mac-setting:
	@echo "Running mac-setting role..."
	@$(ANSIBLE_PLAYBOOK) site.yml --tags "mac-setting"

# ============================================================
# ブートストラップとユーティリティ
# ============================================================

.PHONY: mac-bootstrap
mac-bootstrap:
	@echo "Running mac bootstrap script..."
	@bash ./scripts/mac-bootstrap.sh

.PHONY: install-deps
install-deps:
	@echo "Installing Ansible collections..."
	@$(ANSIBLE_GALAXY) collection install -r requirements.yml

.PHONY: doctor
doctor:
	@missing=0; \
	command -v brew >/dev/null 2>&1 || { echo "⚠️  Homebrew未導入（make mac-bootstrap で導入）"; missing=1; }; \
	command -v mise >/dev/null 2>&1 || { echo "⚠️  mise未導入（make mac-bootstrap で導入）"; missing=1; }; \
	$(ANSIBLE_PLAYBOOK) --version >/dev/null 2>&1 || { echo "⚠️  Ansible未導入（make mac-bootstrap で導入）"; missing=1; }; \
	exit $$missing

.PHONY: check
check:
	@echo "Checking Ansible syntax..."
	@$(ANSIBLE_PLAYBOOK) site.yml --syntax-check

.PHONY: clean
clean:
	@echo "Cleaning up temporary files..."
	@rm -rf .ansible/tmp/ logs/
