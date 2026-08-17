#!/usr/bin/env bash
# OtoWeave launcher for macOS — double-click this file in Finder to start
# the app (no Terminal typing needed once setup is done).
#
# Mirrors distribution/OtoWeaveを起動.bat's role on Windows: a single
# double-clickable entry point that gives a plain-Japanese error and keeps
# the window open (instead of flashing closed) if something is missing.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

fail() {
  echo ""
  echo "=================================================="
  echo "[エラー] $1"
  echo "=================================================="
  echo ""
  echo "このウィンドウを閉じてよいか確認してから閉じてください。"
  read -r -p "Enterキーを押すと閉じます... " _
  exit 1
}

if [ ! -x ".venv/bin/python" ]; then
  fail "初回セットアップがまだです。
先に「setup_mac.sh」をダブルクリックするか、ターミナルで次を実行してください。

  ./setup_mac.sh"
fi

if [ ! -f "otoweave_app/main.py" ]; then
  fail "アプリ本体のファイルが見つかりません（otoweave_app フォルダ）。
OtoWeaveのフォルダ一式を、このフォルダとまとめて置いてから開き直してください。"
fi

export HF_HOME="$ROOT/hf-cache"
export HF_HUB_OFFLINE=1
export TRANSFORMERS_OFFLINE=1

if ! .venv/bin/python -m otoweave_app.main; then
  fail "OtoWeaveの起動中にエラーが発生しました。
上に表示された内容を記録し、開発者に連絡してください。"
fi
