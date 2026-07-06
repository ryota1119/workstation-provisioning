# Ansible 実行フロー リファクタリング 実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ansible タグ設計の明確化・実行バイナリ変数導入・全ロールの `shell`→`command` 統一により、実行フローの意図を明確にする。

**Architecture:** 3つの独立した変更（タグ設計 / 変数導入 / モジュール統一）をファイル単位で順番に適用する。各タスク後に構文チェックで確認し、最後に `--list-tasks` でタグ動作を検証する。

**Tech Stack:** Ansible, community.general collection, Homebrew, macOS

---

### Task 1: 実行バイナリ変数を `group_vars/all.yml` に追加

**Files:**
- Modify: `group_vars/all.yml`

- [ ] **Step 1: `brew_bin`、`mas_bin`、`chezmoi_bin`、`mise_bin` 変数を追加**

`homebrew_prefix: /opt/homebrew` の直下に追加する。

```yaml
# group_vars/all.yml（変更前）
homebrew_prefix: /opt/homebrew

# Tapリポジトリ
```

```yaml
# group_vars/all.yml（変更後）
homebrew_prefix: /opt/homebrew
brew_bin: "{{ homebrew_prefix }}/bin/brew"
mas_bin: "{{ homebrew_prefix }}/bin/mas"
chezmoi_bin: "{{ homebrew_prefix }}/bin/chezmoi"
mise_bin: "{{ homebrew_prefix }}/bin/mise"

# Tapリポジトリ
```

- [ ] **Step 2: 構文チェック**

```bash
ansible-playbook --syntax-check -i inventory.ini.example site.yml
```

期待出力: `playbook: site.yml`（エラーなし）

- [ ] **Step 3: コミット**

```bash
git add group_vars/all.yml
git commit -m "実行バイナリ変数を追加"
```

---

### Task 2: `homebrew/tasks/install.yml` に `brew_bin` を適用

**Files:**
- Modify: `roles/homebrew/tasks/install.yml`

対象行: 11行目・19行目・35行目（`{{ homebrew_prefix }}/bin/brew` → `{{ brew_bin }}`）

- [ ] **Step 1: `install.yml` を書き換え**

```yaml
---
- name: Tapリポジトリを追加
  community.general.homebrew_tap:
    name: "{{ item }}"
    state: present
  loop: "{{ brew_taps | default([], true) }}"
  loop_control:
    label: "{{ item }}"

- name: Tapの信頼状態を確認
  ansible.builtin.command: "{{ brew_bin }} tap-info --json {{ item }}"
  loop: "{{ brew_taps | default([], true) }}"
  register: tap_info_results
  changed_when: false
  loop_control:
    label: "{{ item }}"

- name: Tapリポジトリを信頼
  ansible.builtin.command: "{{ brew_bin }} trust --tap {{ item.item }}"
  loop: "{{ tap_info_results.results | default([]) }}"
  when: not ((item.stdout | from_json)[0].trusted | default(true))
  changed_when: true
  loop_control:
    label: "{{ item.item }}"

- name: Formulaパッケージをインストール
  community.general.homebrew:
    name: "{{ item }}"
    state: present
  loop: "{{ (brew_formula | default([], true)) + (brew_formula_extra | default([], true)) }}"
  loop_control:
    label: "{{ item }}"

- name: インストール済みCask一覧を取得
  ansible.builtin.command: "{{ brew_bin }} list --cask"
  register: installed_casks
  changed_when: false
  failed_when: false
  when: ((brew_casks_normal | default([], true)) + (brew_casks_normal_extra | default([], true))) | length > 0

- name: Caskアプリケーション（通常）をインストール
  community.general.homebrew_cask:
    name: "{{ item }}"
    state: present
  loop: "{{ ((brew_casks_normal | default([], true)) + (brew_casks_normal_extra | default([], true))) | difference(installed_casks.stdout_lines | default([], true)) }}"
  when: ((brew_casks_normal | default([], true)) + (brew_casks_normal_extra | default([], true))) | length > 0
  register: cask_install_result
  failed_when:
    - cask_install_result is failed
    - "'already an App at' not in (cask_install_result.msg | default(''))"
  loop_control:
    label: "{{ item }}"

- name: Caskアプリケーション（sudo必要）の手動インストール案内
  ansible.builtin.debug:
    msg: |
      以下のCaskはrootパスワードが必要なため、手動インストールが必要です：
      brew install --cask {{ ((brew_casks_sudo_required | default([], true)) + (brew_casks_sudo_required_extra | default([], true))) | join(' ') }}
  when: ((brew_casks_sudo_required | default([], true)) + (brew_casks_sudo_required_extra | default([], true))) | length > 0
```

- [ ] **Step 2: 構文チェック**

```bash
ansible-playbook --syntax-check -i inventory.ini.example site.yml
```

期待出力: `playbook: site.yml`

- [ ] **Step 3: コミット**

```bash
git add roles/homebrew/tasks/install.yml
git commit -m "install.yml: brew_bin 変数を適用"
```

---

### Task 3: 全ロールに実行バイナリ変数を適用 + `shell`→`command` 統一

**Files:**
- Modify: `roles/homebrew/tasks/upgrade.yml`
- Modify: `roles/mas/tasks/upgrade.yml`
- Modify: `roles/chezmoi/tasks/main.yml`
- Modify: `roles/chezmoi/tasks/init.yml`
- Modify: `roles/chezmoi/tasks/update.yml`
- Modify: `roles/chezmoi/tasks/apply.yml`
- Modify: `roles/mise/tasks/install.yml`

対象: 各実行バイナリを対応する変数に置換し、`ansible.builtin.shell` → `ansible.builtin.command` を全ロールに適用する。`op account list` は `2>/dev/null` を除去する。

- [ ] **Step 1: 対象ファイルを書き換え**

```yaml
---
- name: 更新可能なFormulaパッケージを取得
  ansible.builtin.command: "{{ brew_bin }} outdated --formula --quiet"
  register: outdated_formulas
  changed_when: false
  failed_when: false

- name: Formulaパッケージをアップグレード
  ansible.builtin.command: "{{ brew_bin }} upgrade --formula {{ item }}"
  loop: "{{ outdated_formulas.stdout_lines | default([], true) }}"
  loop_control:
    label: "{{ item }}"
  when: (outdated_formulas.stdout_lines | default([], true)) | length > 0
  changed_when: true

- name: 更新可能なCaskパッケージを取得
  ansible.builtin.command: "{{ brew_bin }} outdated --cask --greedy --quiet"
  register: outdated_casks_all
  changed_when: false
  failed_when: false

- name: Caskパッケージのアップグレード処理
  when: (outdated_casks_all.stdout_lines | default([], true)) | length > 0
  block:
    - name: 更新可能なCaskパッケージを分類（base + extra を考慮）
      ansible.builtin.set_fact:
        casks_normal_all: "{{ (brew_casks_normal | default([], true)) + (brew_casks_normal_extra | default([], true)) }}"
        casks_sudo_all: "{{ (brew_casks_sudo_required | default([], true)) + (brew_casks_sudo_required_extra | default([], true)) }}"

    - name: 更新対象のCaskを抽出
      ansible.builtin.set_fact:
        outdated_casks_normal: "{{ outdated_casks_all.stdout_lines | select('in', casks_normal_all) | list }}"
        outdated_casks_sudo: "{{ outdated_casks_all.stdout_lines | select('in', casks_sudo_all) | list }}"

    - name: 通常のCaskパッケージをアップグレード
      ansible.builtin.command: "{{ brew_bin }} upgrade --cask {{ item }} --greedy"
      loop: "{{ outdated_casks_normal }}"
      loop_control:
        label: "{{ item }}"
      when: outdated_casks_normal | length > 0
      changed_when: true

    - name: Cask（sudo必要）の手動アップグレード案内
      ansible.builtin.debug:
        msg: |
          以下のCaskはrootパスワードが必要なため、手動アップグレードが必要です：
          brew upgrade --cask {{ outdated_casks_sudo | join(' ') }}
      when: outdated_casks_sudo | length > 0

- name: 古いバージョンのファイルを削除
  ansible.builtin.command: "{{ brew_bin }} cleanup"
  changed_when: false
```

- [ ] **Step 2: 構文チェック**

```bash
ansible-playbook --syntax-check -i inventory.ini.example site.yml
```

期待出力: `playbook: site.yml`

- [ ] **Step 3: コミット**

```bash
git add roles/homebrew/tasks/upgrade.yml roles/mas/tasks/upgrade.yml roles/chezmoi/tasks/main.yml roles/chezmoi/tasks/init.yml roles/chezmoi/tasks/update.yml roles/chezmoi/tasks/apply.yml roles/mise/tasks/install.yml
git commit -m "全ロールの shell を command に統一"
```

---

### Task 4: `homebrew/tasks/main.yml` — `brew_bin` 適用 + upgrade タグ修正

**Files:**
- Modify: `roles/homebrew/tasks/main.yml`

変更点:
- stat の path を `{{ brew_bin }}` に変更
- `import_tasks: upgrade.yml` のタグから `homebrew` を除去

- [ ] **Step 1: `main.yml` を書き換え**

```yaml
---
- name: Homebrewセットアップ
  tags:
    - install
    - upgrade
    - homebrew
  block:
    - name: Homebrewがインストールされているか確認
      ansible.builtin.stat:
        path: "{{ brew_bin }}"
      register: brew_stat

    - name: Homebrewが見つからない場合は処理を中断
      ansible.builtin.fail:
        msg: "Homebrewがインストールされていません。`make mac-bootstrap` を実行してください。"
      when: not brew_stat.stat.exists

    - name: Homebrewを最新版に更新
      community.general.homebrew:
        update_homebrew: true

- name: Homebrewパッケージインストール処理
  ansible.builtin.import_tasks: install.yml
  tags:
    - install
    - homebrew

- name: Homebrewパッケージアップグレード処理
  ansible.builtin.import_tasks: upgrade.yml
  tags:
    - upgrade
```

- [ ] **Step 2: 構文チェック**

```bash
ansible-playbook --syntax-check -i inventory.ini.example site.yml
```

期待出力: `playbook: site.yml`

- [ ] **Step 3: `homebrew` タグが install のみを実行することを確認**

```bash
ansible-playbook site.yml --tags homebrew --list-tasks -i inventory.ini.example
```

期待出力: `install.yml` のタスクのみ列挙される（`upgrade.yml` のタスクは出ない）

- [ ] **Step 4: コミット**

```bash
git add roles/homebrew/tasks/main.yml
git commit -m "homebrew/main.yml: brew_bin 適用、upgrade タグを install のみに限定"
```

---

### Task 5: `mas/tasks/main.yml` — upgrade タグ修正

**Files:**
- Modify: `roles/mas/tasks/main.yml`

変更点: `import_tasks: upgrade.yml` のタグから `mas` を除去

- [ ] **Step 1: `main.yml` を書き換え**

```yaml
---
- name: MASセットアップ
  tags:
    - install
    - upgrade
    - mas
  when: enable_mas | default(true)
  block:
    - name: MASがインストールされているか確認
      ansible.builtin.stat:
        path: "{{ homebrew_prefix }}/bin/mas"
      register: mas_stat

    - name: MASが見つからない場合は処理を中断
      ansible.builtin.fail:
        msg: "MASがインストールされていません。`brew install mas` を実行してください。"
      when: not mas_stat.stat.exists

    - name: App Storeへのログイン状態を確認
      ansible.builtin.command: "{{ homebrew_prefix }}/bin/mas list"
      register: mas_list_result
      changed_when: false
      failed_when: false

    - name: App Store未ログインの警告
      ansible.builtin.debug:
        msg: |
          ⚠️  App Storeにログインしていません。
          App Storeアプリから手動でログインしてください。
      when: mas_list_result.rc != 0

- name: Mac App Storeアプリのインストール
  ansible.builtin.import_tasks: install.yml
  when: enable_mas | default(true)
  tags:
    - install
    - mas

- name: Mac App Storeアプリのアップグレード
  ansible.builtin.import_tasks: upgrade.yml
  when: enable_mas | default(true)
  tags:
    - upgrade
```

- [ ] **Step 2: 構文チェック**

```bash
ansible-playbook --syntax-check -i inventory.ini.example site.yml
```

期待出力: `playbook: site.yml`

- [ ] **Step 3: `mas` タグが install のみを実行することを確認**

```bash
ansible-playbook site.yml --tags mas --list-tasks -i inventory.ini.example
```

期待出力: `install.yml` のタスクのみ列挙される（`upgrade.yml` のタスクは出ない）

- [ ] **Step 4: コミット**

```bash
git add roles/mas/tasks/main.yml
git commit -m "mas/main.yml: upgrade タグを install のみに限定"
```

---

### Task 6: `chezmoi/tasks/main.yml` — update タグ修正

**Files:**
- Modify: `roles/chezmoi/tasks/main.yml`

変更点: `import_tasks: update.yml` のタグから `chezmoi` を除去し、`op account list` をリダイレクトなしの `command` に変更

- [ ] **Step 1: `main.yml` を書き換え**

```yaml
---
- name: chezmoiセットアップ
  tags:
    - install
    - upgrade
    - chezmoi
  block:
    - name: chezmoiをインストール
      ansible.builtin.package:
        name: chezmoi
        state: present

    - name: 1Password CLIの認証状態を確認
      ansible.builtin.command: op account list
      register: op_auth_status
      changed_when: false
      failed_when: false

    - name: 1Password未サインイン時は警告
      ansible.builtin.debug:
        msg: |
          ⚠️  1Passwordにサインインしていません。
          dotfilesのシークレット情報が取得できないため、chezmoi update/applyはスキップされます。

          手動で認証してから実行する場合：
          $ op signin
          $ chezmoi update --force
      when: op_auth_status.rc != 0

    - name: dotfilesリポジトリの存在確認
      ansible.builtin.stat:
        path: ~/.local/share/chezmoi/.git
      register: chezmoi_repo

- name: dotfilesの初期化
  ansible.builtin.import_tasks: init.yml
  tags:
    - install
    - chezmoi

- name: dotfilesの更新（git pull）
  ansible.builtin.import_tasks: update.yml
  tags:
    - upgrade

- name: dotfilesの適用
  ansible.builtin.import_tasks: apply.yml
  tags:
    - install
    - upgrade
    - chezmoi
```

- [ ] **Step 2: 構文チェック**

```bash
ansible-playbook --syntax-check -i inventory.ini.example site.yml
```

期待出力: `playbook: site.yml`

- [ ] **Step 3: `chezmoi` タグが init + apply のみを実行することを確認**

```bash
ansible-playbook site.yml --tags chezmoi --list-tasks -i inventory.ini.example
```

期待出力: `init.yml` と `apply.yml` のタスクのみ列挙される（`update.yml` のタスクは出ない）

- [ ] **Step 4: コミット**

```bash
git add roles/chezmoi/tasks/main.yml
git commit -m "chezmoi/main.yml: update タグを upgrade のみに限定"
```

---

### Task 7: 最終検証・PR 作成

**Files:** なし（検証のみ）

- [ ] **Step 1: 全タグの動作を一括検証**

```bash
# install タグ: 全ロールの install が走ること
ansible-playbook site.yml --tags install --list-tasks -i inventory.ini.example

# upgrade タグ: homebrew/mas/chezmoi の upgrade が走ること
ansible-playbook site.yml --tags upgrade --list-tasks -i inventory.ini.example

# homebrew タグ: install.yml のみ（upgrade.yml は含まない）
ansible-playbook site.yml --tags homebrew --list-tasks -i inventory.ini.example

# mas タグ: install.yml のみ
ansible-playbook site.yml --tags mas --list-tasks -i inventory.ini.example

# chezmoi タグ: init.yml + apply.yml のみ（update.yml は含まない）
ansible-playbook site.yml --tags chezmoi --list-tasks -i inventory.ini.example
```

- [ ] **Step 2: PR 作成**

```bash
git push -u origin <branch-name>
gh pr create --title "Ansible 実行フロー リファクタリング（タグ設計・実行バイナリ変数・shell統一）" --body "$(cat <<'EOF'
## Summary

- **タグ設計の明確化**: 個別ロールタグ（homebrew / mas / chezmoi）を install 操作のみに限定。upgrade は --tags upgrade 経由のみで実行されるよう変更
- **実行バイナリ変数の導入**: group_vars/all.yml に brew_bin / mas_bin / chezmoi_bin / mise_bin を定義し、各ファイルに散在していた実行パスを一元化
- **shell → command 統一**: homebrew / mas / chezmoi / mise のシェル機能が不要なコマンドを ansible.builtin.command に統一し、op account list の 2>/dev/null を除去

## Test plan

- [ ] make check（ansible-playbook --syntax-check）が通ること
- [ ] --tags homebrew --list-tasks で upgrade.yml のタスクが含まれないこと
- [ ] --tags mas --list-tasks で upgrade.yml のタスクが含まれないこと
- [ ] --tags chezmoi --list-tasks で update.yml のタスクが含まれないこと
- [ ] --tags install / --tags upgrade でそれぞれ期待するタスクセットが実行されること

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```
