# `make upgrade` 通知の再設計 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** launchd から実行される `make upgrade` の結果通知を、LLM 要約から決定的なログパースに置き換え、通知クリックで全文サマリを開けるようにする。

**Architecture:** パース処理を `scripts/upgrade-summary.sh` として独立させ、ログファイルを引数に取ってサマリを標準出力する。`scripts/upgrade-scheduled.sh` は「make upgrade を実行 → サマリ生成 → 通知判定 → 通知」のオーケストレーションに専念する。パーサが独立していることで、実際に `make upgrade` を走らせずに `logs/` の既存ログで検証できる。

**Tech Stack:** zsh, awk, terminal-notifier (Homebrew Formula), Ansible

## Global Constraints

- 仕様書: `docs/superpowers/specs/2026-08-12-upgrade-notification-design.md`
- スクリプトは zsh（既存の `upgrade-scheduled.sh` に合わせる）。`set -u` を維持する。
- sudo は一切使わない。
- Ansible ロール（`roles/`）には変更を加えない。
- ログのパースアンカーとなるタスク名・メッセージ文言は、`upgrade-summary.sh` 冒頭に定数として集約する。ロール側とのリネーム結合を1箇所に閉じ込めるため。
- 出力・コメントは日本語。番号付けに丸文字（①②③）を使わない。
- サマリファイルの固定パスは `logs/latest-summary.txt`（`.md` ではない）。
- 既存ログの間引き（`KEEP_LOGS=20`、`upgrade-*.log` グロブ）の挙動は変えない。

---

## File Structure

| ファイル | 責務 |
|---|---|
| `scripts/upgrade-summary.sh` | **新規。** ログ1本を読み、全文サマリまたは通知本文を stdout に出す。副作用なし。 |
| `scripts/upgrade-scheduled.sh` | **改修。** make 実行、サマリのファイル書き出し、通知判定、通知発行、ログ間引き。 |
| `tests/fixtures/upgrade-manual-cases.log` | **新規。** 既存ログに現れない「権限エラー Cask」「MAS 要対応」を含む合成ログ。 |
| `group_vars/all.yml` | `brew_formula` に `terminal-notifier` を追加。 |
| `CLAUDE.md` | 「Scheduled `make upgrade` (launchd)」節の記述を更新。 |

このリポジトリには現在テストディレクトリが存在しない。`tests/fixtures/` を新設するのは、
既存ログでカバーできないケース（権限エラー Cask・MAS 要対応）を検証するために必要なため。
最小限（合成ログ1本）に留める。

---

### Task 1: パーサの骨格と更新パッケージの抽出

ログを `KEY<TAB>VALUE` 形式の中間表現に変換する awk を書き、Formula / Cask の更新を抽出する。
中間表現を挟むのは、全文サマリと通知本文の2つのレンダラで同じパース結果を共有するため。

**Files:**
- Create: `scripts/upgrade-summary.sh`
- Test: 既存ログ `logs/upgrade-20260811-102156.log`、`logs/upgrade-20260810-170703.log`、`logs/upgrade-20260812-100703.log`

**Interfaces:**
- Produces:
  - `scripts/upgrade-summary.sh --dump <logfile>` → 中間表現を stdout に出力、exit 0
  - 中間表現のキー: `STARTED` / `FINISHED` / `STATUS` / `FORMULA` / `CASK`
  - （`--dump` は Task 2 以降でも回帰確認に使う。最終成果物にも残す。）

- [ ] **Step 1: スクリプトを作成する**

`scripts/upgrade-summary.sh`:

```bash
#!/bin/zsh
# make upgrade の実行ログを解析して、サマリまたは通知本文を標準出力に出す。
# 副作用を持たない（ファイルを書かない・通知を出さない）ため、
# logs/ の既存ログを引数に渡すだけで単体検証できる。
#
#   upgrade-summary.sh <logfile>           全文サマリを出力
#   upgrade-summary.sh --dump <logfile>    パース結果の中間表現を出力（デバッグ用）
set -u

# ------------------------------------------------------------
# パースのアンカー。
# roles/ 側のタスク名・メッセージ文言に依存するため、ここに集約する。
# ロールをリネームした場合はここだけを直せばよい。
# ------------------------------------------------------------
TASK_FORMULA='Formulaパッケージをアップグレード'
TASK_CASK='通常のCaskパッケージをアップグレード'
TASK_CASK_REINSTALL='強制再インストール'

usage() {
  echo "usage: ${0:t} [--dump] <logfile>" >&2
  exit 64
}

MODE="summary"
if [ "${1:-}" = "--dump" ]; then
  MODE="dump"
  shift
fi
[ $# -eq 1 ] || usage
LOG_FILE="$1"
[ -r "$LOG_FILE" ] || { echo "${0:t}: ログを読めません: $LOG_FILE" >&2; exit 66; }

# ------------------------------------------------------------
# ログ → 中間表現（KEY<TAB>VALUE）
# ------------------------------------------------------------
parse_log() {
  awk -v t_formula="$TASK_FORMULA" \
      -v t_cask="$TASK_CASK" \
      -v t_cask_re="$TASK_CASK_REINSTALL" '
    function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }

    /^=== make upgrade started: / {
      s = $0; sub(/^=== make upgrade started: /, "", s); sub(/ ===$/, "", s)
      print "STARTED\t" s; next
    }
    /^=== make upgrade finished: / {
      s = $0; sub(/^=== make upgrade finished: /, "", s); sub(/ ===$/, "", s)
      print "FINISHED\t" s; next
    }
    /^=== exit status: / {
      s = $0; sub(/^=== exit status: /, "", s); sub(/ ===$/, "", s)
      print "STATUS\t" s; next
    }

    /^TASK \[/ {
      task = $0
      sub(/^TASK \[/, "", task); sub(/\].*$/, "", task)
      mode = ""
      if (index(task, t_formula))      mode = "FORMULA"
      else if (index(task, t_cask))    mode = "CASK"
      else if (index(task, t_cask_re)) mode = "CASK"
      next
    }

    # changed: [host] => (item=NAME)
    # failed: 行は数えない（再インストールタスクで復旧した分は
    # そのタスクの changed: 行として別途カウントされる）
    mode != "" && /^changed: .*\(item=/ {
      s = $0; sub(/^.*\(item=/, "", s); sub(/\).*$/, "", s)
      print mode "\t" trim(s); next
    }
  ' "$LOG_FILE"
}

if [ "$MODE" = "dump" ]; then
  parse_log
  exit 0
fi

# 全文サマリの描画は Task 2 以降で実装する
parse_log
```

- [ ] **Step 2: 実行権限を付けて、更新のあるログで検証する**

```bash
chmod +x scripts/upgrade-summary.sh
./scripts/upgrade-summary.sh --dump logs/upgrade-20260811-102156.log
```

期待する出力（順不同ではなくこの順序）:

```
STARTED	2026-08-11 10:21:56
FORMULA	awscli
FORMULA	ollama
CASK	notion
CASK	slack
STATUS	<ログ末尾の値>
```

`failed: [host] (item=chatgpt)` などの行が `CASK` として出ていないことを確認する。

- [ ] **Step 3: 更新1件のみのログで検証する**

```bash
./scripts/upgrade-summary.sh --dump logs/upgrade-20260810-170703.log
```

期待: `CASK	codexbar` が1行だけ出る。`FORMULA` 行は出ない。

- [ ] **Step 4: 更新0件・失敗ログで検証する**

```bash
./scripts/upgrade-summary.sh --dump logs/upgrade-20260812-100703.log
```

期待: `STARTED` と `STATUS	2` のみ。`FORMULA` / `CASK` 行は1つも出ない。

- [ ] **Step 5: コミット**

```bash
git add scripts/upgrade-summary.sh
git commit -m "upgrade通知: ログパーサの骨格と更新パッケージ抽出を追加"
```

---

### Task 2: 要手動対応とエラーの抽出

`debug` タスクの固定文言をアンカーに、sudo 必要 Cask・権限エラー Cask・MAS 要対応を抽出する。
あわせて `fatal:` からエラーを抽出する。

**Files:**
- Modify: `scripts/upgrade-summary.sh`
- Create: `tests/fixtures/upgrade-manual-cases.log`

**Interfaces:**
- Consumes: Task 1 の `parse_log` と `--dump`
- Produces: 中間表現に `SUDO_CASK` / `PERM_CASK` / `MAS` / `ERROR` / `ERROR_DETAIL` を追加

- [ ] **Step 1: 合成ログのフィクスチャを作る**

既存ログには「権限エラー Cask」「MAS 要対応」が現れないため、
ロールの `debug` 文言（`roles/homebrew/tasks/upgrade.yml`、`roles/mas/tasks/upgrade.yml`）
どおりの合成ログを用意する。MAS の行は実際の `mas outdated` の出力書式に合わせている。

`tests/fixtures/upgrade-manual-cases.log`:

```
=== make upgrade started: 2026-08-12 09:00:00 ===
Upgrading packages...

PLAY [環境プロビジョニング] ****************************************************

TASK [homebrew : Formulaパッケージをアップグレード] ****************************
changed: [testhost] => (item=jq)

TASK [homebrew : 権限エラーで再インストールできなかったCaskの案内] *************
ok: [testhost] => (item=obsidian) => 
    msg: |
      以下のCaskは対象Appの所有者/権限がずれているため、手動での対応が必要です：
      sudo chown -R $(whoami) /Applications/Obsidian.app
      その後、再度 make upgrade を実行してください。

TASK [homebrew : Cask（sudo必要）の手動アップグレード案内] *********************
ok: [testhost] => 
    msg: |
      以下のCaskはrootパスワードが必要なため、手動アップグレードが必要です：
      brew upgrade --cask docker-desktop logi-options+ microsoft-office

TASK [mas : アップデート対象がある場合に手動アップデート案内] *******************
ok: [testhost] => 
    msg: |
      以下のMac App Storeアプリにアップデートがあります：
      682658836  GarageBand  (10.4.13 -> 10.4.14)
      361285480  Keynote     (15.1.1  -> 15.3.1)

      `mas install --force` はsudoが必要なため自動更新できません。
      App Storeアプリの「アップデート」タブから手動でアップデートしてください。

PLAY RECAP *********************************************************************
testhost                   : ok=5    changed=1    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0   

=== make upgrade finished: 2026-08-12 09:02:10 ===
=== exit status: 0 ===
```

- [ ] **Step 2: アンカー定数を追加する**

`scripts/upgrade-summary.sh` の `TASK_CASK_REINSTALL` の直後に追記:

```bash
MSG_SUDO_CASK='以下のCaskはrootパスワードが必要なため'
MSG_PERM_CASK='以下のCaskは対象Appの所有者/権限がずれているため'
MSG_MAS='以下のMac App Storeアプリにアップデートがあります'
```

- [ ] **Step 3: awk の呼び出しに変数を渡す**

`parse_log` の awk 起動部分を差し替える:

```bash
  awk -v t_formula="$TASK_FORMULA" \
      -v t_cask="$TASK_CASK" \
      -v t_cask_re="$TASK_CASK_REINSTALL" \
      -v m_sudo="$MSG_SUDO_CASK" \
      -v m_perm="$MSG_PERM_CASK" \
      -v m_mas="$MSG_MAS" '
```

- [ ] **Step 4: 抽出ルールを追加する**

awk プログラム内、`mode != "" && /^changed: .*\(item=/` ブロックの**直後**に追記する。
`debug` の msg は複数行にわたるため、アンカー行で `pending` を立てて次行以降を拾う方式にする。

```awk
    index($0, m_sudo) { pending = "SUDO"; next }
    index($0, m_perm) { pending = "PERM"; next }
    index($0, m_mas)  { pending = "MAS";  next }

    pending == "SUDO" && /brew upgrade --cask / {
      s = $0; sub(/^.*brew upgrade --cask /, "", s)
      print "SUDO_CASK\t" trim(s); pending = ""; next
    }
    pending == "PERM" && /\/Applications\/.*\.app/ {
      s = $0; sub(/^.*\/Applications\//, "", s); sub(/\.app.*$/, "", s)
      print "PERM_CASK\t" trim(s); pending = ""; next
    }
    pending == "MAS" {
      line = trim($0)
      if (line == "") { pending = ""; next }   # 空行で app 一覧の終わり
      print "MAS\t" line; next
    }

    /^fatal: \[/ { print "ERROR\t" task; errdetail = 1; next }
    errdetail && /msg:/ {
      s = $0; sub(/^[ \t]*msg: "?/, "", s)
      print "ERROR_DETAIL\t" trim(s); errdetail = 0; next
    }
```

`TASK [` にマッチした行で `pending = ""` をリセットするため、
既存の `/^TASK \[/` ブロックの `mode = ""` の次の行に `pending = ""` を追加する。

- [ ] **Step 5: フィクスチャで検証する**

```bash
./scripts/upgrade-summary.sh --dump tests/fixtures/upgrade-manual-cases.log
```

期待する出力:

```
STARTED	2026-08-12 09:00:00
FORMULA	jq
PERM_CASK	Obsidian
SUDO_CASK	docker-desktop logi-options+ microsoft-office
MAS	682658836  GarageBand  (10.4.13 -> 10.4.14)
MAS	361285480  Keynote     (15.1.1  -> 15.3.1)
FINISHED	2026-08-12 09:02:10
STATUS	0
```

`mas install --force` を含む行が `MAS` として出ていないこと（空行で打ち切られていること）を確認する。

- [ ] **Step 6: 実ログでエラー抽出を検証する**

```bash
./scripts/upgrade-summary.sh --dump logs/upgrade-20260812-100703.log
```

期待する出力に以下が含まれること:

```
SUDO_CASK	docker-desktop logi-options+ microsoft-office
ERROR	workspace-base : workspace-baseをclone/更新
ERROR_DETAIL	Failed to download remote objects and refs:  sign_and_send_pubkey: signing failed
STATUS	2
```

- [ ] **Step 7: 既存ログで回帰がないことを確認する**

```bash
for f in logs/upgrade-20260811-102156.log logs/upgrade-20260810-170703.log; do
  echo "### $f"; ./scripts/upgrade-summary.sh --dump "$f"
done
```

期待: Task 1 で確認した `FORMULA` / `CASK` の抽出結果が変わっていないこと。

- [ ] **Step 8: コミット**

```bash
git add scripts/upgrade-summary.sh tests/fixtures/upgrade-manual-cases.log
git commit -m "upgrade通知: 要手動対応とエラーの抽出を追加"
```

---

### Task 3: サマリ描画と通知本文モード

中間表現を2つの形に描画する。全文サマリと、バナー用の2行本文。
通知の要否も判定する。

**Files:**
- Modify: `scripts/upgrade-summary.sh`

**Interfaces:**
- Consumes: Task 2 までの `parse_log`
- Produces:
  - `upgrade-summary.sh <logfile>` → 全文サマリを stdout、exit 0
  - `upgrade-summary.sh --notify <logfile>` → 通知本文（2行以内）を stdout。exit 0 = 通知すべき / exit 10 = 通知不要
  - `upgrade-summary.sh --title <logfile>` → 通知タイトル1行を stdout、exit 0

- [ ] **Step 1: 引数処理を3モードに拡張する**

既存の `MODE` 判定ブロックを差し替える:

```bash
MODE="summary"
case "${1:-}" in
  --dump)   MODE="dump";   shift ;;
  --notify) MODE="notify"; shift ;;
  --title)  MODE="title";  shift ;;
  -*)       usage ;;
esac
```

あわせて `usage()` の文言を更新する:

```bash
  echo "usage: ${0:t} [--dump|--notify|--title] <logfile>" >&2
```

- [ ] **Step 2: 中間表現を配列に読み込む処理を追加する**

`if [ "$MODE" = "dump" ]; then ... fi` ブロックの**直後**に挿入する
（dump モードは早期 exit するので、この処理を通らない）:

```bash
# ------------------------------------------------------------
# 中間表現をキーごとの配列へ
# ------------------------------------------------------------
typeset -a FORMULA CASK SUDO_CASK PERM_CASK MAS ERRORS ERROR_DETAILS
STARTED=""; FINISHED=""; STATUS="0"

while IFS=$'\t' read -r key value; do
  case "$key" in
    STARTED)       STARTED="$value" ;;
    FINISHED)      FINISHED="$value" ;;
    STATUS)        STATUS="$value" ;;
    FORMULA)       FORMULA+=("$value") ;;
    CASK)          CASK+=("$value") ;;
    SUDO_CASK)     SUDO_CASK+=("$value") ;;
    PERM_CASK)     PERM_CASK+=("$value") ;;
    MAS)           MAS+=("$value") ;;
    ERROR)         ERRORS+=("$value") ;;
    ERROR_DETAIL)  ERROR_DETAILS+=("$value") ;;
  esac
done < <(parse_log)

# 同じCaskが複数タスクで changed になる場合があるため重複を除く
CASK=(${(u)CASK})

# sudo必要Caskは1行にスペース区切りで入るので件数は語数で数える
SUDO_CASK_COUNT=0
if (( ${#SUDO_CASK} > 0 )); then
  SUDO_CASK_COUNT=${#${(z)SUDO_CASK[1]}}
fi

UPDATED_COUNT=$(( ${#FORMULA} + ${#CASK} ))
MANUAL_COUNT=$(( SUDO_CASK_COUNT + ${#PERM_CASK} + ${#MAS} ))
ERROR_COUNT=${#ERRORS}
```

`ERRORS` と `ERROR_DETAILS` は、awk が `ERROR` の直後に `ERROR_DETAIL` を出すため
同じ添字で対応する前提で扱う。`msg:` を持たない `fatal:` があった場合のみ
対応がずれるが、その場合も Step 4 の `${ERROR_DETAILS[$i]:-}` で落ちない。

- [ ] **Step 3: タイトルと通知モードを実装する**

Step 2 で追加した配列読み込みの直後に追記:

```bash
if [ "$STATUS" = "0" ]; then
  RESULT="成功"
else
  RESULT="失敗 (exit $STATUS)"
fi

if [ "$MODE" = "title" ]; then
  echo "make upgrade: $RESULT"
  exit 0
fi

if [ "$MODE" = "notify" ]; then
  # 通知の発行条件: 失敗・更新あり・要手動対応ありのいずれか。
  # 正常かつ無変化のときは黙る（1日2回の「更新なし」通知を避ける）。
  if [ "$STATUS" = "0" ] && (( UPDATED_COUNT == 0 )) && (( MANUAL_COUNT == 0 )); then
    exit 10
  fi

  if (( UPDATED_COUNT > 0 )); then
    echo "更新 Formula ${#FORMULA} / Cask ${#CASK}"
  else
    echo "更新なし"
  fi

  typeset -a warn
  (( MANUAL_COUNT > 0 )) && warn+=("要手動 ${MANUAL_COUNT}件")
  (( ERROR_COUNT > 0 ))  && warn+=("エラー ${ERROR_COUNT}件")
  (( ${#warn} > 0 )) && echo "⚠️ ${(j:・:)warn}"

  exit 0
fi
```

- [ ] **Step 4: 全文サマリの描画を実装する**

ファイル末尾の `parse_log`（Task 1 で暫定的に置いた行）を、以下で差し替える:

```bash
# ------------------------------------------------------------
# 全文サマリ
# ------------------------------------------------------------
echo "make upgrade: $RESULT"
if [ -n "$FINISHED" ]; then
  echo "$STARTED → $FINISHED"
else
  echo "$STARTED"
fi

if (( UPDATED_COUNT > 0 )); then
  echo ""
  echo "[更新]"
  if (( ${#FORMULA} > 0 )); then
    echo "Formula (${#FORMULA})"
    printf '  %s\n' "${FORMULA[@]}"
  fi
  if (( ${#CASK} > 0 )); then
    echo "Cask (${#CASK})"
    printf '  %s\n' "${CASK[@]}"
  fi
fi

if (( MANUAL_COUNT > 0 )); then
  echo ""
  echo "[要手動対応]"
  if (( SUDO_CASK_COUNT > 0 )); then
    echo "sudo が必要な Cask (${SUDO_CASK_COUNT})"
    echo "  brew upgrade --cask ${SUDO_CASK[1]}"
  fi
  if (( ${#PERM_CASK} > 0 )); then
    echo "権限がずれている Cask (${#PERM_CASK})"
    for app in "${PERM_CASK[@]}"; do
      echo "  sudo chown -R \$(whoami) /Applications/${app}.app"
    done
  fi
  if (( ${#MAS} > 0 )); then
    echo "Mac App Store (${#MAS})"
    printf '  %s\n' "${MAS[@]}"
    echo "  → App Store の「アップデート」タブから手動で"
  fi
fi

if (( ERROR_COUNT > 0 )); then
  echo ""
  echo "[エラー]"
  for i in {1..$ERROR_COUNT}; do
    echo "${ERRORS[$i]}"
    [ -n "${ERROR_DETAILS[$i]:-}" ] && echo "  ${ERROR_DETAILS[$i]}"
  done
fi

echo ""
echo "[詳細ログ]"
echo "$LOG_FILE"
```

- [ ] **Step 5: 失敗ログで全文サマリを確認する**

```bash
./scripts/upgrade-summary.sh logs/upgrade-20260812-100703.log
```

期待する出力:

```
make upgrade: 失敗 (exit 2)
2026-08-12 10:07:03

[要手動対応]
sudo が必要な Cask (3)
  brew upgrade --cask docker-desktop logi-options+ microsoft-office

[エラー]
workspace-base : workspace-baseをclone/更新
  Failed to download remote objects and refs:  sign_and_send_pubkey: signing failed

[詳細ログ]
logs/upgrade-20260812-100703.log
```

`[更新]` セクションが省略されていることを確認する。

- [ ] **Step 6: フィクスチャで全セクションを確認する**

```bash
./scripts/upgrade-summary.sh tests/fixtures/upgrade-manual-cases.log
```

期待: `[更新]`（Formula 1件）、`[要手動対応]`（sudo 3件・権限 1件・MAS 2件）が出て、
`[エラー]` セクションは省略される。1行目が `make upgrade: 成功`、
2行目が `2026-08-12 09:00:00 → 2026-08-12 09:02:10` になる。

- [ ] **Step 7: 通知モードと発行条件を確認する**

```bash
./scripts/upgrade-summary.sh --notify logs/upgrade-20260812-100703.log; echo "exit=$?"
./scripts/upgrade-summary.sh --notify logs/upgrade-20260811-102156.log; echo "exit=$?"
./scripts/upgrade-summary.sh --title  logs/upgrade-20260812-100703.log
```

期待:
1. 1つ目は `更新なし` / `⚠️ 要手動 3件・エラー 1件` の2行、`exit=0`
2. 2つ目は `更新 Formula 2 / Cask 2` を含み、`exit=0`
3. 3つ目は `make upgrade: 失敗 (exit 2)`

- [ ] **Step 8: 「黙る」条件を確認する**

正常・無変化のログを一時的に作って判定させる:

```bash
printf '=== make upgrade started: 2026-08-12 08:00:00 ===\n=== exit status: 0 ===\n' \
  > /tmp/quiet.log
./scripts/upgrade-summary.sh --notify /tmp/quiet.log; echo "exit=$?"
```

期待: 何も出力されず `exit=10`。

- [ ] **Step 9: コミット**

```bash
git add scripts/upgrade-summary.sh
git commit -m "upgrade通知: サマリ描画と通知本文モードを追加"
```

---

### Task 4: ラッパーの置き換えと依存の追加

`upgrade-scheduled.sh` から LLM 要約を削除し、`upgrade-summary.sh` と
`terminal-notifier` を使う形に置き換える。

**Files:**
- Modify: `scripts/upgrade-scheduled.sh`
- Modify: `group_vars/all.yml`（`brew_formula` に追加）
- Modify: `CLAUDE.md`

**Interfaces:**
- Consumes: `scripts/upgrade-summary.sh` の3モード（Task 3 の Produces）

- [ ] **Step 1: `terminal-notifier` を Homebrew Formula に追加する**

`group_vars/all.yml` の `brew_formula` の「CLI ユーティリティ」ブロック内、
`telnet` と `tree` の間（アルファベット順）に1行追加する:

```yaml
  - terminal-notifier
```

- [ ] **Step 2: インストールして `-open` の挙動を実機で確認する**

```bash
make homebrew
```

初回はシステム設定 > 通知 で「terminal-notifier」の通知を許可する必要がある。
許可したうえで、既存ログのサマリを一時ファイルに出して確認する:

```bash
./scripts/upgrade-summary.sh logs/upgrade-20260812-100703.log > /tmp/summary-test.txt
terminal-notifier -title "テスト" -message "クリックして全文" \
  -open "file:///tmp/summary-test.txt"
```

期待: 通知が出て、クリックすると `/tmp/summary-test.txt` が TextEdit で開く。

**仕様書の未検証事項:** ここでクリックしても開かない場合は、
`-open` の代わりに `-execute "open /tmp/summary-test.txt"` を試し、
動いたほうを Step 3 の実装で採用する。どちらを採用したかをコミットメッセージに残す。

- [ ] **Step 3: ラッパーを書き換える**

`scripts/upgrade-scheduled.sh` に対して3箇所の編集を行う。
**ログ間引き節（`KEEP_LOGS` を使う while ループ）と末尾の `exit $STATUS` は現行のまま残すこと。**

**(1) 冒頭の定数から `CLAUDE_BIN` の行を削除する:**

```bash
CLAUDE_BIN="/opt/homebrew/bin/claude"
```

**(2) `STATUS=$?` の直後にある `RESULT` の判定ブロックを削除する:**

タイトルは `upgrade-summary.sh --title` が返すため不要になる。

```bash
if [ $STATUS -eq 0 ]; then
  RESULT="成功"
else
  RESULT="失敗"
fi
```

**(3) 「通知本文の生成」節の見出しコメントから `osascript` ブロックの終わり
（`APPLESCRIPT` の行）までを、以下で置き換える:**

```bash
SUMMARY_SCRIPT="$REPO_DIR/scripts/upgrade-summary.sh"
LATEST_SUMMARY="$LOG_DIR/latest-summary.txt"

# ------------------------------------------------------------
# サマリ生成（通知の有無にかかわらず常に書き出す）
# ------------------------------------------------------------
"$SUMMARY_SCRIPT" "$LOG_FILE" > "$LATEST_SUMMARY" 2>/dev/null

# ------------------------------------------------------------
# 通知
# 更新・要手動対応・失敗のいずれかがある場合のみ出す（exit 10 = 通知不要）
# ------------------------------------------------------------
BODY=$("$SUMMARY_SCRIPT" --notify "$LOG_FILE" 2>/dev/null)
NOTIFY_RC=$?

if [ $NOTIFY_RC -eq 0 ]; then
  TITLE=$("$SUMMARY_SCRIPT" --title "$LOG_FILE" 2>/dev/null)

  if command -v terminal-notifier >/dev/null 2>&1; then
    terminal-notifier \
      -title "$TITLE" \
      -message "$BODY" \
      -open "file://$LATEST_SUMMARY"
  else
    # terminal-notifier 未導入のマシン向けフォールバック。
    # クリックはできないが通知は途切れさせない。
    /usr/bin/osascript - "$TITLE" "$BODY" <<'APPLESCRIPT'
on run argv
  display notification (item 2 of argv) with title (item 1 of argv)
end run
APPLESCRIPT
  fi
fi
```

**(4) 終了時刻の記録を追加する**（サマリ2行目の `→` 表示に使う）。
`STATUS=$?` の次の行、既存の `echo "=== exit status: $STATUS ===" >>"$LOG_FILE"` より
**前**に置くこと:

```bash
echo "=== make upgrade finished: $(date '+%Y-%m-%d %H:%M:%S') ===" >>"$LOG_FILE"
```

なお `logs/` の既存ログにはこの行が無いため、`upgrade-summary.sh` は
`FINISHED` が空のときサマリ2行目に開始時刻だけを出す（Task 3 Step 4 で実装済み）。

- [ ] **Step 4: 削除されたことを確認する**

```bash
grep -nE "CLAUDE_BIN|claude -p|PROMPT|--model haiku|grep -q \"手動\"" scripts/upgrade-scheduled.sh
```

期待: 1件もヒットしない（exit 1）。

- [ ] **Step 5: ラッパーを実際に走らせる**

```bash
zsh scripts/upgrade-scheduled.sh; echo "exit=$?"
```

期待:
1. 新しい `logs/upgrade-<timestamp>.log` が作られる
2. `logs/latest-summary.txt` が生成され、内容が末尾の `[詳細ログ]` まで揃っている
3. 通知が出る（今の環境は sudo 必要 Cask があるため通知条件を満たす）
4. 通知をクリックすると `latest-summary.txt` が開く

```bash
cat logs/latest-summary.txt
```

- [ ] **Step 6: `CLAUDE.md` を更新する**

「Scheduled `make upgrade` (launchd)」節の第1段落を差し替える。
現行の記述は `claude -p --model haiku` による要約を説明しているため、実装と食い違う。

```markdown
`scripts/upgrade-scheduled.sh` is the wrapper the LaunchAgent runs. It writes the full log to `logs/upgrade-<timestamp>.log` (keeping the last 20), then calls `scripts/upgrade-summary.sh` to parse that log into a deterministic summary at `logs/latest-summary.txt` (fixed path, overwritten each run). The notification shows a two-line digest via `terminal-notifier`; clicking it opens the full summary. It never calls sudo — sudo-required Casks, permission-mismatched Casks, and Mac App Store updates all surface as 要手動対応 entries in the summary.

Notifications are only posted when something happened: a non-zero exit, at least one upgraded package, or at least one 要手動対応 item. A clean run with no changes stays silent, so a notification always means there is something to look at. The summary file is written either way.

`scripts/upgrade-summary.sh` takes a log file and prints the summary (`--notify` for the notification body, exit 10 meaning "nothing to report"; `--title` for the title; `--dump` for the parsed intermediate form). It has no side effects, so any archived log under `logs/` can be replayed through it for debugging.
```

**注意:** このパーサは `roles/homebrew/tasks/upgrade.yml` と `roles/mas/tasks/upgrade.yml`
のタスク名・`debug` 文言に依存している。その旨も同節に1文追加する:

```markdown
The parser anchors on task names and `debug` message wording from `roles/homebrew/tasks/upgrade.yml` and `roles/mas/tasks/upgrade.yml`. Those anchors are defined as constants at the top of `scripts/upgrade-summary.sh` — if you rename a task in those roles, update the constants there.
```

- [ ] **Step 7: コミット**

```bash
git add scripts/upgrade-scheduled.sh group_vars/all.yml CLAUDE.md
git commit -m "upgrade通知: LLM要約を廃止してterminal-notifierとパーサに置き換え"
```

---

## 検証まとめ

| ログ | 検証内容 | 使うタスク |
|---|---|---|
| `logs/upgrade-20260812-100703.log` | 更新0件・sudo 必要 Cask 3件・エラー1件（failed=1） | 1, 2, 3 |
| `logs/upgrade-20260811-102156.log` | Formula 2件・Cask 更新および failed 混在 | 1, 2, 3 |
| `logs/upgrade-20260810-170703.log` | Cask 1件のみ更新 | 1, 2 |
| `tests/fixtures/upgrade-manual-cases.log` | 権限エラー Cask・MAS 要対応（既存ログに無い） | 2, 3 |
| `/tmp/quiet.log`（Task 3 で生成） | 正常・無変化 → 通知しない | 3 |
