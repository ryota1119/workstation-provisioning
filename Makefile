SHELL := /bin/zsh

.PHONY: help
help:
	@echo "Usage: make [target]"
	@echo ""
	@echo "Main Targets:"
	@echo "  mac-bootstrap       - Xcode Command Line Tools、Homebrew、Ansibleの導入"
	@echo "  install-deps        - Ansibleコレクションのインストール"
	@echo "  provision           - 環境構築フルプロビジョニング（全ロール実行）"
	@echo "  all                 - 上記3つを順に実行"
	@echo ""
	@echo "Individual Roles:"
	@echo "  homebrew            - Homebrewパッケージのインストール"
	@echo "  mas                 - Mac App Storeアプリのインストール"
	@echo "  mise                - miseでプラグイン・バージョンをインストール"
	@echo "  chezmoi             - chezmoiのセットアップ（dotfiles管理）"
	@echo "  mac-setting         - macOSシステム設定の適用"
	@echo ""
	@echo "Upgrade Commands:"
	@echo "  upgrade             - 全パッケージのアップグレード（Homebrew + MAS）"
	@echo ""
	@echo "Utilities:"
	@echo "  doctor              - 必須ツールの事前チェック"
	@echo "  clean               - 一時ファイルのクリーンアップ"
	@echo "  check               - Ansible構文チェック"

.PHONY: mac-bootstrap
mac-bootstrap:
	@echo "Running mac bootstrap script..."
	@sh ./scripts/mac-bootstrap.sh

.PHONY: install-deps
install-deps:
	@echo "Installing Ansible collections..."
	@ansible-galaxy collection install -r requirements.yml

.PHONY: provision
provision:
	@echo "Running full provisioning..."
	@ansible-playbook site.yml --tags "provision" -K

.PHONY: homebrew
homebrew:
	@echo "Installing Homebrew packages..."
	@ansible-playbook site.yml --tags "homebrew"

.PHONY: mas
mas:
	@echo "Installing Mac App Store apps..."
	@ansible-playbook site.yml --tags "mas" -K

.PHONY: mise
mise:
	@echo "Installing mise packages..."
	@ansible-playbook site.yml --tags "mise"

.PHONY: chezmoi
chezmoi:
	@echo "Setting up chezmoi..."
	@ansible-playbook site.yml --tags "chezmoi"

.PHONY: mac-setting
mac-setting:
	@echo "Applying macOS settings..."
	@ansible-playbook site.yml --tags "mac-setting"

.PHONY: doctor
doctor:
	@command -v brew >/dev/null 2>&1 || echo "⚠️  Homebrew未導入（make mac-bootstrap で導入）"
	@command -v ansible >/dev/null 2>&1 || echo "⚠️  Ansible未導入（make mac-bootstrap で導入）"

.PHONY: all
all: mac-bootstrap install-deps provision

.PHONY: upgrade
upgrade:
	@echo "Upgrading all packages..."
	@ansible-playbook site.yml --tags "upgrade" -K

.PHONY: clean
clean:
	@echo "Cleaning up temporary files..."
	@rm -rf .ansible/tmp/ logs/

.PHONY: check
check:
	@echo "Checking Ansible syntax..."
	@ansible-playbook site.yml --syntax-check
