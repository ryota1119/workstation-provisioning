# Ansible 実行フロー リファクタリング設計

## 背景

現状の Ansible プレイブックは以下の問題を抱えている：

1. 個別ロールタグ（`homebrew`, `mas`, `chezmoi`）が install と upgrade の両方を起動する
2. `{{ homebrew_prefix }}/bin/brew` というパスが10箇所以上に散在している
3. 全ロールで `shell` と `command` モジュールが混在している

## スコープ外

- Darwin ガード（`when: ansible_os_family == 'Darwin'`）の追加・変更
  - `mise` と `chezmoi` は将来のクロスプラットフォーム対応のため Darwin ガードなしを維持
  - `homebrew`, `mas`, `mac-setting` は現状のガードを維持

---

## 変更1: タグ設計の再定義

### 問題

`make homebrew` を実行すると `--tags homebrew` で `install.yml` と `upgrade.yml` の両方が走る。
個別ロールタグが「完全メンテナンス」として機能してしまい、意図が不明確。

### 設計

個別ロールタグは install 操作のみに限定する。upgrade は `--tags upgrade` 経由のみで実行。

#### 変更後のタグマトリクス

| タグ | homebrew/setup | homebrew/install | homebrew/upgrade | mas/install | mas/upgrade | chezmoi/setup | chezmoi/init | chezmoi/update | chezmoi/apply |
|------|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|
| `install` | ✅ | ✅ | | ✅ | | ✅ | ✅ | | ✅ |
| `upgrade` | ✅ | | ✅ | | ✅ | ✅ | | ✅ | ✅ |
| `homebrew` | ✅ | ✅ | | | | | | | |
| `mas` | | | | ✅ | | | | | |
| `chezmoi` | | | | | | ✅ | ✅ | | ✅ |

#### 変更箇所

**`homebrew/tasks/main.yml`:**
```yaml
# 変更前
- import_tasks: upgrade.yml
  tags: [upgrade, homebrew]

# 変更後
- import_tasks: upgrade.yml
  tags: [upgrade]
```

**`mas/tasks/main.yml`:**
```yaml
# 変更前
- import_tasks: upgrade.yml
  tags: [upgrade, mas]

# 変更後
- import_tasks: upgrade.yml
  tags: [upgrade]
```

**`chezmoi/tasks/main.yml`:**
```yaml
# 変更前
- import_tasks: update.yml
  tags: [upgrade, chezmoi]

# 変更後
- import_tasks: update.yml
  tags: [upgrade]
```

#### make ターゲットの動作（変更後）

| コマンド | 実行内容 |
|---------|---------|
| `make provision` | 全ロール install |
| `make upgrade` | homebrew/mas/chezmoi upgrade |
| `make homebrew` | homebrew install のみ |
| `make mas` | mas install のみ |
| `make chezmoi` | chezmoi init + apply のみ |
| `make mise` | mise install のみ（変更なし） |
| `make mac-setting` | mac-setting install のみ（変更なし） |

---

## 変更2: `brew_bin` 変数の導入

### 問題

`{{ homebrew_prefix }}/bin/brew` が以下のファイルに散在している：
- `homebrew/tasks/main.yml`（2箇所）
- `homebrew/tasks/install.yml`（2箇所）
- `homebrew/tasks/upgrade.yml`（5箇所）
- `mas/tasks/main.yml`（1箇所）

### 設計

`group_vars/all.yml` に `brew_bin` に加えて `mas_bin`、`chezmoi_bin`、`mise_bin` を追加し、全箇所を置換する。

```yaml
# group_vars/all.yml に追加
brew_bin: "{{ homebrew_prefix }}/bin/brew"
mas_bin: "{{ homebrew_prefix }}/bin/mas"
chezmoi_bin: "{{ homebrew_prefix }}/bin/chezmoi"
mise_bin: "{{ homebrew_prefix }}/bin/mise"
```

使用例：
```yaml
# 変更前
ansible.builtin.command: "{{ homebrew_prefix }}/bin/brew upgrade --formula {{ item }}"

# 変更後
ansible.builtin.command: "{{ brew_bin }} upgrade --formula {{ item }}"
```

---

## 変更3: `shell` → `command` モジュール統一

### 問題

`homebrew/tasks/upgrade.yml` だけでなく、`mas`、`chezmoi`、`mise` ロールでも
パイプ・リダイレクト・変数展開が不要なコマンドに `ansible.builtin.shell` を使っているため、`command` に統一する。

`ansible.builtin.shell` はシェル展開のオーバーヘッドがあり、セキュリティリスクも高い。

### 設計

```yaml
# 変更前
- name: 更新可能なFormulaパッケージを取得
  ansible.builtin.shell: "{{ brew_bin }} outdated --formula --quiet"

- name: 更新可能なCaskパッケージを取得
  ansible.builtin.shell: "{{ brew_bin }} outdated --cask --greedy --quiet"

# 変更後
- name: 更新可能なFormulaパッケージを取得
  ansible.builtin.command: "{{ brew_bin }} outdated --formula --quiet"

- name: 更新可能なCaskパッケージを取得
  ansible.builtin.command: "{{ brew_bin }} outdated --cask --greedy --quiet"
```

`chezmoi/tasks/main.yml` の `op account list` は `2>/dev/null` を除去し、`ansible.builtin.command` に統一する。

---

## 変更対象ファイル一覧

| ファイル | 変更1（タグ） | 変更2（実行バイナリ変数） | 変更3（shell） |
|---------|:-----------:|:----------------:|:-------------:|
| `group_vars/all.yml` | | ✅ 追加 | |
| `homebrew/tasks/main.yml` | | ✅ | |
| `homebrew/tasks/install.yml` | | ✅ | |
| `homebrew/tasks/upgrade.yml` | | ✅ | ✅ |
| `mas/tasks/main.yml` | ✅ | ✅ | |
| `mas/tasks/upgrade.yml` | | ✅ | ✅ |
| `chezmoi/tasks/main.yml` | ✅ | | ✅ |
| `chezmoi/tasks/init.yml` | | ✅ | ✅ |
| `chezmoi/tasks/update.yml` | | ✅ | ✅ |
| `chezmoi/tasks/apply.yml` | | ✅ | ✅ |
| `mise/tasks/install.yml` | | ✅ | ✅ |

---

## テスト方針

- `ansible-playbook --syntax-check` で構文確認
- `make check` が通ること
- 各 `make` ターゲットの `--list-tasks` で期待するタスクのみが列挙されること
  ```bash
  ansible-playbook site.yml --tags homebrew --list-tasks
  # → install.yml のタスクのみが表示される（upgrade.yml は表示されない）
  ```
