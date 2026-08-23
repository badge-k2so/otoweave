#!/usr/bin/env bash
# OtoWeave — macOS 用 実行環境（専用Python・ffmpeg）の取得
#
# Homebrew を使わずに、このフォルダの中だけで完結する実行環境を用意します。
# setup_mac.sh の中から自動で呼ばれます。単独でも実行できます:
#   ./distribution/setup_runtime_mac.sh
#
# ここで用意するもの:
#   runtime/python/       専用のPython 3.12（tkinter/Tcl-Tk 同梱・約25MB）
#   engines/ffmpeg/ffmpeg 単体で動くffmpeg（音声の変換・保存に使用）
#
# どちらも管理者パスワード・Xcode・Homebrew を必要としません。
# 配布元の公式ビルドをダウンロードし、SHA256 で中身を検証してから使います。
#
# 注意: macOS の /bin/bash は 3.2 系のため、連想配列など bash 4 以降の
#       機能は使わない。日本語（全角文字）の直前の変数は必ず ${VAR} と
#       波かっこで囲む（macOS の bash は「$VAR（」を1つの変数名として
#       読んでしまうため）。
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

RUNTIME_DIR="$ROOT/runtime"
PYTHON_HOME="$RUNTIME_DIR/python"
PYTHON_BIN="$PYTHON_HOME/bin/python3.12"
FFMPEG_BIN="$ROOT/engines/ffmpeg/ffmpeg"

# --- 取得するもの（版を上げるときは URL と SHA256 を必ず一緒に更新する）---
#
# Python: astral-sh/python-build-standalone の公式ビルド。
#   macOS 版は _tkinter と Tcl/Tk 9.0 を同梱しているため、Homebrew の
#   python-tk を別途入れる必要がない。バイナリは ad-hoc 署名済みで、
#   Apple Silicon でもそのまま実行できる。
PY_VERSION="3.12.14"
PY_TAG="20260814"
PY_URL_ARM64="https://github.com/astral-sh/python-build-standalone/releases/download/${PY_TAG}/cpython-${PY_VERSION}+${PY_TAG}-aarch64-apple-darwin-install_only.tar.gz"
PY_SHA_ARM64="4572133a5542f306b9bdb155da5800f9e38950cd0a98d469b832ce256fe299ea"
PY_URL_X86_64="https://github.com/astral-sh/python-build-standalone/releases/download/${PY_TAG}/cpython-${PY_VERSION}+${PY_TAG}-x86_64-apple-darwin-install_only.tar.gz"
PY_SHA_X86_64="1a94c83264731e9603fbea78e57e7ca8f20e7d91eb866627ac2304621b0f6f1f"
PY_MIN_BYTES=20000000

# ffmpeg: eugeneware/ffmpeg-static の macOS 向け単体バイナリ。
#   libopus を含む（録音の保存に必要）。こちらも ad-hoc 署名済み。
FFMPEG_TAG="b6.1.1"
FFMPEG_URL_ARM64="https://github.com/eugeneware/ffmpeg-static/releases/download/${FFMPEG_TAG}/ffmpeg-darwin-arm64"
FFMPEG_SHA_ARM64="a90e3db6a3fd35f6074b013f948b1aa45b31c6375489d39e572bea3f18336584"
FFMPEG_URL_X86_64="https://github.com/eugeneware/ffmpeg-static/releases/download/${FFMPEG_TAG}/ffmpeg-darwin-x64"
FFMPEG_SHA_X86_64="ebdddc936f61e14049a2d4b549a412b8a40deeff6540e58a9f2a2da9e6b18894"
FFMPEG_MIN_BYTES=30000000

ARCH_NAME="$(uname -m)"
if [ "$ARCH_NAME" = "arm64" ]; then
  PY_URL="$PY_URL_ARM64"
  PY_SHA="$PY_SHA_ARM64"
  FFMPEG_URL="$FFMPEG_URL_ARM64"
  FFMPEG_SHA="$FFMPEG_SHA_ARM64"
else
  PY_URL="$PY_URL_X86_64"
  PY_SHA="$PY_SHA_X86_64"
  FFMPEG_URL="$FFMPEG_URL_X86_64"
  FFMPEG_SHA="$FFMPEG_SHA_X86_64"
fi

info() { echo "   $*"; }

die() {
  echo "" >&2
  echo "==================================================" >&2
  echo "[エラー] $1" >&2
  echo "==================================================" >&2
  exit 1
}

file_size() {
  if [ -f "$1" ]; then
    stat -f%z "$1" 2>/dev/null || wc -c < "$1" 2>/dev/null || echo 0
  else
    echo 0
  fi
}

sha256_of() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" 2>/dev/null | awk '{print $1}'
  else
    sha256sum "$1" 2>/dev/null | awk '{print $1}'
  fi
}

# download_verified <url> <dest> <sha256> <min_bytes> <label>
# 途中で止まっても、もう一度実行すれば続きから再開する（curl -C -）。
download_verified() {
  local url="$1" dest="$2" want="$3" min="$4" label="$5"
  local actual
  mkdir -p "$(dirname "$dest")"
  info "取得中: ${label}"
  if ! curl -L --fail --retry 5 --retry-delay 5 -C - -o "$dest.part" "$url"; then
    # 既に全部取れている場合、サーバが「続きはもう無い」と返すため curl は
    # 失敗扱いになる。照合値まで合っていればそのまま採用する。
    if [ "$(sha256_of "$dest.part")" != "$want" ]; then
      # 途中まで取れた分は消さない。次回の curl -C - が続きから取得する。
      die "${label} のダウンロードが最後まで終わりませんでした。
Wi-Fi に繋がっているか確認して、もう一度実行してください（途中から再開します）。
入手元: ${url}"
    fi
  fi
  # ここから先は「最後まで取れたのに中身がおかしい」場合なので、
  # 残しておいても直らない。消してやり直させる。
  if [ "$(file_size "$dest.part")" -lt "$min" ] 2>/dev/null; then
    rm -f "$dest.part"
    die "${label} のダウンロードが不完全でした。もう一度実行してください。"
  fi
  actual="$(sha256_of "$dest.part")"
  if [ -n "$want" ] && [ "$actual" != "$want" ]; then
    rm -f "$dest.part"
    die "${label} のダウンロード内容が壊れています（照合値が一致しません）。
もう一度実行しても直らない場合は、この画面ごと開発者に連絡してください。
  期待した値: ${want}
  実際の値  : ${actual}"
  fi
  mv -f "$dest.part" "$dest"
  info "完了: ${label}"
}

# --- 専用Python -------------------------------------------------------------
# 版が変わったときに古いものを使い続けないよう、版番号まで見て判定する。
INSTALLED_PY_VERSION=""
if [ -x "$PYTHON_BIN" ]; then
  INSTALLED_PY_VERSION="$("$PYTHON_BIN" -c 'import platform; print(platform.python_version())' 2>/dev/null || echo "")"
fi
if [ "$INSTALLED_PY_VERSION" = "$PY_VERSION" ] && "$PYTHON_BIN" -c "import tkinter" >/dev/null 2>&1; then
  info "[済] 専用Python ${PY_VERSION} （既存のものを使用）"
else
  # 壊れた状態が残っていると原因が分かりにくいので、作り直す
  rm -rf "$PYTHON_HOME"
  mkdir -p "$RUNTIME_DIR"
  PY_ARCHIVE="$RUNTIME_DIR/python-${PY_VERSION}-${ARCH_NAME}.tar.gz"
  download_verified "$PY_URL" "$PY_ARCHIVE" "$PY_SHA" "$PY_MIN_BYTES" \
    "専用Python ${PY_VERSION}（約25MB）"
  info "展開しています..."
  # 書庫の中身は python/ から始まるため、runtime/ に展開すると
  # runtime/python/ になる
  if ! tar -xzf "$PY_ARCHIVE" -C "$RUNTIME_DIR"; then
    rm -rf "$PYTHON_HOME"
    die "専用Python の展開に失敗しました。ディスクの空き容量を確認してください。"
  fi
  rm -f "$PY_ARCHIVE"
  [ -x "$PYTHON_BIN" ] || die "専用Python の配置に失敗しました（${PYTHON_BIN} が見つかりません）。"
  if ! "$PYTHON_BIN" -c "import tkinter" >/dev/null 2>&1; then
    die "専用Python に画面表示の部品（tkinter）が入っていませんでした。
この画面ごと開発者に連絡してください。"
  fi
  info "完了: 専用Python ${PY_VERSION}"
fi

# --- ffmpeg -----------------------------------------------------------------
# 45MBの照合は1秒もかからないので毎回行う。壊れていた場合や、上の
# FFMPEG_TAG を上げた場合に、そのまま取り直せる。
if [ -x "$FFMPEG_BIN" ] && [ "$(sha256_of "$FFMPEG_BIN")" = "$FFMPEG_SHA" ]; then
  info "[済] ffmpeg （既存のものを使用）"
else
  download_verified "$FFMPEG_URL" "$FFMPEG_BIN" "$FFMPEG_SHA" "$FFMPEG_MIN_BYTES" \
    "ffmpeg（約45MB）"
  chmod +x "$FFMPEG_BIN"
fi

# ダウンロードしたものに検疫フラグが付いていると実行できないことがあるため外す
xattr -dr com.apple.quarantine "$PYTHON_HOME" "$FFMPEG_BIN" >/dev/null 2>&1 || true

if ! "$FFMPEG_BIN" -version >/dev/null 2>&1; then
  die "ffmpeg を実行できませんでした（${FFMPEG_BIN}）。
この画面ごと開発者に連絡してください。"
fi

exit 0
