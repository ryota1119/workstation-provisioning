#!/usr/bin/env bash
########################################################
# chezmoi Dotfiles Management Script
########################################################
# chezmoiによるdotfilesの初期化・更新・適用を行う。
# 1Password CLIが未認証の場合、シークレットを必要とする
# update/apply処理はスキップして正常終了する。
#
# 使い方:
#   scripts/chezmoi.sh           # init → apply（新規セットアップ）
#   scripts/chezmoi.sh init      # 未初期化の場合のみリポジトリを初期化
#   scripts/chezmoi.sh upgrade   # fetch後、差分があればupdate
#   scripts/chezmoi.sh apply     # 差分があればapply
########################################################
set -euo pipefail

########################################################
# 設定
########################################################
readonly CHEZMOI_REPO_URL="git@github.com:ryota1119/dotfiles.git"
readonly CHEZMOI_SOURCE_DIR="${HOME}/.local/share/chezmoi"
CHEZMOI_BIN=""

########################################################
# 前提チェック
########################################################
resolve_chezmoi_bin() {
  if ! command -v brew >/dev/null 2>&1; then
    echo "❌ Homebrewが見つかりません。先にmake mac-bootstrapを実行してください。" >&2
    return 1
  fi

  CHEZMOI_BIN="$(brew --prefix)/bin/chezmoi"
  if [[ ! -x "${CHEZMOI_BIN}" ]]; then
    echo "❌ chezmoiが見つかりません。brew install chezmoiでインストールしてください。" >&2
    return 1
  fi
}

# update/applyでは1Passwordからシークレットを取得するため、認証済みか確認する。
check_op_auth() {
  if ! command -v op >/dev/null 2>&1 || ! op account list >/dev/null 2>&1; then
    echo "⚠️  1Password CLIにサインインしていません。"
    echo "dotfilesのシークレット情報を取得できないため、chezmoi update/applyをスキップします。"
    echo "手動で認証する場合: op signin"
    return 1
  fi
}

########################################################
# chezmoi処理
########################################################
run_init() {
  if [[ -d "${CHEZMOI_SOURCE_DIR}/.git" ]]; then
    echo "✅ chezmoiは初期化済みです。"
    return 0
  fi

  echo "📥 dotfilesリポジトリを初期化しています..."
  if ! "${CHEZMOI_BIN}" init "${CHEZMOI_REPO_URL}"; then
    echo "❌ chezmoiの初期化に失敗しました。" >&2
    echo "GitHubへのSSH認証に失敗した可能性があります。~/.ssh/configや鍵の登録を確認してください。" >&2
    return 1
  fi
}

run_upgrade() {
  if [[ ! -d "${CHEZMOI_SOURCE_DIR}/.git" ]]; then
    echo "❌ chezmoiが未初期化です。先にscripts/chezmoi.sh initを実行してください。" >&2
    return 1
  fi

  check_op_auth || return 0

  echo "🔄 dotfilesリポジトリを取得しています..."
  if ! "${CHEZMOI_BIN}" git -- fetch; then
    echo "❌ dotfilesリポジトリのfetchに失敗しました。" >&2
    echo "GitHubへのSSH認証に失敗しました。~/.ssh/configや鍵の登録を確認してください。" >&2
    return 1
  fi

  local head_revision upstream_revision status_output
  head_revision="$("${CHEZMOI_BIN}" git -- rev-parse HEAD)"
  upstream_revision="$("${CHEZMOI_BIN}" git -- rev-parse '@{u}' 2>/dev/null || true)"
  status_output="$("${CHEZMOI_BIN}" status)"

  if [[ -n "${status_output}" || ( -n "${upstream_revision}" && "${head_revision}" != "${upstream_revision}" ) ]]; then
    echo "⬆️  dotfilesを更新しています..."
    "${CHEZMOI_BIN}" update --force
  else
    echo "✅ dotfilesは最新です。"
  fi
}

run_apply() {
  if [[ ! -d "${CHEZMOI_SOURCE_DIR}/.git" ]]; then
    echo "❌ chezmoiが未初期化です。先にscripts/chezmoi.sh initを実行してください。" >&2
    return 1
  fi

  check_op_auth || return 0

  local status_output
  status_output="$("${CHEZMOI_BIN}" status)"
  if [[ -z "${status_output}" ]]; then
    echo "✅ 適用するdotfilesの差分はありません。"
  else
    echo "📝 dotfilesの差分を適用しています..."
    "${CHEZMOI_BIN}" apply --force
  fi
}

########################################################
# メイン処理
########################################################
main() {
  if [[ $# -gt 1 ]]; then
    echo "❌ 引数が多すぎます。" >&2
    echo "使い方: $0 [init|upgrade|apply]" >&2
    return 1
  fi

  resolve_chezmoi_bin

  case "${1:-setup}" in
    init)
      run_init
      ;;
    upgrade)
      run_upgrade
      ;;
    apply)
      run_apply
      ;;
    setup)
      run_init
      run_apply
      ;;
    *)
      echo "❌ 不明なサブコマンド: $1" >&2
      echo "使い方: $0 [init|upgrade|apply]" >&2
      return 1
      ;;
  esac
}

main "$@"
