#!/usr/bin/env bash
########################################################
# Mac Provisioning Bootstrap Script
########################################################
# このスクリプトはAnsibleプレイブック実行のための基本環境をセットアップします。
#
# 前提条件:
# - Homebrewが手動でインストール済みであること
#
# このスクリプトがインストールするもの:
# - asdf (Homebrew経由)
# - Python (asdf経由)
# - Ansible (pip経由)
# - Ansible Collections
########################################################
set -euo pipefail

########################################################
# 設定
########################################################
readonly PYTHON_VERSION=3.13.7
readonly ASDF_SHIMS_PATH="$HOME/.asdf/shims"

########################################################
# ヘルパー関数
########################################################

# asdfのshimをPATHに追加（まだ追加されていない場合）
ensure_asdf_in_path() {
  if [[ ":$PATH:" != *":${ASDF_SHIMS_PATH}:"* ]]; then
    export PATH="${ASDF_SHIMS_PATH}:$PATH"
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
  echo "   - Python: $(which python3) ($(python3 --version 2>&1))"
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
  # macOS前提: Homebrewのパスをアーキテクチャ（Apple Silicon/Intel）で分岐
  if [[ "$(uname)" != "Darwin" ]]; then
    echo "❌ このスクリプトはmacOS専用です。" >&2
    exit 1
  fi

  local brew_prefix
  if [[ "$(uname -m)" == "arm64" ]]; then
    brew_prefix="/opt/homebrew"
  else
    brew_prefix="/usr/local"
  fi

  # 現在のシェルに環境変数を設定（まだ設定されていない場合）
  if ! command -v brew >/dev/null 2>&1; then
    if [ -f "${brew_prefix}/bin/brew" ]; then
      eval "$(${brew_prefix}/bin/brew shellenv)"
    else
      echo "❌ Homebrewがインストールされていません。"
      echo "   手動でインストールしてください:"
      echo "   /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
      if [[ "${brew_prefix}" == "/opt/homebrew" ]]; then
        echo "   eval \"\$(/opt/homebrew/bin/brew shellenv)\"  # Apple Silicon Macの場合"
      fi
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
# asdfのインストール
########################################################
install_asdf() {
  if command -v asdf >/dev/null 2>&1; then
    echo "✅ asdfは既にインストール済みです。"
  else
    echo "📦 asdfをインストールしています..."
    brew install asdf
    echo "✅ asdfのインストールが完了しました。"
  fi

  ensure_asdf_in_path
}

########################################################
# Python3/pipのインストール
########################################################
# Pythonビルドに必要な依存パッケージ（build dependencies）のインストールも考慮した処理に改修
install_python() {
  # Pythonのビルドに必要な依存パッケージをHomebrew経由でインストール
  echo "📦 Pythonのビルドに必要な依存パッケージをインストールしています..."
  brew install openssl readline sqlite3 xz zlib tcl-tk

  # asdfのpythonプラグインが存在するか確認
  if asdf plugin list 2>/dev/null | grep -q "^python$"; then
    echo "✅ asdf pythonプラグインは既にインストール済みです。"
  else
    echo "📦 asdf pythonプラグインをインストールしています..."
    asdf plugin add python
  fi

  # asdf経由で指定バージョンがインストールされているか確認
  if asdf list python 2>/dev/null | grep -q "${PYTHON_VERSION}"; then
    echo "✅ Python ${PYTHON_VERSION} (asdf) は既にインストール済みです。"
  else
    echo "📦 Python ${PYTHON_VERSION}をasdf経由でインストールしています..."
    asdf install python ${PYTHON_VERSION}
    echo "✅ Pythonのインストールが完了しました。"
  fi

  # ローカルバージョンの設定（asdf経由を確実に使用）
  echo "📦 Python ${PYTHON_VERSION}をローカルバージョンに設定しています..."
  asdf set python ${PYTHON_VERSION}

  ensure_asdf_in_path

  # asdfのshimを更新
  asdf reshim python

  # pipを最新版にアップグレード
  echo "📦 pipをアップグレードしています..."
  python3 -m ensurepip --upgrade 2>/dev/null || true
  python3 -m pip install --upgrade pip
  echo "✅ pipの準備が完了しました (Python: $(python3 --version))。"
}

########################################################
# Ansibleのインストール（asdf Python環境にインストール）
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

  ensure_asdf_in_path

  # 既存のAnsibleが~/.localにインストールされている場合は削除
  if python3 -m pip show ansible 2>/dev/null | grep -q "Location:.*\.local"; then
    echo "📦 既存のAnsibleを~/.localから削除しています..."
    python3 -m pip uninstall -y ansible ansible-core 2>/dev/null || true
  fi

  echo "📦 Ansibleをインストールしています..."
  # PIP_USER=falseを設定して、asdf Python環境に直接インストール
  # --force-reinstallで既存のパッケージを再インストール
  PIP_USER=false python3 -m pip install --force-reinstall ansible
  asdf reshim

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
# 環境変数の設定（シェル設定ファイルに追加）
########################################################
setup_environment_variables() {
  local shell_config
  local asdf_brew_prefix
  local asdf_init_script

  # asdfの初期化スクリプトのパスを取得
  if command -v brew >/dev/null 2>&1; then
    asdf_brew_prefix=$(brew --prefix asdf 2>/dev/null || echo "/opt/homebrew/opt/asdf")
    asdf_init_script="${asdf_brew_prefix}/libexec/asdf.sh"
  else
    asdf_init_script="${HOME}/.asdf/asdf.sh"
  fi

  # シェル設定ファイルを決定（zshの場合）
  if [ -n "${ZSH_VERSION:-}" ]; then
    shell_config="${HOME}/.zshrc"
  elif [ -n "${BASH_VERSION:-}" ]; then
    shell_config="${HOME}/.bashrc"
  else
    shell_config="${HOME}/.zshrc"
  fi

  # 既に設定されているか確認
  if [ -f "${shell_config}" ] && grep -q "asdf環境変数の設定" "${shell_config}" 2>/dev/null; then
    echo "✅ 環境変数は既に${shell_config}に設定されています。"
    return 0
  fi

  echo "📦 環境変数を${shell_config}に追加しています..."

  # シェル設定ファイルが存在しない場合は作成
  if [ ! -f "${shell_config}" ]; then
    touch "${shell_config}"
  fi

  # 環境変数を追加
  {
    echo ""
    echo "# asdf環境変数の設定"
    if [ -f "${asdf_init_script}" ]; then
      echo ". ${asdf_init_script}"
    else
      echo "# asdf初期化スクリプトが見つかりません: ${asdf_init_script}"
      echo "export PATH=\"\${HOME}/.asdf/shims:\${PATH}\""
    fi
    echo "export ANSIBLE_PYTHON_INTERPRETER=\"\${HOME}/.asdf/shims/python3\""
  } >> "${shell_config}"

  echo "✅ 環境変数の設定が完了しました。"
  echo "   次回のターミナル起動時から有効になります。"
  
  # 現在のシェルセッションにも環境変数を設定（スクリプト実行中のみ有効）
  if [ -f "${asdf_init_script}" ]; then
    # shellcheck source=/dev/null
    . "${asdf_init_script}"
    echo "   現在のシェルセッションにもasdfを読み込みました。"
  else
    ensure_asdf_in_path
  fi
  export ANSIBLE_PYTHON_INTERPRETER="${HOME}/.asdf/shims/python3"
  
  echo "   注意: スクリプト終了後も継続するには、以下を実行してください:"
  echo "   source ${shell_config}"
}

########################################################
# メイン処理
########################################################
main() {
  setup_sudo
  check_homebrew
  install_xcode_command_line_tools
  install_asdf
  install_python
  install_ansible
  install_ansible_collections
  setup_environment_variables

  # 完了メッセージ
  echo ""
  echo "=========================================="
  echo "  ブートストラップが完了しました！ 🎉"
  echo "=========================================="
  echo ""
  echo "インストール済み:"
  echo "  ✅ asdf"
  echo "  ✅ Python (asdf経由)"
  echo "  ✅ Ansible"
  echo "  ✅ Ansible Collections"
  echo "  ✅ 環境変数の設定"
  echo ""
  echo "📝 注意:"
  echo "   このスクリプトは子プロセスで実行されているため、"
  echo "   スクリプト終了後も環境変数を継続するには、以下を実行してください:"
  echo ""
  echo "   source ~/.zshrc"
  echo ""
  echo "   または、次回ターミナル起動時から自動的に有効になります。"
  echo ""
  echo "次のステップ:"
  echo "  1. 環境変数を反映: source ~/.zshrc"
  echo "  2. 以下を実行: make provision"
  echo ""
}

main
