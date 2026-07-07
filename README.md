# macOS Provisioning

macOS環境のセットアップと管理を自動化するAnsibleプロジェクトです。Homebrew・Mac App Store・mise・chezmoiを統合的に管理します。

## 🚀 特徴

- **2コマンド運用**: 初回は `make provision`、日常は `make upgrade` の2つで完結
- **マシン固有設定**: `host_vars/{ホスト名}.yml` で機種ごとに追加パッケージを管理
- **冪等性**: 何度実行しても同じ結果になる（既にインストール済みは自動スキップ）
- **sudo必要なCaskの分離**: 対話的な操作が必要なアプリは手動インストール案内のみ表示
- **dotfiles管理**: chezmoiで複数マシン間のdotfilesを同期
- **1Password連携**: SSH認証エージェント・シークレット管理に1Passwordを使用
- **mise統合**: 言語ランタイムのバージョン管理

## 📋 前提条件

- macOS（Apple Silicon）
- 管理者権限
- インターネット接続
- 1Passwordアプリ（手動インストール・サインイン済み）
- Homebrew（手動インストール済み）
- Git（Homebrewでインストール済み）

## 🛠️ 初回セットアップ

### 1. 1Passwordのインストールとログイン

App Storeまたは[公式サイト](https://1password.com/downloads/mac/)からインストールし、サインインしておいてください。

### 2. SSH認証エージェントを1Passwordに変更

1Password → 設定 → 開発者 → 「sshエージェントを使用」にチェック。

`~/.zshrc` などに以下を追加：

```bash
export SSH_AUTH_SOCK=~/Library/Group\ Containers/2BUA8C4S2C.com.1password/t/agent.sock
```

### 3. Homebrewのインストール

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
eval "$(/opt/homebrew/bin/brew shellenv)"
```

### 4. Gitとリポジトリのクローン

```bash
brew install git
git clone git@github.com:ryota1119/workstation-provisioning.git
cd workstation-provisioning
```

### 5. ブートストラップ + プロビジョニング

```bash
make all
```

`make all` は以下を順に実行します：

1. `make mac-bootstrap` - Xcode CLT・mise・Python・Ansibleの導入と `inventory.ini` / `host_vars/{ホスト名}.yml` の自動生成
2. `make install-deps` - Ansible Collectionsのインストール
3. `make provision` - 全ロールを一括インストール

## 🎯 利用可能なコマンド

### 主要コマンド（よく使う）

| コマンド | 用途 | 実行頻度 |
|---|---|---|
| `make all` | 新規PC初回セットアップ（bootstrap + deps + provision） | 初回のみ |
| `make provision` | 全ロールを一括インストール | 稀 |
| `make upgrade` | パッケージとdotfilesを一括更新 | 日常 |

### 個別ロール（必要時のみ）

| コマンド | 内容 |
|---|---|
| `make homebrew` | Homebrewパッケージ（Formula + Cask）のインストール |
| `make mas` | Mac App Storeアプリのインストール |
| `make mise` | miseで言語ランタイムをインストール |
| `make chezmoi` | dotfilesの初期化・適用（updateは含まない） |
| `make mac-setting` | macOSシステム設定の適用 |

### ブートストラップ・ユーティリティ

| コマンド | 内容 |
|---|---|
| `make mac-bootstrap` | Xcode CLT・Ansible等の導入（初回のみ） |
| `make install-deps` | Ansible Collectionsのインストール |
| `make doctor` | 必須ツールの事前チェック |
| `make check` | Ansible構文チェック |
| `make clean` | 一時ファイルのクリーンアップ |

## 📁 プロジェクト構造

```plaintext
workstation-provisioning/
├── ansible.cfg                  # Ansible設定
├── site.yml                     # メインプレイブック
├── inventory.ini                # インベントリ（mac-bootstrap.shが自動生成、Git管理外）
├── inventory.ini.example        # インベントリのテンプレート
├── requirements.yml             # Ansibleコレクション依存関係
├── Makefile                     # タスク管理
├── group_vars/
│   └── all.yml                  # 全マシン共通の設定とパッケージリスト
├── host_vars/
│   ├── _template.yml            # マシン固有設定のテンプレート
│   └── {ホスト名}.yml            # マシン固有設定（自動生成）
├── roles/
│   ├── homebrew/tasks/
│   │   ├── main.yml             # エントリーポイント
│   │   ├── install.yml          # インストール処理
│   │   └── upgrade.yml          # アップグレード処理
│   ├── mas/tasks/
│   │   ├── main.yml
│   │   ├── install.yml
│   │   └── upgrade.yml
│   ├── mise/tasks/
│   │   ├── main.yml
│   │   └── install.yml          # 初回のみインストール（upgradeなし）
│   ├── chezmoi/tasks/
│   │   ├── main.yml
│   │   ├── init.yml             # リポジトリ初期化（初回のみ）
│   │   ├── update.yml           # git pull相当（chezmoi update）
│   │   └── apply.yml            # ローカル適用（chezmoi apply）
│   └── mac-setting/
│       ├── tasks/
│       │   ├── main.yml
│       │   └── defaults.yml     # macOSシステム設定
│       └── handlers/
│           └── main.yml         # 設定変更時だけ関連プロセスを再起動
├── settings/
│   ├── iStat Menus Settings.ismp7
│   ├── iTerm2 State.itermexport
│   └── RectangleConfig.json
└── scripts/
    └── mac-bootstrap.sh         # 初回ブートストラップスクリプト
```

## 🏷️ Ansible Tagsの設計

playbook 全体は2つのトップレベルタグと、ロール個別タグで制御できます。

| タグ | Homebrew | MAS | mise | chezmoi | mac-setting | 用途 |
|---|---|---|---|---|---|---|
| `install` | install | install | install | init + apply | defaults | 初回インストール（`make provision`） |
| `upgrade` | upgrade | upgrade | - | update + apply | - | 日常更新（`make upgrade`） |
| `homebrew` | install | - | - | - | - | Homebrewのみ |
| `mas` | - | install | - | - | - | MASのみ |
| `mise` | - | - | install | - | - | miseのみ |
| `chezmoi` | - | - | - | init + apply | - | chezmoiのみ。updateは実行しない |
| `mac-setting` | - | - | - | - | defaults | macOS設定のみ |

ポイント:

- **mise** は明示バージョンを初回のみ導入する仕様のため、`upgrade` には含まれません
- **mac-setting** は Finder/Dock の再起動が走るため、`upgrade` には含まれません
- **chezmoi** は `install` 時は init+apply、`upgrade` 時は update+apply です。個別の `chezmoi` タグでは update は実行されません

## 🔧 設定ファイル

### `group_vars/all.yml` - 全マシン共通

すべてのマシンで共通で使うパッケージや設定を記述します。

```yaml
# Homebrew Formula（CLIツール）
brew_formula:
  - git
  - jq
  - mise
  ...

# Cask（通常 - 自動アップグレード対象）
brew_casks_normal:
  - 1password
  - cursor
  - google-chrome
  ...

# Cask（sudo必要 - 手動インストール案内）
brew_casks_sudo_required:
  - docker-desktop
  - zoom
  ...

# Mac App Store アプリ
mas_apps:
  - { name: "1Password for Safari", id: 1569813296 }
  ...

# miseで管理する言語ランタイム
mise_tools_versions:
  - { name: "node", version: "24.3.0" }
  ...

# Mac App Store アプリのインストール（host_varsで上書き可能）
enable_mas: true

# dotfilesリポジトリ
chezmoi_repo_url: "git@github.com:ryota1119/dotfiles.git"
```

### `host_vars/{ホスト名}.yml` - マシン固有

各マシン固有の追加設定を記述します。`mac-bootstrap.sh` 実行時に `_template.yml` から自動生成されます。

```yaml
# Mac App Storeを無効化（仕事用Macなど）
enable_mas: false

# このマシンにだけ追加するFormula
brew_formula_extra:
  - some-cli-tool

# このマシンにだけ追加するCask
brew_casks_normal_extra:
  - chatwork
  - readdle-spark

# このマシンにだけ追加するCask（sudo必要）
brew_casks_sudo_required_extra:
  - nordvpn
```

`group_vars/all.yml` の `brew_formula` などの共通リストと、`host_vars/{ホスト名}.yml` の `brew_formula_extra` などのマシン固有リストは**結合された上で**インストールされます。

## 💡 利用シーン

### 新規Macのセットアップ

```bash
# 前提（手動）: 1Password、Homebrew、Gitを導入

git clone git@github.com:ryota1119/workstation-provisioning.git
cd workstation-provisioning
make all
```

### 日常的なアップグレード

```bash
make upgrade
```

実行内容：

- ✅ Homebrew Formulaのアップグレード
- ✅ 通常Caskアプリのアップグレード
- ✅ Mac App Storeアプリのアップグレード
- ✅ chezmoi: dotfilesの更新（`chezmoi update --force`）+ 適用（`chezmoi apply`）
- 📋 sudo必要Caskは通知のみ（手動実行が必要）
- ⏭️ mise / mac-setting はスキップ

### sudo必要なCaskを手動アップグレード

`make upgrade` 後にコンソールに表示されるコマンドを実行：

```bash
brew upgrade --cask docker-desktop zoom
```

### マシンに新しいアプリを追加

```bash
# host_vars/{ホスト名}.yml に追加
brew_casks_normal_extra:
  - new-app

# 反映
make homebrew
```

## 📝 chezmoi（dotfiles管理）

chezmoiは複数マシン間でdotfilesを管理するためのツールです。1Passwordと連携してシークレット情報を安全に扱えます。

### 動作モード

| 実行コマンド | 動作 |
|---|---|
| `make provision`（install タグ） | `init`（リポジトリclone）+ `apply`（ローカル適用） |
| `make upgrade`（upgrade タグ） | `update`（git pull）+ `apply`（ローカル適用） |
| `make chezmoi` | `init`（未初期化時のみ）+ `apply`（updateは含まない） |

## ⚙️ 手動適用が必要なアプリ設定

`settings/` 配下のファイルは、アプリごとのエクスポート設定です。自動適用はせず、アプリ側のインポート機能から手動で取り込みます。

| ファイル | 用途 | 手動適用手順 |
|---|---|---|
| `settings/iStat Menus Settings.ismp7` | iStat Menusの表示項目・メニューバー設定 | iStat Menusを開き、設定画面のインポート機能からこのファイルを選択 |
| `settings/iTerm2 State.itermexport` | iTerm2のプロファイル・外観・キーバインド等 | iTerm2の Settings → General → Settings からインポート |
| `settings/RectangleConfig.json` | Rectangleのウィンドウ操作ショートカット | Rectangleの設定画面からImportを選び、このJSONを指定 |

### 1Password CLIとの連携

chezmoiのテンプレートファイル内で1Passwordのシークレットを参照できます：

```bash
# ~/.local/share/chezmoi/dot_gitconfig.tmpl
[user]
  name = {{ .name }}
  email = {{ .email }}
[github]
  token = {{ onepasswordRead "op://Private/GitHub/token" }}
```

1Password CLIが未認証の場合、`update` / `apply` は**自動的にスキップ**されて警告が表示されます。

### よく使うchezmoiコマンド

```bash
chezmoi status              # 状態確認
chezmoi diff                # 差分確認
chezmoi apply               # ローカルに適用
chezmoi update --force      # git pull + apply
```

## 🔍 トラブルシューティング

### Homebrewが見つからない場合

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
eval "$(/opt/homebrew/bin/brew shellenv)"
```

### 「It seems there is already an App at」エラーが出る場合

すでにApp Storeなどから手動インストール済みのアプリが存在する場合、本プロジェクトでは自動的にスキップして処理を続行します。問題ありません。

### chezmoiでdotfilesが適用されない場合

```bash
# 1Passwordの認証状態を確認
op account list

# サインインし直す
op signin

# 手動で更新
chezmoi update --force
```

### `host_vars/{ホスト名}.yml` が存在しないと言われる場合

`make mac-bootstrap` を実行すると、ホスト名（`scutil --get LocalHostName`）から自動生成されます。

## 🤝 貢献

1. このリポジトリをフォーク
2. フィーチャーブランチを作成
3. 変更をコミット
4. プルリクエストを作成

## 📄 ライセンス

このプロジェクトはMITライセンスの下で公開されています。
