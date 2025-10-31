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
	@echo "  1password           - 1Passwordアプリ・CLIのインストールと認証確認"
	@echo ""
	@echo "Chezmoi (dotfiles管理):"
	@echo "  chezmoi-init        - chezmoiの初期化（dotfilesリポジトリをクローン）"
	@echo "  chezmoi-apply       - dotfilesを適用（変更を反映）"
	@echo "  chezmoi-update      - dotfilesを更新（リポジトリから取得して適用）"
	@echo ""
	@echo "Upgrade Commands:"
	@echo "  upgrade             - 全パッケージのアップグレード（Homebrew + MAS）"
	@echo "  upgrade-homebrew    - Homebrewパッケージのみアップグレード"
	@echo "  upgrade-mas         - Mac App Storeアプリのみアップグレード"
	@echo "  upgrade-formula     - Homebrew Formulaのみアップグレード"
	@echo "  upgrade-cask        - Homebrew Cask（通常）のみアップグレード"
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
	@ansible-playbook site.yml -i inventory.ini

.PHONY: homebrew
homebrew:
	@echo "Installing Homebrew packages..."
	@ansible-playbook site.yml -i inventory.ini --tags "homebrew,install"

.PHONY: mas
mas:
	@echo "Installing Mac App Store apps..."
	@ansible-playbook site.yml -i inventory.ini --tags "mas,install"

.PHONY: asdf
asdf:
	@echo "Installing asdf packages..."
	@ansible-playbook site.yml -i inventory.ini --tags asdf

.PHONY: 1password
1password:
	@echo "Installing 1Password app and CLI..."
	@ansible-playbook site.yml -i inventory.ini --tags 1password

.PHONY: chezmoi-init
chezmoi-init:
	@echo "Initializing chezmoi..."
	@ansible-playbook site.yml -i inventory.ini --tags "chezmoi,init"

.PHONY: chezmoi-apply
chezmoi-apply:
	@echo "Applying dotfiles..."
	@ansible-playbook site.yml -i inventory.ini --tags "chezmoi,apply"

.PHONY: chezmoi-update
chezmoi-update:
	@echo "Updating dotfiles from repository..."
	@ansible-playbook site.yml -i inventory.ini --tags "chezmoi,update"

.PHONY: test
test:
	@echo "Running test tasks..."
	@ansible-playbook site.yml -i inventory.ini --tags test

.PHONY: doctor
doctor:
	@command -v brew >/dev/null 2>&1 || echo "⚠️ Homebrew未導入（make bootstrap で導入）"
	@command -v ansible >/dev/null 2>&1 || echo "⚠️ Ansible未導入（make bootstrap で導入）"

.PHONY: all
all: bootstrap install-deps provision

.PHONY: upgrade
upgrade:
	@echo "Upgrading all packages (Homebrew + Mac App Store)..."
	@ansible-playbook site.yml -i inventory.ini --tags upgrade

.PHONY: upgrade-homebrew
upgrade-homebrew:
	@echo "Upgrading Homebrew packages..."
	@ansible-playbook site.yml -i inventory.ini --tags "homebrew,upgrade"

.PHONY: upgrade-mas
upgrade-mas:
	@echo "Upgrading Mac App Store apps..."
	@ansible-playbook site.yml -i inventory.ini --tags "mas,upgrade"

.PHONY: upgrade-formula
upgrade-formula:
	@echo "Upgrading Homebrew formulae..."
	@ansible-playbook site.yml -i inventory.ini --tags "homebrew,upgrade,formula"

.PHONY: upgrade-cask
upgrade-cask:
	@echo "Upgrading Homebrew casks (通常のみ)..."
	@ansible-playbook site.yml -i inventory.ini --tags "homebrew,upgrade,cask"

.PHONY: clean
clean:
	@echo "Cleaning up temporary files..."
	@rm -rf .ansible/tmp/
	@rm -rf logs/

.PHONY: check
check:
	@echo "Checking Ansible syntax..."
	@ansible-playbook site.yml -i inventory.ini -- syntax-check
