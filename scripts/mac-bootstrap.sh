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
# Pythonのバージョン
########################################################
PYTHON_VERSION=3.13.7

########################################################
# sudo権限の確認
########################################################
echo "🔐 このスクリプトには管理者権限が必要です。"
echo "パスワードを入力してください..."
sudo -v

# sudo権限の維持（バックグラウンドで60秒ごとに更新）
while true; do
  sudo -n true
  sleep 60
  kill -0 "$$" || exit
done 2>/dev/null &

########################################################
# Homebrewの確認
########################################################
check_homebrew() {
  # Homebrewのパスを確実に設定
  local brew_prefix
  # macOS前提: Homebrewのパスをアーキテクチャ（Apple Silicon/Intel）で分岐
  if [[ "$(uname)" == "Darwin" ]]; then
  if [[ "$(uname -m)" == "arm64" ]]; then
    brew_prefix="/opt/homebrew"
  else
    brew_prefix="/usr/local"
    fi
  else
    echo "❌ このスクリプトはmacOS専用です。" >&2
    exit 1
  fi

  # 現在のシェルに環境変数を設定（まだ設定されていない場合）
  if ! command -v brew >/dev/null 2>&1; then
    if [ -f "${brew_prefix}/bin/brew" ]; then
  eval "$(${brew_prefix}/bin/brew shellenv)"
    else
      echo "❌ Homebrewがインストールされていません。"
      echo "   手動でインストールしてください:"
      echo "   /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
      echo "   eval \"\$(/opt/homebrew/bin/brew shellenv)\"  # Apple Silicon Macの場合"
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
    return 0
  fi

  echo "📦 asdfをインストールしています..."
  brew install asdf
  echo "✅ asdfのインストールが完了しました。"
}

########################################################
# Python3/pipのインストール
########################################################
install_python() {
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

  # グローバルバージョンの設定（asdf経由を確実に使用）
  echo "📦 Python ${PYTHON_VERSION}をローカルバージョンに設定しています..."
  asdf set python ${PYTHON_VERSION}

  # asdfのshimを更新
  asdf reshim python

  # pipを最新版にアップグレード
  echo "📦 pipをアップグレードしています..."
  python3 -m ensurepip --upgrade 2>/dev/null || true
  python3 -m pip install --user --upgrade pip
  echo "✅ pipの準備が完了しました (Python: $(python3 --version))。"
}

########################################################
# Ansibleのインストール（userインストール）
########################################################
install_ansible() {
  # Ansibleが正常に動作するか確認（Pythonバージョン変更時の対応）
  if command -v ansible >/dev/null 2>&1 && ansible --version >/dev/null 2>&1; then
    local ansible_version=$(ansible --version | head -n1)
    echo "✅ Ansibleは既にインストール済みです (${ansible_version})。"
    return 0
  fi

  # Ansibleが存在するが動作しない場合（Pythonバージョン変更など）
  if command -v ansible >/dev/null 2>&1; then
    echo "⚠️  Ansibleが見つかりましたが、正常に動作しません。再インストールします..."
  fi

  echo "📦 Ansibleをインストールしています..."
  python3 -m pip install --user --upgrade ansible
  asdf reshim

  # インストール確認
  if ansible --version >/dev/null 2>&1; then
    echo "✅ Ansibleのインストールが完了しました ($(ansible --version | head -n1))。"
  else
    echo "❌ Ansibleのインストールに失敗しました。"
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
  if ! command -v ansible-galaxy >/dev/null 2>&1 || ! ansible-galaxy --version >/dev/null 2>&1; then
    echo "❌ ansible-galaxyが正常に動作しません。Ansibleの再インストールが必要です。"
    return 1
  fi

  echo "📦 Ansible collectionsをインストールしています..."
  ansible-galaxy collection install -r requirements.yml || true
  echo "✅ Ansible collectionsのインストールが完了しました。"
}

########################################################
# メイン処理
########################################################
check_homebrew
install_xcode_command_line_tools
install_asdf
install_python
install_ansible
install_ansible_collections

########################################################
# 完了メッセージ
########################################################
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
echo ""
echo "次のステップ:"
echo "  1. ターミナルを再起動するか、以下を実行: source ~/.zprofile"
echo "  2. 以下を実行: make provision"
echo ""
