# macOS Provisioning

macOS環境のセットアップと管理を自動化するAnsibleプロジェクトです。Homebrewを使用してアプリケーションのインストール、更新、管理を行います。

## 🚀 特徴

- **自動化されたセットアップ**: 新規macOS環境の初期設定を自動化
- **スマートなアップグレード**: sudo権限が必要なアプリを自動分離
- **Homebrew統合**: Formula、Cask、MASアプリを一元管理
- **1Password連携**: CLIの自動インストールと認証確認
- **dotfiles管理**: chezmoiでdotfilesを自動展開
- **Ansible**: 冪等性を保った設定管理
- **開発環境管理**: asdfで複数言語のバージョン管理
- **マルチOS対応**: macOS専用roleと共通roleを分離し、将来的なLinux対応も可能

## 📋 前提条件

- macOS 10.15以降
- 管理者権限
- インターネット接続

## 🛠️ セットアップ

### 1. リポジトリのクローン

```bash
git clone <repository-url>
cd mac-provisioning
```

### 2. 初期セットアップ

```bash
make bootstrap
```

このコマンドは以下を実行します：

- Xcode Command Line Toolsのインストール
- Homebrewのインストール
- Ansibleのインストール

### 3. Ansibleコレクションのインストール

```bash
make install-deps
```

### 4. プロビジョニング

```bash
make provision
```

Ansibleプレイブックを実行して、アプリケーションのインストールと設定を行います。

⚠️ **注意**: 初回実行時は、1Passwordのサインインが必要なため、以下の手順で実行してください：

```bash
# 1. 1Passwordまで実行（認証確認で停止）
make provision

# 2. 1Passwordアプリを起動してサインイン
# 3. サインイン確認
op account list

# 4. 再度実行（chezmoi roleが実行される）
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
- `make bootstrap` - 初期セットアップ（Xcode-CLT、Homebrew、Ansible）
- `make install-deps` - Ansibleコレクションのインストール
- `make provision` - Ansibleでプロビジョニング実行
- `make all` - bootstrap → install-deps → provision を順次実行

### 個別ロール実行

- `make homebrew` - Homebrewパッケージのインストール
- `make mas` - Mac App Storeアプリのインストール
- `make asdf` - asdfプラグインとバージョンのインストール
- `make 1password` - 1Passwordアプリ・CLIのインストールと認証確認

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
# 1. Xcode CLT、Homebrew、Ansibleをインストール
make bootstrap

# 2. Ansibleコレクションをインストール
make install-deps

# 3. 全てのパッケージをインストール
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

# 1Passwordのインストールと認証確認のみ
make 1password

# dotfilesの展開のみ（1Password認証済みの場合）
make chezmoi
```

### 1Passwordとchezmoiの連携

chezmoiは1Passwordと連携してシークレット情報（APIキー、トークンなど）を安全に管理できます。

#### 初回セットアップ

```bash
# 1. 1Passwordのインストールと認証確認
make 1password

# 認証されていない場合は停止するので、1Passwordアプリでサインイン後：
op account list  # 確認

# 2. group_vars/all.ymlにdotfilesリポジトリURLを設定
# chezmoi_repo_url: "https://github.com/yourusername/dotfiles.git"

# 3. chezmoiの初期化（dotfilesリポジトリをクローン）
make chezmoi-init

# 4. dotfilesを適用
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

```bash
make bootstrap
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
