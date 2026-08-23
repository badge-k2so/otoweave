#!/usr/bin/env bash
# OtoWeave — macOS (Apple Silicon / Intel) 初回セットアップ
#
# このフォルダの中だけで完結する実行環境を作ります。
# Homebrew・管理者パスワード・Xcode のいずれも必要ありません。
#
# 実行方法（どちらでも同じです）:
#   Finder で「はじめに実行.command」を右クリック →「開く」
#   ターミナルで  ./setup_mac.sh
#
# 用意するもの:
#   runtime/python/   専用のPython 3.12（tkinter同梱）
#   engines/ffmpeg/   単体で動くffmpeg
#   .venv/            上の専用Pythonから作る作業用環境
#   models/ hf-cache/ AIモデル本体（約5.3GB）
#
# 完了すると、最後に verify_setup_mac.sh が自動で実行され、
# 「起動する前に何が足りないか」を日本語で表示します。
#
# 注意: macOS の /bin/bash は 3.2 系のため bash 4 以降の機能は使わない。
#       日本語（全角文字）の直前の変数は必ず ${VAR} と波かっこで囲む
#       （macOS の bash は「$VAR（」を1つの変数名として読んでしまう）。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

PYTHON_HOME="$ROOT/runtime/python"
RUNTIME_PYTHON="$PYTHON_HOME/bin/python3.12"
VENV_PYTHON="$ROOT/.venv/bin/python"

# AI要約・チャット用エンジンの事前ビルド済みファイル置き場。
# .github/workflows/build-mac-llama-wheel.yml が作って、ここに置きます。
WHEEL_REPO="badge-k2so/otoweave"
WHEEL_TAG="mac-wheels-v1"

# 日本語文字起こしエンジン（PyPI未公開）の取得元。実機で動作確認済みの版。
REAZON_COMMIT="2d4d4762e7ee294ac8e47a177ac2e9b0e8d0d43f"

TOTAL_STEPS=7
LLAMA_OK=0

step() {
  echo ""
  echo "==> [$1/${TOTAL_STEPS}] $2"
}

fail() {
  echo "" >&2
  echo "==================================================" >&2
  echo "[エラー] $1" >&2
  echo "==================================================" >&2
  echo "" >&2
  echo "この画面をそのまま（写真かコピーで）開発者に送ってください。" >&2
  exit 1
}

warn_box() {
  echo "" >&2
  echo "--------------------------------------------------------" >&2
  echo "[お知らせ] $1" >&2
  echo "--------------------------------------------------------" >&2
  echo "" >&2
}

# ---------------------------------------------------------------------------
step 1 "お使いのMacを確認しています"

OS_NAME="$(uname -s)"
ARCH_NAME="$(uname -m)"
if [ "$OS_NAME" != "Darwin" ]; then
  fail "このスクリプトは macOS 専用です（検出したOS: ${OS_NAME}）。"
fi

# 専用Python も事前ビルド済みのエンジンも macOS 11 以降向け。
# 古いMacでは分かりにくい失敗をするより、先に理由を伝えて止める。
OS_VERSION="$(sw_vers -productVersion 2>/dev/null || echo "")"
OS_MAJOR="${OS_VERSION%%.*}"
if [ -n "$OS_MAJOR" ] && [ "$OS_MAJOR" -lt 11 ] 2>/dev/null; then
  fail "このMacの macOS ${OS_VERSION} には対応していません。
OtoWeave は macOS 11（Big Sur）以降で動きます。
macOS を更新できるか、別のMacをお持ちかを開発者にお知らせください。"
fi

if [ "$ARCH_NAME" = "arm64" ]; then
  echo "   Apple Silicon (arm64) のMacです。AIの処理にGPUを使えます。"
else
  echo "   Intel (${ARCH_NAME}) のMacです。動作しますが、要約・チャットは少し遅くなります。"
fi

# インターネットから受け取ったファイルには macOS が「検疫」の印を付けるため、
# そのままでは実行できないことがある。このフォルダの分をまとめて外す。
xattr -dr com.apple.quarantine "$ROOT" >/dev/null 2>&1 || true

# ---------------------------------------------------------------------------
step 2 "専用のPythonとffmpegを用意しています（約70MB）"

[ -f "$ROOT/distribution/setup_runtime_mac.sh" ] \
  || fail "distribution/setup_runtime_mac.sh が見つかりません。
zip を展開したフォルダの中身が揃っているか確認してください。"

bash "$ROOT/distribution/setup_runtime_mac.sh" \
  || fail "実行環境（Python・ffmpeg）の用意に失敗しました。
Wi-Fi に繋がっているか確認して、もう一度実行してください（続きから再開します）。"

[ -x "$RUNTIME_PYTHON" ] || fail "専用Python が見つかりません（${RUNTIME_PYTHON}）。"

# ---------------------------------------------------------------------------
step 3 "作業用の環境 (.venv) を作っています"

# 古い版の setup_mac.sh は Homebrew の Python から .venv を作っていた。
# それが残っていると tkinter が無いまま起動して失敗するので、専用Python
# 以外から作られた .venv は作り直す。
NEED_VENV=1
if [ -x "$VENV_PYTHON" ]; then
  CURRENT_BASE="$("$VENV_PYTHON" -c 'import sys; print(sys.base_prefix)' 2>/dev/null || echo "")"
  if [ "$CURRENT_BASE" = "$PYTHON_HOME" ]; then
    NEED_VENV=0
    echo "   既にある .venv をそのまま使います。"
  else
    echo "   以前の .venv は別のPythonから作られていたため、作り直します。"
    rm -rf "$ROOT/.venv"
  fi
fi
if [ "$NEED_VENV" = "1" ]; then
  "$RUNTIME_PYTHON" -m venv "$ROOT/.venv" || fail ".venv の作成に失敗しました。"
fi

# shellcheck disable=SC1091
source "$ROOT/.venv/bin/activate"

# 画面表示に必要な tkinter が本当に使えるか、ここで確かめておく
python -c "import tkinter" >/dev/null 2>&1 \
  || fail "画面表示に必要な部品（tkinter）が使えませんでした。
runtime フォルダを削除してから、もう一度実行してください。"

# ---------------------------------------------------------------------------
step 4 "必要なライブラリを入れています（数分かかります）"

python -m pip install --upgrade pip wheel >/dev/null \
  || fail "pip の更新に失敗しました。Wi-Fi に繋がっているか確認してください。"

pip install -r requirements_mac.txt || fail "ライブラリの導入に失敗しました。
Wi-Fi に繋がっているか確認して、もう一度実行してください。"

# ---------------------------------------------------------------------------
step 5 "AI要約・チャット用エンジンを入れています"

# まずは事前ビルド済みのファイル（wheel）を探す。見つかれば数十秒で終わり、
# Xcode も要らない。無ければその場で組み立て、それも無理なら要約・チャット
# 抜きで続行する（録音・文字起こし・読み上げはそのまま使える）。
if [ "$ARCH_NAME" = "arm64" ]; then
  WHEEL_ARCH="arm64"
else
  WHEEL_ARCH="x86_64"
fi
LLAMA_WHEEL_URL="$(
  curl -fsSL --max-time 30 \
    "https://api.github.com/repos/${WHEEL_REPO}/releases/tags/${WHEEL_TAG}" 2>/dev/null \
    | grep -o '"browser_download_url": *"[^"]*"' \
    | sed 's/.*"browser_download_url": *"//; s/"$//' \
    | grep "macosx_" \
    | grep "${WHEEL_ARCH}\.whl$" \
    | head -1 || true
)"

if [ -n "$LLAMA_WHEEL_URL" ] && pip install "$LLAMA_WHEEL_URL"; then
  echo "   完了: 事前ビルド済みのエンジンを使いました。"
  LLAMA_OK=1
elif xcode-select -p >/dev/null 2>&1; then
  echo "   事前ビルド済みのファイルが無かったため、この場で組み立てます（数分かかります）。"
  if [ "$ARCH_NAME" = "arm64" ]; then
    if CMAKE_ARGS="-DGGML_METAL=on" pip install llama-cpp-python --no-binary llama-cpp-python; then
      LLAMA_OK=1
    fi
  else
    if pip install llama-cpp-python; then
      LLAMA_OK=1
    fi
  fi
fi

if [ "$LLAMA_OK" != "1" ]; then
  warn_box "AI要約・AIチャットは、このMacでは使えない状態です。
  録音・文字起こし・読み上げ・話者の推定は、このまま問題なく使えます。
  要約とチャットも使いたい場合は開発者に連絡してください
  （このMac向けの部品を用意してお渡しします）。
  セットアップはこのまま続けます。"
fi

# ---------------------------------------------------------------------------
step 6 "日本語の文字起こしエンジンを入れています"

# git+https:// の形式は git コマンドを必要とし、Xcode Command Line Tools が
# 入っていないMacでは失敗する（しかもインストールを促す画面が勝手に出る）。
# git を使わずに済む書庫URLから入れる。REAZON_COMMIT は動作確認が取れている
# 版で、ここを書き換えれば追従できる。
REAZON_ARCHIVE="https://github.com/reazon-research/ReazonSpeech/archive/${REAZON_COMMIT}.tar.gz#subdirectory=pkg/k2-asr"
if pip install "$REAZON_ARCHIVE"; then
  echo "   完了: 日本語の文字起こしエンジンを入れました。"
elif xcode-select -p >/dev/null 2>&1 \
  && pip install "git+https://github.com/reazon-research/ReazonSpeech.git#subdirectory=pkg/k2-asr"; then
  echo "   完了: 日本語の文字起こしエンジンを入れました。"
else
  warn_box "日本語のリアルタイム文字起こしが使えない状態です。
  （英語の文字起こし・要約・チャット・読み上げは、この件と関係なく動きます）
  もう一度 ./setup_mac.sh を実行すると直ることがあります。
  直らない場合は開発者に連絡してください。
  セットアップはこのまま続けます。"
fi

# ---------------------------------------------------------------------------
step 7 "AIモデルをダウンロードしています（約5.3GB・初回のみ）"

echo "   回線によっては1時間以上かかります。Wi-Fi に繋いだままにしてください。"
echo "   途中で止まっても、もう一度実行すれば続きから再開します。"

if [ -f "$ROOT/distribution/download_models_mac.sh" ]; then
  bash "$ROOT/distribution/download_models_mac.sh" || fail "AIモデルのダウンロードに失敗しました。
Wi-Fi に繋がっているか確認して、もう一度実行してください（続きから再開します）。"
else
  echo "   distribution/download_models_mac.sh が見つかりませんでした（スキップします）。" >&2
fi

if [ -f "$ROOT/OtoWeaveを起動.command" ]; then
  chmod +x "$ROOT/OtoWeaveを起動.command" || true
fi

# ---------------------------------------------------------------------------
echo ""
echo "==> 仕上げの確認をしています"
VERIFY_STATUS=0
if [ -f "$ROOT/verify_setup_mac.sh" ]; then
  bash "$ROOT/verify_setup_mac.sh" || VERIFY_STATUS=$?
else
  echo "   verify_setup_mac.sh が見つかりませんでした（スキップします）。" >&2
fi

echo ""
if [ "$VERIFY_STATUS" = "0" ]; then
  echo "=================================================="
  echo "セットアップが終わりました。"
  if [ "$LLAMA_OK" != "1" ]; then
    echo ""
    echo "※ ただし AI要約・AIチャットは使えない状態です。"
    echo "   録音・文字起こし・読み上げは使えます。"
    echo "   要約とチャットも使いたい場合は開発者にご連絡ください。"
  fi
  echo ""
  echo "起動するには:"
  echo "  Finder で「OtoWeaveを起動.command」をダブルクリック"
  echo "=================================================="
  exit 0
fi

# 導入自体は最後まで進んだが、確認で [NG] が残っている状態。
# 「はじめに実行.command」がこの 2 を見分けて案内を変える。
echo "=================================================="
echo "セットアップは最後まで進みましたが、確認したい項目が残っています。"
echo ""
echo "上に出ている [NG] の行を見てください。多くの場合、もう一度"
echo "「はじめに実行.command」を開くだけで解決します。"
echo "=================================================="
exit 2
