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
先に、同じフォルダの「はじめに実行.command」を右クリック →「開く」で実行してください。"
fi

if [ ! -f "otoweave_app/main.py" ]; then
  fail "アプリ本体のファイルが見つかりません（otoweave_app フォルダ）。
OtoWeaveのフォルダ一式を、このフォルダとまとめて置いてから開き直してください。"
fi

# 画面表示の部品（tkinter）が無いまま起動すると、英語のトレースバックだけ出て
# 終わってしまう。先に確かめて、直し方を日本語で出す。
if ! .venv/bin/python -c "import tkinter" >/dev/null 2>&1; then
  fail "画面表示に必要な部品（tkinter）が入っていません。
同じフォルダの「はじめに実行.command」をもう一度開いてください
（済んでいるところはやり直しません）。"
fi

export HF_HOME="$ROOT/hf-cache"
export HF_HUB_OFFLINE=1
export TRANSFORMERS_OFFLINE=1

if ! .venv/bin/python -m otoweave_app.main; then
  fail "OtoWeaveの起動中にエラーが発生しました。
上に表示された内容を記録し、開発者に連絡してください。"
fi
