#!/usr/bin/env bash
########################################################
# Mac Provisioning Bootstrap Script
########################################################
# このスクリプトはAnsibleプレイブック実行のための基本環境をセットアップします。
#
# 前提条件:
# - macOS (Apple Silicon専用)
# - Homebrewが手動でインストール済みであること
#
# このスクリプトがインストールするもの:
# - mise (Homebrew経由)
# - Python (mise経由)
# - Ansible (pip経由)
# - Ansible Collections
########################################################
set -euo pipefail

########################################################
# 設定
########################################################
readonly PYTHON_VERSION=3.13.7

########################################################
# ヘルパー関数
########################################################

# mise環境を有効化
ensure_mise_in_path() {
  if command -v mise >/dev/null 2>&1; then
    set +u
    eval "$(mise activate bash 2>/dev/null || mise activate zsh 2>/dev/null)" || true
    set -u
  fi
}

# コマンドが存在し、正常に動作するか確認
command_exists_and_works() {
  local cmd="$1"
  command -v "${cmd}" >/dev/null 2>&1 && "${cmd}" --version >/dev/null 2>&1
}

# デバッグ情報を出力
print_debug_info() {
  echo "   デバッグ情報:"
  echo "   - which python3: $(which python3)"
  echo "   - python3 --version: $(python3 --version 2>&1)"
  echo "   - mise which python3: $(mise which python3 2>/dev/null || echo '見つかりません')"
  echo "   - ansibleコマンド: $(command -v ansible || echo '見つかりません')"
  echo "   - Python実行可能ファイルの場所: $(python3 -c 'import sys; print(sys.executable)' 2>/dev/null || echo '確認できません')"
  echo "   - Python site-packages: $(python3 -c 'import site; print(site.getsitepackages())' 2>/dev/null || echo '確認できません')"
  echo "   - PATH: $PATH"
}

########################################################
# sudo権限の確認
########################################################
setup_sudo() {
  echo "🔐 このスクリプトには管理者権限が必要です。"
  echo "パスワードを入力してください..."
  sudo -v

  # sudo権限の維持（バックグラウンドで60秒ごとに更新）
  while true; do
    sudo -n true
    sleep 60
    kill -0 "$$" || exit
  done 2>/dev/null &
}

########################################################
# Homebrewの確認
########################################################
check_homebrew() {
  # macOS前提: Apple Silicon専用
  if [[ "$(uname)" != "Darwin" ]]; then
    echo "❌ このスクリプトはmacOS専用です。" >&2
    exit 1
  fi

  local brew_prefix="/opt/homebrew"

  # 現在のシェルに環境変数を設定（まだ設定されていない場合）
  if ! command -v brew >/dev/null 2>&1; then
    if [ -f "${brew_prefix}/bin/brew" ]; then
      eval "$(${brew_prefix}/bin/brew shellenv)"
    else
      echo "❌ Homebrewがインストールされていません。"
      echo "   手動でインストールしてください:"
      echo "   /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
      echo "   eval \"\$(/opt/homebrew/bin/brew shellenv)\""
      exit 1
    fi
  fi

  echo "✅ Homebrewが確認できました ($(brew --version | head -n1))。"
}

########################################################
# Xcode Command Line Toolsのインストール
########################################################
install_xcode_command_line_tools() {
  if xcode-select -p >/dev/null 2>&1; then
    echo "✅ Xcode Command Line Toolsは既にインストール済みです。"
    return 0
  fi

  echo "📦 Xcode Command Line Toolsをインストールしています..."
  xcode-select --install || true
  echo "✅ Xcode Command Line Toolsのインストールが完了しました。"
}

########################################################
# miseのインストール
########################################################
install_mise() {
  if command -v mise >/dev/null 2>&1; then
    echo "✅ miseは既にインストール済みです。"
  else
    echo "📦 miseをインストールしています..."
    brew install mise
    echo "✅ miseのインストールが完了しました。"
  fi

  ensure_mise_in_path
}

########################################################
# Python3/pipのインストール
########################################################
# Pythonビルドに必要な依存パッケージ（build dependencies）のインストールも考慮した処理に改修
install_python() {
  # Pythonのビルドに必要な依存パッケージをHomebrew経由でインストール
  echo "📦 Pythonのビルドに必要な依存パッケージをインストールしています..."
  brew install openssl readline sqlite3 xz zlib tcl-tk bzip2 libffi

  # mise経由で指定バージョンがインストールされているか確認
  if mise list python 2>/dev/null | grep -q "${PYTHON_VERSION}"; then
    echo "✅ Python ${PYTHON_VERSION} (mise) は既にインストール済みです。"
  else
    echo "📦 Python ${PYTHON_VERSION}をmise経由でインストールしています..."
    # Apple Silicon環境でのビルドを確実にするため環境変数を設定
    export CPPFLAGS="-I/opt/homebrew/include"
    export LDFLAGS="-L/opt/homebrew/lib"
    export PKG_CONFIG_PATH="/opt/homebrew/lib/pkgconfig"
    mise use python@${PYTHON_VERSION}
    echo "✅ Pythonのインストールが完了しました。"
  fi

  ensure_mise_in_path

  # pipを最新版にアップグレード
  echo "📦 pipをアップグレードしています..."
  mise exec python@${PYTHON_VERSION} -- python3 -m ensurepip --upgrade 2>/dev/null || true
  mise exec python@${PYTHON_VERSION} -- python3 -m pip install --upgrade pip
  echo "✅ pipの準備が完了しました (Python: $(mise exec python@${PYTHON_VERSION} -- python3 --version))。"
}

########################################################
# Ansibleのインストール（mise Python環境にインストール）
########################################################
install_ansible() {
  # Ansibleが正常に動作するか確認
  if command_exists_and_works ansible; then
    local ansible_version
    ansible_version=$(ansible --version | head -n1)
    echo "✅ Ansibleは既にインストール済みです (${ansible_version})。"
    return 0
  fi

  # Ansibleが存在するが動作しない場合（Pythonバージョン変更など）
  if command -v ansible >/dev/null 2>&1; then
    echo "⚠️  Ansibleが見つかりましたが、正常に動作しません。再インストールします..."
  fi

  ensure_mise_in_path

  # 既存のAnsibleが~/.localにインストールされている場合は削除
  if mise exec python@${PYTHON_VERSION} -- python3 -m pip show ansible 2>/dev/null | grep -q "Location:.*\.local"; then
    echo "📦 既存のAnsibleを~/.localから削除しています..."
    mise exec python@${PYTHON_VERSION} -- python3 -m pip uninstall -y ansible ansible-core 2>/dev/null || true
  fi

  echo "📦 Ansibleをインストールしています..."
  # PIP_USER=falseを設定して、mise Python環境に直接インストール
  # --force-reinstallで既存のパッケージを再インストール
  PIP_USER=false mise exec python@${PYTHON_VERSION} -- python3 -m pip install --force-reinstall ansible

  # インストール確認（少し待ってから確認）
  sleep 1
  if command_exists_and_works ansible; then
    local ansible_version
    ansible_version=$(ansible --version | head -n1)
    echo "✅ Ansibleのインストールが完了しました (${ansible_version})。"
  else
    echo "❌ Ansibleのインストールに失敗しました。"
    print_debug_info
    return 1
  fi
}

########################################################
# inventory.ini の自動生成
########################################################
setup_inventory() {
  local hostname
  hostname=$(scutil --get LocalHostName)
  local inventory_file
  inventory_file="$(cd "$(dirname "$0")/.." && pwd)/inventory.ini"

  echo "📋 inventory.ini を生成しています (ホスト名: ${hostname})..."
  cat > "${inventory_file}" << EOF
[local]
${hostname} ansible_connection=local ansible_host=localhost
EOF
  echo "✅ inventory.ini を生成しました。"

  # host_vars/{hostname}.yml が存在しない場合はテンプレートからコピー
  local host_vars_dir
  host_vars_dir="$(cd "$(dirname "$0")/.." && pwd)/host_vars"
  local host_vars_file="${host_vars_dir}/${hostname}.yml"
  local template_file="${host_vars_dir}/_template.yml"

  if [ ! -f "${host_vars_file}" ]; then
    if [ -f "${template_file}" ]; then
      cp "${template_file}" "${host_vars_file}"
      echo "✅ host_vars/${hostname}.yml をテンプレートから作成しました。"
      echo "   必要に応じて編集してください: ${host_vars_file}"
    else
      echo "⚠️  host_vars/${hostname}.yml が存在しません。"
      echo "   マシン固有の設定が必要な場合は作成してください: ${host_vars_file}"
    fi
  else
    echo "✅ host_vars/${hostname}.yml が既に存在します。"
  fi
}

########################################################
# Ansible Collectionsのインストール
########################################################
install_ansible_collections() {
  if [ ! -f requirements.yml ]; then
    echo "⚠️  requirements.ymlが見つかりません。collection のインストールをスキップします。"
    return 0
  fi

  # ansible-galaxyが正常に動作するか確認
  if ! command_exists_and_works ansible-galaxy; then
    echo "❌ ansible-galaxyが正常に動作しません。Ansibleの再インストールが必要です。"
    return 1
  fi

  echo "📦 Ansible collectionsをインストールしています..."
  ansible-galaxy collection install -r requirements.yml || true
  echo "✅ Ansible collectionsのインストールが完了しました。"
}

########################################################
# 現在のシェルセッションにmiseを読み込む
########################################################
# 注: ~/.zshrc への mise activate の追記は dotfiles（chezmoi）側で管理する。
# ここでは、後続の make provision 等で mise コマンドを使えるよう
# 現在のシェルセッションにのみ環境を読み込む。
load_mise_in_current_shell() {
  if command -v mise >/dev/null 2>&1; then
    set +u
    eval "$(mise activate bash 2>/dev/null || mise activate zsh 2>/dev/null)" || true
    set -u
    echo "✅ 現在のシェルセッションにmiseを読み込みました。"
  fi
}

########################################################
# メイン処理
########################################################
main() {
  setup_sudo
  check_homebrew
  install_xcode_command_line_tools
  install_mise
  install_python
  install_ansible
  install_ansible_collections
  setup_inventory
  load_mise_in_current_shell

  # 完了メッセージ
  echo ""
  echo "=========================================="
  echo "  ブートストラップが完了しました！ 🎉"
  echo "=========================================="
  echo ""
  echo "インストール済み:"
  echo "  ✅ mise"
  echo "  ✅ Python (mise経由)"
  echo "  ✅ Ansible"
  echo "  ✅ Ansible Collections"
  echo ""
  echo "📝 注意:"
  echo "   ~/.zshrc への mise activate 設定は make provision 実行時に"
  echo "   chezmoi（dotfiles）経由で適用されます。"
  echo ""
  echo "次のステップ:"
  echo "  1. 以下を実行: make provision"
  echo "  2. ターミナルを再起動 or source ~/.zshrc"
  echo ""
}

main
