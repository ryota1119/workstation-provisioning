# macOS Provisioning

macOS環境のセットアップと管理を自動化するAnsibleプロジェクトです。Homebrewを使用してアプリケーションのインストール、更新、管理を行います。

## 🚀 特徴

- **自動化されたセットアップ**: 新規macOS環境の初期設定を自動化
- **スマートなアップグレード**: sudo権限が必要なアプリを自動分離
- **Homebrew統合**: Formula、Cask、MASアプリを一元管理
- **1Password連携**: SSH認証エージェントとして1Passwordを使用
- **dotfiles管理**: chezmoiでdotfilesを自動展開
- **Ansible**: 冪等性を保った設定管理
- **開発環境管理**: asdfで複数言語のバージョン管理
- **マルチOS対応**: macOS専用roleと共通roleを分離し、将来的なLinux対応も可能

## 📋 前提条件

- macOS 10.15以降
- 管理者権限
- インターネット接続
- 1Passwordアプリ（手動インストール済み）
- Homebrew（手動インストール済み）
- Git（Homebrewでインストール済み）

## 🛠️ セットアップ

### 1. 1Passwordのインストールとログイン

1Passwordアプリを手動でインストールし、ログインしておいてください。

App Storeからインストールするか、[公式サイト](https://downloads.1password.com/mac/1Password.zip)からダウンロード

### 2. SSH認証エージェントを1Passwordに変更

1PasswordのSSH認証エージェントを使用するように設定します。

1Password → 設定 → 開発者 → 「sshエージェントを使用」にチェックを入れる

以下の環境変数を設定

```bash
export SSH_AUTH_SOCK=~/Library/Group\ Containers/2BUA8C4S2C.com.1password/t/agent.sock
```

この設定を永続化するには、`~/.zshrc` または `~/.zprofile` に追加してください：

```bash
echo 'export SSH_AUTH_SOCK=~/Library/Group\ Containers/2BUA8C4S2C.com.1password/t/agent.sock' >> ~/.zshrc
```

### 3. Homebrewのインストールとパスの設定

Homebrewを手動でインストールし、パスを通しておきます。

```bash
# Homebrewのインストール
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# パスの設定（Apple Silicon Macの場合）
eval "$(/opt/homebrew/bin/brew shellenv)"
```

### 4. Gitのインストール

リポジトリをクローンするために、HomebrewでGitをインストールします。

```bash
brew install git
```

### 5. リポジトリのクローン

workstation-provisioningリポジトリをクローンします。

```bash
git clone git@github.com:ryota1119/workstation-provisioning.git
cd workstation-provisioning
```

### 6. ブートストラップスクリプトの実行

asdf、Python、Ansibleなどを自動インストールします。

```bash
make mac-bootstrap
```

このスクリプトは以下を実行します：

- Homebrewの確認
- Xcode Command Line Toolsのインストール
- asdfのインストール（Homebrew経由）
- Pythonのインストール（asdf経由）
- Ansibleのインストール
- Ansibleコレクションのインストール

### 7. プロビジョニング

Ansibleプレイブックを実行して、アプリケーションのインストールと設定を行います。

```bash
make provision
```

## 📁 プロジェクト構造

```plaintext
mac-provisioning/
├── ansible.cfg              # Ansible設定
├── site.yml                 # メインプレイブック
├── inventory.ini            # インベントリファイル
├── requirements.yml         # Ansibleコレクション依存関係
├── Makefile                 # タスク管理
├── group_vars/
│   └── all.yml             # パッケージリストと共通変数
├── roles/
│   ├── homebrew/           # Homebrew管理ロール（macOS専用）
│   │   └── tasks/
│   │       ├── main.yml        # エントリーポイント
│   │       ├── install.yml     # インストール処理
│   │       └── upgrade.yml     # アップグレード処理
│   ├── mas/                # Mac App Store管理ロール（macOS専用）
│   │   └── tasks/
│   │       ├── main.yml        # エントリーポイント
│   │       ├── install.yml     # インストール処理
│   │       └── upgrade.yml     # アップグレード処理
│   ├── 1password/          # 1Password管理ロール（macOS専用）
│   │   └── tasks/
│   │       └── main.yml        # インストールと認証確認
│   ├── asdf/               # asdf言語バージョン管理ロール（OS共通）
│   │   └── tasks/
│   │       └── main.yml
│   └── chezmoi/            # dotfiles管理ロール（OS共通）
│       └── tasks/
│           └── main.yml
└── scripts/
    └── bootstrap.sh         # 初期セットアップスクリプト
```

## 🎯 利用可能なコマンド

### 基本コマンド

- `make help` - 利用可能なコマンドの一覧表示
- `make mac-bootstrap` - ブートストラップスクリプトの実行（asdf、Python、Ansibleをインストール）
- `make install-deps` - Ansibleコレクションのインストール
- `make provision` - Ansibleでプロビジョニング実行

### 個別ロール実行

- `make homebrew` - Homebrewパッケージのインストール
- `make mas` - Mac App Storeアプリのインストール
- `make asdf` - asdfプラグインとバージョンのインストール

### Chezmoi (dotfiles管理)

- `make chezmoi-init` - chezmoiの初期化（dotfilesリポジトリをクローン）
- `make chezmoi-apply` - dotfilesを適用（変更を反映）
- `make chezmoi-update` - dotfilesを更新（リポジトリから取得して適用）

### アップグレードコマンド

- `make upgrade` - **日常的に使用（推奨）**: Homebrew + Mac App Storeの全アップグレード
- `make upgrade-homebrew` - Homebrewパッケージのみアップグレード
- `make upgrade-mas` - Mac App Storeアプリのみアップグレード
- `make upgrade-formula` - Homebrew Formulaのみアップグレード
- `make upgrade-cask` - Homebrew Cask（通常）のみアップグレード

### その他

- `make doctor` - 必須ツールの事前チェック
- `make clean` - 一時ファイルのクリーンアップ

## 🔧 設定

### パッケージの管理

`group_vars/all.yml` でパッケージとdotfilesリポジトリを管理します：

```yaml
# Homebrewフォーミュラ（CLIツール）
brew_formula:
  - git
  - vim
  - jq

# Caskアプリケーション（通常 - 自動アップグレード対象）
brew_casks_normal:
  - visual-studio-code
  - google-chrome
  - slack

# Caskアプリケーション（sudo必要 - 手動アップグレード）
brew_casks_sudo_required:
  - docker-desktop
  - zoom

# Mac App Store アプリ
mas_apps:
  - { name: "1Password", id: 443987910 }
  - { name: "Slack", id: 803453959 }

# asdf言語バージョン管理
asdf_plugins:
  - nodejs
  - python
  - ruby

asdf_plugins_versions:
  - { name: "nodejs", version: "20.11.0" }
  - { name: "python", version: "3.12.0" }

# chezmoi dotfilesリポジトリ
chezmoi_repo_url: "https://github.com/yourusername/dotfiles.git"
```

### Caskアップグレードの仕組み

**通常Cask** (`brew_casks_normal`):

- 日常的な`make packages-upgrade`で自動アップグレード
- sudo権限不要で安全に実行可能

**sudo必要Cask** (`brew_casks_sudo_required`):

- 初回インストールは自動実行
- アップグレード時は通知のみ（手動実行が必要）
- Docker DesktopやZoomなど、対話的な操作が必要なアプリ

## 💡 使用例

### 初回セットアップ（新しいMac）

```bash
# 1. 1Passwordをインストールしてログイン
# 2. SSH認証エージェントを1Passwordに設定
export SSH_AUTH_SOCK=~/Library/Group\ Containers/2BUA8C4S2C.com.1password/t/agent.sock

# 3. Homebrewをインストールしてパスを通す
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
eval "$(/opt/homebrew/bin/brew shellenv)"  # Apple Silicon Macの場合

# 4. Gitをインストール
brew install git

# 5. リポジトリをクローン
git clone git@github.com:ryota1119/workstation-provisioning.git
cd workstation-provisioning

# 6. ブートストラップスクリプトを実行（asdf、Python、Ansibleをインストール）
make mac-bootstrap

# 7. 全てのパッケージをインストール
make provision
```

### 日常的なアップグレード（推奨）

```bash
# Homebrew + Mac App Storeを自動アップグレード
make upgrade
```

実行すると：

- ✅ Formulaパッケージがアップグレードされる
- ✅ 通常Caskアプリがアップグレードされる
- ✅ Mac App Storeアプリがアップグレードされる
- 📋 sudo必要なCaskは通知のみ（手動実行が必要）

### sudo必要なアプリの手動アップグレード

アップグレード後に通知された場合：

```bash
# 個別にアップグレード
brew upgrade --cask docker-desktop
brew upgrade --cask zoom
```

### 個別ロールの実行

```bash
# Homebrewパッケージのみ追加インストール
make homebrew

# asdfプラグインとバージョンのみ更新
make asdf

# dotfilesの展開のみ（1Password認証済みの場合）
make chezmoi
```

### 1Passwordとchezmoiの連携

chezmoiは1Passwordと連携してシークレット情報（APIキー、トークンなど）を安全に管理できます。

#### 初回セットアップ

```bash
# 1. 1Passwordアプリをインストールしてログイン（手動で実施済み）

# 2. 1Password CLIをインストール（手動）
brew install --cask 1password
brew install 1password-cli

# 3. 1Password CLIの認証確認
op account list  # 確認

# 4. group_vars/all.ymlにdotfilesリポジトリURLを設定
# chezmoi_repo_url: "https://github.com/yourusername/dotfiles.git"

# 5. chezmoiの初期化（dotfilesリポジトリをクローン）
make chezmoi-init

# 6. dotfilesを適用
make chezmoi-apply
```

#### 日常的な使い方

```bash
# dotfilesの変更を取得して適用
make chezmoi-update

# ローカルの変更のみ適用（リポジトリは更新しない）
make chezmoi-apply
```

## 📝 chezmoiによるdotfiles管理

chezmoiは複数マシン間でdotfilesを管理するためのツールです。1Passwordと連携してシークレット情報を安全に管理できます。

### chezmoiの設定

#### 1. dotfilesリポジトリの準備

GitHubなどにdotfilesリポジトリを作成し、`group_vars/all.yml`にURLを設定します：

```yaml
chezmoi_repo_url: "https://github.com/yourusername/dotfiles.git"
```

#### 2. 初期化と適用

```bash
# chezmoiをインストールして初期化
make chezmoi-init

# dotfilesを適用
make chezmoi-apply
```

### 1Passwordとの連携例

chezmoiのテンプレートファイル内で1Passwordのシークレットを参照できます：

```bash
# ~/.local/share/chezmoi/dot_gitconfig.tmpl
[user]
  name = {{ .name }}
  email = {{ .email }}
[github]
  token = {{ onepasswordRead "op://Private/GitHub/token" }}
```

### よくあるchezmoiコマンド

```bash
# 状態確認
chezmoi status

# 差分確認
chezmoi diff

# 特定ファイルの適用
chezmoi apply ~/.zshrc

# 手動での初期化（Ansible経由でない場合）
chezmoi init https://github.com/yourusername/dotfiles.git
chezmoi apply
```

## 🔍 トラブルシューティング

### Homebrewが見つからない場合

Homebrewがインストールされていない場合は、手動でインストールしてください：

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
eval "$(/opt/homebrew/bin/brew shellenv)"  # Apple Silicon Macの場合
```

### 権限エラーが発生する場合

管理者権限でターミナルを実行してください。

### 特定のアプリケーションがインストールされない場合

`group_vars/all.yml`の構文を確認し、アプリケーション名が正しいかチェックしてください。

### chezmoiでdotfilesが適用されない場合

```bash
# 1Passwordの認証状態を確認
op account list

# chezmoiの状態を確認
chezmoi status

# 詳細なログで実行
chezmoi apply -v

# 手動で適用（デバッグ用）
chezmoi apply --force
```

### 1Passwordのシークレットが取得できない場合

- 1Passwordアプリにサインインしているか確認
- 1Password CLIがインストールされているか確認（`op --version`）
- chezmoiテンプレート内のシークレット参照が正しいか確認

## 🤝 貢献

1. このリポジトリをフォーク
2. フィーチャーブランチを作成 (`git checkout -b feature/amazing-feature`)
3. 変更をコミット (`git commit -m 'Add amazing feature'`)
4. ブランチにプッシュ (`git push origin feature/amazing-feature`)
5. プルリクエストを作成

## 📄 ライセンス

このプロジェクトはMITライセンスの下で公開されています。

## 🙏 謝辞

- [Homebrew](https://brew.sh/) - macOS用パッケージマネージャー
- [Ansible](https://www.ansible.com/) - 自動化ツール
- [Brewfile](https://github.com/Homebrew/homebrew-bundle) - Homebrew依存関係管理
