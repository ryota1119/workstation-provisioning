SHELL := /bin/zsh

.PHONY: help
help:
	@echo "Usage: make [target]"
	@echo ""
	@echo "Main Targets:"
	@echo "  mac-bootstrap       - Xcode Command Line Tools, Homebrew, Ansibleの導入"
	@echo "  install-deps        - Ansibleコレクションのインストール"
	@echo "  provision           - 環境構築フルプロビジョニング（全ロール実行）"
	@echo "  all                 - 'mac-bootstrap', 'install-deps', 'provision' を順に実行"
	@echo ""
	@echo "Individual Roles:"
	@echo "  homebrew            - Homebrewパッケージのインストール"
	@echo "  mas                 - Mac App Storeアプリのインストール"
	@echo "  asdf                - asdfでプラグイン・バージョンをインストール"
	@echo "  chezmoi             - chezmoiのセットアップ（dotfiles管理）"
	@echo "  mac-setting         - macOSシステム設定の適用"
	@echo ""
	@echo "Upgrade Commands:"
	@echo "  upgrade             - 全パッケージのアップグレード（Homebrew + MAS）"
	@echo ""
	@echo "Utilities:"
	@echo "  doctor              - 必須ツールの事前チェック（Homebrew, Ansible等）"
	@echo "  clean               - 一時ファイルのクリーンアップ"
	@echo "  check               - Ansible構文チェック"

.PHONY: mac-bootstrap
mac-bootstrap:
	@echo "Running mac bootstrap script .."
	sh ./scripts/mac-bootstrap.sh

.PHONY: install-deps
install-deps:
	@echo "Installing Ansible collections..."
	@ansible-galaxy collection install -r requirements.yml

.PHONY: provision
provision:
	@echo "Running full provisioning..."
	@ansible-playbook site.yml -i inventory.ini --tags "provision" -K

.PHONY: homebrew
homebrew:
	@echo "Installing Homebrew packages..."
	@ansible-playbook site.yml -i inventory.ini --tags "homebrew"

.PHONY: mas
mas:
	@echo "Installing Mac App Store apps..."
	@ansible-playbook site.yml -i inventory.ini --tags "mas" -K

.PHONY: asdf
asdf:
	@echo "Installing asdf packages..."
	@ansible-playbook site.yml -i inventory.ini --tags "asdf"

.PHONY: chezmoi
chezmoi:
	@echo "Setting up chezmoi..."
	@ansible-playbook site.yml -i inventory.ini --tags "chezmoi"

.PHONY: mac-setting
mac-setting:
	@echo "Applying mac settings..."
	@ansible-playbook site.yml -i inventory.ini --tags mac-setting

.PHONY: doctor
doctor:
	@command -v brew >/dev/null 2>&1 || echo "⚠️ Homebrew未導入（make bootstrap で導入）"
	@command -v ansible >/dev/null 2>&1 || echo "⚠️ Ansible未導入（make bootstrap で導入）"

.PHONY: all
all: 
	@echo "Running all tasks..."
	@make mac-bootstrap
	@source ~/.zshrc
	@make install-deps
	@make provision

.PHONY: upgrade
upgrade:
	@echo "Upgrading all packages (Homebrew + Mac App Store)..."
	@ansible-playbook site.yml -i inventory.ini --tags upgrade --ask-become-pass

.PHONY: clean
clean:
	@echo "Cleaning up temporary files..."
	@rm -rf .ansible/tmp/
	@rm -rf logs/

.PHONY: check
check:
	@echo "Checking Ansible syntax..."
	@ansible-playbook site.yml -i inventory.ini -- syntax-check
