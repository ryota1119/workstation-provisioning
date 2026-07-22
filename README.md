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

## 🔄 プロビジョニングの全体フロー

新規Macで環境を再現するまでの、実際の手順と依存関係です（前工程が後工程の前提になっています）。

```
1. 1Passwordインストール・サインイン（手動）
2. SSH認証エージェントを1Passwordに変更（手動、~/.zshrcに1行追加）
3. Homebrewインストール（手動、公式スクリプト）
4. 本リポジトリをclone
5. make all
   ├─ make mac-bootstrap   … Xcode CLT・mise・Python・Ansible導入、inventory.ini / host_vars/{ホスト名}.yml自動生成
   ├─ make install-deps    … Ansible Collectionsインストール
   └─ make provision       … site.yml --tags install を実行
        ├─ homebrew        … Formula / Cask
        ├─ mas             … Mac App Store
        ├─ mise            … 言語ランタイム
        ├─ mac-setting     … macOSシステム設定
        ├─ chezmoi-config-bootstrap … chezmoi.tomlを事前生成（1Password参照先。会社PCならhost_vars/{ホスト名}/chezmoi.local.ymlで上書き）
        ├─ workspace-base           … workspace-baseリポジトリを~/Workspaceへclone
        ├─ chezmoi-init             … dotfilesリポジトリをclone（scripts/chezmoi.sh init）
        └─ chezmoi-apply            … dotfilesを適用（scripts/chezmoi.sh apply）
6. （日常）make upgrade
        └─ site.yml --tags upgrade … homebrew/mas/workspace-baseの更新。chezmoiは含まれない（後述）
```

ポイント：

- **`chezmoi-config-bootstrap`ロールが`chezmoi-init`より先に走る**ことで、`chezmoi init`実行時の1Password参照先プロンプトが発生しない（`~/.config/chezmoi/chezmoi.toml`が事前に存在するため）。値そのものは`group_vars/all.yml`（個人用デフォルト）または`host_vars/{ホスト名}/chezmoi.local.yml`（gitignore対象、会社PC等の上書き）から来る。
- **`make upgrade`にchezmoiは含まれない。** dotfilesを最新化したい場合は個別に`make chezmoi-upgrade`を実行する（対話プロンプトの問題が解決したので再統合も検討可能）。
- **`workspace-base`ロールは`install`/`upgrade`両方に含まれる。** `~/Workspace`が既に存在する場合は`ansible.builtin.git`が検知して無変更（新規PCではclone）。ここでcloneされるのは`.claude/skills/`とCLAUDE.mdの基盤（`workspace-base`リポジトリ）のみで、`repos/`・`sandbox/`配下の個別プロジェクトや`exocortex`（Google Drive同期）はこのロールの対象外（各々を`gh`/`ghq`/`ghs`で別途復元、Google Driveは事前にサインイン・同期完了が前提）。
- 1Password自体のサインイン・アンロックと、Google Drive等の外部同期待ちは本質的に手動/時間依存のため自動化していない。

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
| `make upgrade` | Homebrew・MAS・workspaceを更新（dotfilesは含まない） | 日常 |

### 個別ロール（必要時のみ）

| コマンド | 内容 |
|---|---|
| `make homebrew` | Homebrewパッケージ（Formula + Cask）のインストール |
| `make mas` | Mac App Storeアプリのインストール |
| `make mise` | miseで言語ランタイムをインストール |
| `make chezmoi` | dotfilesの初期化・適用（updateは含まない） |
| `make chezmoi-config-bootstrap` | chezmoi.tomlの事前生成のみ（1Password対話プロンプト回避） |
| `make workspace-base` | workspace-base（`~/Workspace`）のclone/更新のみ |
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
│   ├── {ホスト名}.yml            # マシン固有設定（自動生成、フラットファイルの場合）
│   └── {ホスト名}/               # マシン固有設定（ローカル上書きが必要な場合はディレクトリ化）
│       ├── vars.yml             # 通常のマシン固有設定
│       ├── chezmoi.local.yml.example  # chezmoi_git_identity上書き用テンプレート
│       └── chezmoi.local.yml    # 実際の値（gitignore対象、会社名等を含み得るため非公開）
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
│   ├── chezmoi-config-bootstrap/
│   │   ├── tasks/
│   │   │   ├── main.yml
│   │   │   └── install.yml      # ~/.config/chezmoi/chezmoi.tomlを事前生成（既存ファイルは上書きしない）
│   │   └── templates/
│   │       └── chezmoi.toml.j2  # chezmoi_git_identity変数から生成
│   ├── workspace-base/tasks/
│   │   └── main.yml             # workspace-baseリポジトリを~/Workspaceへclone/更新
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
    ├── mac-bootstrap.sh         # 初回ブートストラップスクリプト
    └── chezmoi.sh               # chezmoiのinit/update/apply処理（ansibleロールではなくbashスクリプト）
```

chezmoi自体の`init`/`update`/`apply`はansibleのロール・タグではなく、`scripts/chezmoi.sh`（bash）が担っています。`site.yml`が担当するのは、その前段階である`chezmoi.toml`の事前生成（`chezmoi-config-bootstrap`ロール）のみです。

## 🏷️ Ansible Tagsの設計

playbook 全体は2つのトップレベルタグと、ロール個別タグで制御できます（chezmoi自体の`init`/`update`/`apply`はansibleの外・`scripts/chezmoi.sh`が担当するため、この表には含まれません）。

| タグ | Homebrew | MAS | mise | chezmoi-config-bootstrap | workspace-base | mac-setting | 用途 |
|---|---|---|---|---|---|---|---|
| `install` | install | install | install | 実行 | clone/更新 | defaults | 初回インストール（`make provision`） |
| `upgrade` | upgrade | upgrade | - | - | clone/更新 | - | 日常更新（`make upgrade`） |
| `homebrew` | install | - | - | - | - | - | Homebrewのみ |
| `mas` | - | install | - | - | - | - | MASのみ |
| `mise` | - | - | install | - | - | - | miseのみ |
| `chezmoi-config-bootstrap` | - | - | - | 実行 | - | - | chezmoi.tomlの事前生成のみ |
| `workspace-base` | - | - | - | - | clone/更新 | - | workspace-baseのclone/更新のみ |
| `mac-setting` | - | - | - | - | - | defaults | macOS設定のみ |

ポイント:

- **mise** は明示バージョンを初回のみ導入する仕様のため、`upgrade` には含まれません
- **mac-setting** は Finder/Dock の再起動が走るため、`upgrade` には含まれません
- **chezmoi-config-bootstrap** は `chezmoi.toml` を事前生成するだけで、`chezmoi init`/`apply`自体は呼びません（`force: false`のため既存ファイルは上書きしません）。`install`タグのみに含まれ、`upgrade`には含まれません
- chezmoi自体の実行（init/update/apply）は`Makefile`が`scripts/chezmoi.sh`を直接呼ぶことで行われ、`make provision`では実行されますが`make upgrade`では実行されません（後述）
- **workspace-base** は`ansible.builtin.git`で`~/Workspace`をclone/更新するのみ。`install`/`upgrade`どちらのタグにも含まれます（基盤リポジトリなので日常的にも最新化したい）

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

# chezmoiのgit identity設定（1Password参照先）。デフォルトは個人用。
# 会社PC等で別の保管庫を使う場合は host_vars/{ホスト名}/chezmoi.local.yml で上書きする。
chezmoi_git_identity:
  onepassword_username_path: "op://Personal/GitHub - ryota1119/username"
  onepassword_email_path: "op://Personal/GitHub - ryota1119/email"
  onepassword_signing_key_path: "op://Personal/id_ed25519/public_key"
```

dotfilesリポジトリ自体のURL（`git@github.com:ryota1119/dotfiles.git`）はansible変数ではなく、`scripts/chezmoi.sh`内に直接定義されています。`workspace_base_repo_url`/`workspace_dest`は`workspace-base`ロールが`~/Workspace`をclone/更新する際に使う変数です。

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

### `host_vars/{ホスト名}/chezmoi.local.yml` - 会社PC等のchezmoi上書き（gitignore対象）

会社の1Passwordアカウント名など、公開リポジトリに書けない値を使うマシンでは、`host_vars/{ホスト名}.yml` を `host_vars/{ホスト名}/` ディレクトリ化し、その中に `chezmoi.local.yml`（実ファイル、gitignore対象）を置いて `chezmoi_git_identity` を上書きします。テンプレートは同ディレクトリの `chezmoi.local.yml.example`（Git管理下）を参照してください。

```bash
cp host_vars/{ホスト名}/chezmoi.local.yml.example host_vars/{ホスト名}/chezmoi.local.yml
# 実際の値に書き換える（accountは1Passwordのサインインアドレスではなくaccount_uuidを推奨）
```

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
- 📋 sudo必要Caskは通知のみ（手動実行が必要）
- ⏭️ mise / mac-setting / chezmoi はスキップ（dotfilesを更新したい場合は`make chezmoi-upgrade`を個別に実行）

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

chezmoiは複数マシン間でdotfilesを管理するためのツールです。1Passwordと連携してシークレット情報を安全に扱えます。実体は`scripts/chezmoi.sh`（bash）で、ansibleのロールではありません。

### 動作モード

| 実行コマンド | 動作 |
|---|---|
| `make provision` | ansible（`chezmoi-config-bootstrap`ロールでchezmoi.toml事前生成）→ `chezmoi-init` → `chezmoi-apply` |
| `make upgrade` | 実行されない（homebrew/masのみ。dotfilesを更新したい場合は個別に`make chezmoi-upgrade`） |
| `make chezmoi` | `init`（未初期化時のみ）+ `apply`（updateは含まない） |
| `make chezmoi-init` | 未初期化の場合のみ`chezmoi init`（リポジトリclone） |
| `make chezmoi-upgrade` | `chezmoi update --force`（git pull相当、差分があれば適用） |
| `make chezmoi-apply` | 差分があれば`chezmoi apply` |

### 1Password対話プロンプトの回避

`.chezmoi.toml.tmpl`は`promptStringOnce`で1Passwordの参照先（アカウント・パス）を保持しますが、値が未設定だと対話入力を要求します。これが`make provision`の非対話実行を妨げていたため、`chezmoi-config-bootstrap`ロールが`chezmoi init`より先に`~/.config/chezmoi/chezmoi.toml`を`chezmoi_git_identity`変数から生成し、プロンプトを回避します（詳細は「🔄 プロビジョニングの全体フロー」参照）。

## ⚙️ 手動適用が必要なアプリ設定

`settings/` 配下のファイルは、アプリごとのエクスポート設定です。自動適用はせず、アプリ側のインポート機能から手動で取り込みます。

| ファイル | 用途 | 手動適用手順 |
|---|---|---|
| `settings/iStat Menus Settings.ismp7` | iStat Menusの表示項目・メニューバー設定 | iStat Menusを開き、設定画面のインポート機能からこのファイルを選択 |
| `settings/iTerm2 State.itermexport` | iTerm2のプロファイル・外観・キーバインド等 | iTerm2の Settings → General → Settings からインポート |
| `settings/RectangleConfig.json` | Rectangleのウィンドウ操作ショートカット | Rectangleの設定画面からImportを選び、このJSONを指定 |

### 1Password CLIとの連携

chezmoiのテンプレートファイル内で1Passwordのシークレットを参照できます（実例：`~/.local/share/chezmoi/dot_config/git/config.local.tmpl`）：

```toml
[user]
    name = {{ onepasswordRead .gitIdentity.onepasswordUsernamePath }}
    email = {{ onepasswordRead .gitIdentity.onepasswordEmailPath }}
    signingkey = {{ onepasswordRead .gitIdentity.onepasswordSigningKeyPath }}
```

`.gitIdentity.*`の値は`chezmoi init`時に`~/.config/chezmoi/chezmoi.toml`から読み込まれます（本リポジトリの`chezmoi-config-bootstrap`ロールが事前生成する値、または過去に対話入力した値）。1Passwordは複数アカウント同時サインインをしない運用のため、`onepasswordRead`にaccount引数は渡しません（そのマシンでサインインしている唯一のアカウントが自動的に使われます）。

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
