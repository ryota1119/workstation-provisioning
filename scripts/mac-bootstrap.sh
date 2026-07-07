#!/usr/bin/env bash
########################################################
# Macプロビジョニング用ブートストラップスクリプト
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
# - Ansibleコレクション
########################################################
set -euo pipefail

########################################################
# 設定
########################################################
readonly REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

########################################################
# ヘルパー関数
########################################################

# mise環境を有効化
ensure_mise_in_path() {
  export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:${HOME}/.local/share/mise/shims:${PATH}"

  if command -v mise >/dev/null 2>&1; then
    set +u
    eval "$(mise activate bash 2>/dev/null || mise activate zsh 2>/dev/null)" || true
    set -u
  fi
}

# mise.toml からPythonバージョンを取得
get_python_version() {
  local version
  version=$(awk -F'"' '/^python =/ { print $2; exit }' "${REPO_ROOT}/mise.toml")

  if [ -z "${version}" ]; then
    echo "❌ mise.toml からPythonバージョンを取得できません。" >&2
    return 1
  fi

  echo "${version}"
}

# group_vars/all.yml からPythonビルド依存を取得
get_python_build_dependencies() {
  awk '
    /# mise経由でPythonをビルドする際に必要/ { in_python_deps = 1; next }
    in_python_deps && /^$/ { exit }
    in_python_deps && /^  - / { sub(/^  - /, ""); print }
  ' "${REPO_ROOT}/group_vars/all.yml"
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

  echo "📦 Xcode Command Line Toolsのインストールを開始します..."
  xcode-select --install || true
  echo "ℹ️  表示されたGUIでインストールを完了してください。"
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
  local python_version
  python_version="$(get_python_version)"

  # Pythonのビルドに必要な依存パッケージをHomebrew経由でインストール
  local python_build_dependencies
  python_build_dependencies="$(get_python_build_dependencies | tr '\n' ' ')"
  if [ -n "${python_build_dependencies}" ]; then
    echo "📦 Pythonのビルドに必要な依存パッケージをインストールしています..."
    # パッケージ名はAnsible変数側で管理し、bootstrap側では同じ一覧を再利用する。
    # shellcheck disable=SC2086
    brew install ${python_build_dependencies}
  fi

  # mise経由で指定バージョンがインストールされているか確認
  if mise list python 2>/dev/null | grep -q "${python_version}"; then
    echo "✅ Python ${python_version} (mise) は既にインストール済みです。"
  else
    echo "📦 Python ${python_version}をmise経由でインストールしています..."
    # Apple Silicon環境でのビルドを確実にするため環境変数を設定
    export CPPFLAGS="-I/opt/homebrew/include"
    export LDFLAGS="-L/opt/homebrew/lib"
    export PKG_CONFIG_PATH="/opt/homebrew/lib/pkgconfig"
    mise use python@"${python_version}"
    echo "✅ Pythonのインストールが完了しました。"
  fi

  ensure_mise_in_path

  # pipを最新版にアップグレード
  echo "📦 pipをアップグレードしています..."
  mise exec python@"${python_version}" -- python3 -m ensurepip --upgrade 2>/dev/null || true
  mise exec python@"${python_version}" -- python3 -m pip install --upgrade pip
  echo "✅ pipの準備が完了しました (Python: $(mise exec python@"${python_version}" -- python3 --version))。"
}

########################################################
# Ansibleのインストール（mise Python環境にインストール）
########################################################
install_ansible() {
  local python_version
  python_version="$(get_python_version)"

  # Ansibleが正常に動作するか確認
  if mise exec python@"${python_version}" -- ansible --version >/dev/null 2>&1; then
    local ansible_version
    ansible_version=$(mise exec python@"${python_version}" -- ansible --version | head -n1)
    echo "✅ Ansibleは既にインストール済みです (${ansible_version})。"
    return 0
  fi

  # Ansibleが存在するが動作しない場合（Pythonバージョン変更など）
  if command -v ansible >/dev/null 2>&1; then
    echo "⚠️  Ansibleが見つかりましたが、正常に動作しません。再インストールします..."
  fi

  ensure_mise_in_path

  # 既存のAnsibleが~/.localにインストールされている場合は削除
  if mise exec python@"${python_version}" -- python3 -m pip show ansible 2>/dev/null | grep -q "Location:.*\.local"; then
    echo "📦 既存のAnsibleを~/.localから削除しています..."
    mise exec python@"${python_version}" -- python3 -m pip uninstall -y ansible ansible-core 2>/dev/null || true
  fi

  echo "📦 Ansibleをインストールしています..."
  # PIP_USER=falseを設定して、mise Python環境に直接インストール
  # --force-reinstallで既存のパッケージを再インストール
  PIP_USER=false mise exec python@"${python_version}" -- python3 -m pip install --force-reinstall ansible

  # インストール確認（少し待ってから確認）
  sleep 1
  if mise exec python@"${python_version}" -- ansible --version >/dev/null 2>&1; then
    local ansible_version
    ansible_version=$(mise exec python@"${python_version}" -- ansible --version | head -n1)
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
  local python_version
  python_version="$(get_python_version)"

  if [ ! -f requirements.yml ]; then
    echo "⚠️  requirements.ymlが見つかりません。collection のインストールをスキップします。"
    return 0
  fi

  # ansible-galaxyが正常に動作するか確認
  if ! mise exec python@"${python_version}" -- ansible-galaxy --version >/dev/null 2>&1; then
    echo "❌ ansible-galaxyが正常に動作しません。Ansibleの再インストールが必要です。"
    return 1
  fi

  echo "📦 Ansible collectionsをインストールしています..."
  if ! mise exec python@"${python_version}" -- ansible-galaxy collection install -r requirements.yml; then
    echo "❌ Ansible collectionsのインストールに失敗しました。" >&2
    return 1
  fi
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
