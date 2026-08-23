#!/usr/bin/env bash
# OtoWeave launcher for macOS (Apple Silicon / Intel).
#
# Usage:
#   ./run_otoweave.sh                 # normal launch
#   ./run_otoweave.sh --demo          # seed the demo lesson
#   ./run_otoweave.sh --data-root DIR # use a custom lesson storage folder
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

if [ ! -x ".venv/bin/python" ]; then
  echo "[エラー] .venv が見つかりません。先に ./setup_mac.sh を実行してください。" >&2
  exit 1
fi

# 画面表示の部品（tkinter）が使えないまま起動すると、英語のトレースバックが
# 出るだけで原因が分からない。先に確かめて、直し方を日本語で出す。
if ! .venv/bin/python -c "import tkinter" >/dev/null 2>&1; then
  echo "[エラー] 画面表示に必要な部品（tkinter）が見つかりません。" >&2
  echo "  「はじめに実行.command」をもう一度開く（または ./setup_mac.sh を実行する）と直ります。" >&2
  exit 1
fi

# Same idea as the Windows distribution's OtoWeaveを起動.bat: keep the
# HuggingFace cache local to this folder and never let libraries reach out
# to the network at runtime.
export HF_HOME="$ROOT/hf-cache"
export HF_HUB_OFFLINE=1

exec .venv/bin/python -m otoweave_app.main "$@"
