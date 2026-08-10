#!/bin/zsh
# launchdから定期実行される `make upgrade` のラッパー。
# 実行ログをlogs/へ残し、結果の要約をmacOSの通知センターへ表示する。
# sudoは一切使わない（sudo必要なCaskはAnsibleが案内を出力するだけ）。
set -u

# launchdは最小限のPATHしか渡さないため明示的に設定する
export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:$HOME/.local/share/mise/shims:/usr/bin:/bin:/usr/sbin:/sbin"

REPO_DIR="${0:A:h:h}"
LOG_DIR="$REPO_DIR/logs"
LOG_FILE="$LOG_DIR/upgrade-$(date +%Y%m%d-%H%M%S).log"
CLAUDE_BIN="/opt/homebrew/bin/claude"
KEEP_LOGS=20

mkdir -p "$LOG_DIR"
cd "$REPO_DIR" || exit 1

# ------------------------------------------------------------
# make upgrade
# ------------------------------------------------------------
{
  echo "=== make upgrade started: $(date '+%Y-%m-%d %H:%M:%S') ==="
  make upgrade
} >"$LOG_FILE" 2>&1
STATUS=$?
echo "=== exit status: $STATUS ===" >>"$LOG_FILE"

if [ $STATUS -eq 0 ]; then
  RESULT="成功"
else
  RESULT="失敗"
fi

# ------------------------------------------------------------
# 通知本文の生成（claudeが使えない場合はログから機械的に組み立てる）
# ------------------------------------------------------------
PROMPT=$(cat <<'EOF'
以下はmacOSプロビジョニングの `make upgrade` の実行ログです。
macOSの通知センターに表示する要約を日本語で作ってください。

制約:
- 全体で200文字以内
- 1行目: 更新されたFormula / Cask / Mac App Storeの件数（更新がなければ「更新なし」）
- 2行目: 主要な更新パッケージ名を数個だけ
- 3行目: 手動対応が必要な案内（sudoが必要なCask、所有権エラー）があればその旨。なければこの行は省略
- 失敗している場合は原因を一行で
- 前置き・見出し・マークダウン記法は使わず、本文だけを出力
EOF
)

SUMMARY=""
if [ -x "$CLAUDE_BIN" ]; then
  SUMMARY=$(tail -c 40000 "$LOG_FILE" \
    | "$CLAUDE_BIN" -p "$PROMPT" --model haiku --disallowedTools "Bash" "Write" "Edit" \
    2>>"$LOG_FILE")
fi

if [ -z "$SUMMARY" ]; then
  # フォールバック: ログから要点だけ抜く
  SUMMARY=$(grep -E "^(localhost|127\.0\.0\.1)\s+:\s+ok=" "$LOG_FILE" | tail -1)
  [ -z "$SUMMARY" ] && SUMMARY="要約を生成できませんでした。ログを確認してください。"
fi

# 手動対応が必要かどうかはログから直接判定する（要約の取りこぼしを防ぐ）
if grep -q "手動" "$LOG_FILE"; then
  SUMMARY="${SUMMARY}
⚠️ 要手動対応あり"
fi

BODY="${SUMMARY}
ログ: ${LOG_FILE:t}"

# ------------------------------------------------------------
# 通知
# ------------------------------------------------------------
/usr/bin/osascript - "make upgrade: $RESULT" "$BODY" <<'APPLESCRIPT'
on run argv
  display notification (item 2 of argv) with title (item 1 of argv)
end run
APPLESCRIPT

# ------------------------------------------------------------
# 古いログを間引く
# ------------------------------------------------------------
ls -1t "$LOG_DIR"/upgrade-*.log 2>/dev/null | tail -n +$((KEEP_LOGS + 1)) | while read -r old; do
  rm -f "$old"
done

exit $STATUS
