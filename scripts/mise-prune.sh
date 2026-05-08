#!/usr/bin/env bash
########################################################
# mise Prune Script
########################################################
# 同一ツールに複数バージョンがインストールされていて、かつ
# 非アクティブ（どのmise.tomlからも参照されていない）バージョンを削除する。
#
# 使い方:
#   scripts/mise-prune.sh           # dry-run（削除候補を表示するだけ）
#   scripts/mise-prune.sh -y        # 確認なしで削除
#   scripts/mise-prune.sh --apply   # 対話的に確認して削除
#
# 判定基準:
#   - 同一ツール（例: python, node）に2つ以上のバージョンが存在すること
#   - 当該バージョンが active=false （mise.toml で参照されていない）であること
########################################################
set -euo pipefail

########################################################
# 設定
########################################################
MODE="dry-run"  # dry-run | apply | yes

########################################################
# 引数パース
########################################################
parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -y|--yes)
        MODE="yes"
        shift
        ;;
      --apply)
        MODE="apply"
        shift
        ;;
      -h|--help)
        sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'
        exit 0
        ;;
      *)
        echo "❌ 不明な引数: $1" >&2
        echo "使い方: $0 [-y|--yes|--apply]" >&2
        exit 1
        ;;
    esac
  done
}

########################################################
# 前提チェック
########################################################
check_prerequisites() {
  if ! command -v mise >/dev/null 2>&1; then
    echo "❌ mise が見つかりません。" >&2
    exit 1
  fi
  if ! command -v jq >/dev/null 2>&1; then
    echo "❌ jq が見つかりません。 brew install jq でインストールしてください。" >&2
    exit 1
  fi
}

########################################################
# 削除候補の抽出
#
# 出力形式: "tool@version" を1行ずつ
########################################################
collect_prune_targets() {
  mise list --json | jq -r '
    to_entries[]
    | select((.value | length) >= 2)
    | .key as $tool
    | .value[]
    | select(.installed == true and .active == false)
    | "\($tool)@\(.version)"
  '
}

########################################################
# 削除実行
########################################################
uninstall_one() {
  local target="$1"
  echo "🗑  mise uninstall ${target}"
  mise uninstall "${target}"
}

########################################################
# メイン処理
########################################################
main() {
  parse_args "$@"
  check_prerequisites

  echo "🔍 mise の削除候補を検出しています..."
  local targets
  targets="$(collect_prune_targets)"

  if [[ -z "${targets}" ]]; then
    echo "✨ 削除候補はありません。"
    exit 0
  fi

  echo ""
  echo "削除候補（非アクティブ かつ 同一ツールに複数バージョンあり）:"
  echo "${targets}" | sed 's/^/  - /'
  echo ""

  case "${MODE}" in
    dry-run)
      echo "ℹ️  dry-run モードです。実際に削除するには -y または --apply を付けて再実行してください。"
      exit 0
      ;;
    apply)
      printf "上記を削除しますか？ [y/N]: "
      read -r reply
      if [[ ! "${reply}" =~ ^[Yy]$ ]]; then
        echo "中止しました。"
        exit 0
      fi
      ;;
    yes)
      ;;
  esac

  while IFS= read -r target; do
    [[ -z "${target}" ]] && continue
    uninstall_one "${target}"
  done <<< "${targets}"

  echo ""
  echo "✅ 完了しました。"
}

main "$@"
