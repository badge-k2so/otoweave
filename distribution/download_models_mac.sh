#!/usr/bin/env bash
# OtoWeave — macOS 用 AIモデル一括ダウンロード
#
# Windows版 distribution/setup_easy.ps1 の「5. AIモデルのダウンロード」と
# 同じ入手元・同じ配置先を macOS 向けに実装したものです。
# setup_mac.sh の中から自動で呼ばれます。単独でも実行できます:
#   ./distribution/download_models_mac.sh
#
# 特徴（Windows版と同じ）:
# - 既にあるファイルはサイズを検証してスキップ（再実行しても無駄がない）
# - 途中で止まっても、もう一度実行すれば続きから再開する（curl -C -）
# - 必須モデルの失敗は中断、任意モデルの失敗は警告のみで続行
#
# 注意: macOS の /bin/bash は 3.2 系のため、連想配列など bash 4 以降の
#       機能は使わない。
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

MODELS_DIR="$ROOT/models"
PARAKEET_DIR="$MODELS_DIR/sherpa-onnx-nemo-parakeet-tdt-0.6b-v2-int8"
SPEECHBRAIN_DIR="$MODELS_DIR/speechbrain-lang-id-voxlingua107-ecapa-onnx"
DIARIZATION_DIR="$MODELS_DIR/diarization"

if [ -x "$ROOT/.venv/bin/python" ]; then
  PY="$ROOT/.venv/bin/python"
else
  PY="python3"
fi

FAILED_OPTIONAL=()

info() { echo "   $*"; }

die() {
  echo "" >&2
  echo "==================================================" >&2
  echo "[エラー] $1" >&2
  echo "==================================================" >&2
  exit 1
}

# file_size <path> — ファイルサイズをバイトで返す（無ければ 0）
file_size() {
  if [ -f "$1" ]; then
    # BSD stat (macOS)。GNU stat の環境でも wc へフォールバックする
    stat -f%z "$1" 2>/dev/null || wc -c < "$1" 2>/dev/null || echo 0
  else
    echo 0
  fi
}

# valid_file <path> <min_bytes> — 存在し、かつ最低サイズを満たすか
valid_file() {
  local size
  size="$(file_size "$1")"
  [ "${size:-0}" -ge "$2" ] 2>/dev/null
}

# download <url> <dest> <min_bytes> <label>
download() {
  local url="$1" dest="$2" min="$3" label="$4"
  if valid_file "$dest" "$min"; then
    info "[済] $label （既存ファイルを使用）"
    return 0
  fi
  mkdir -p "$(dirname "$dest")"
  info "取得中: $label"
  if ! curl -L --fail --retry 5 --retry-delay 5 -C - -o "$dest.part" "$url"; then
    # 既に全部取れている場合、サーバが「続きはもう無い」と返すため curl は
    # 失敗扱いになる。中身が揃っていればそのまま採用する。
    if ! valid_file "$dest.part" "$min"; then
      # 途中まで取れた分は消さない。次回の curl -C - が続きから取得する。
      echo "[失敗] $label のダウンロードが最後まで終わりませんでした（入手元: ${url}）" >&2
      echo "       もう一度実行すると、途中から再開します。" >&2
      return 1
    fi
  fi
  if ! valid_file "$dest.part" "$min"; then
    echo "[失敗] $label のダウンロードが不完全です（$(file_size "$dest.part") バイト / 想定 $min バイト以上）" >&2
    return 1
  fi
  mv -f "$dest.part" "$dest"
  info "完了: $label"
  return 0
}

# note_optional_failure <label>
note_optional_failure() {
  FAILED_OPTIONAL+=("$1")
  echo "   [警告] $1 の取得に失敗しました（任意のモデルのため続行します）" >&2
}

echo "=================================================="
echo "AIモデルのダウンロード"
echo "=================================================="
echo "初回は合計 約5.3GB（メモリ8GB未満の機種では約2.7GB）を取得します。"
echo "回線によっては1時間以上かかることがあります。"
echo ""
echo "★ Wi-Fi に接続した状態で実行してください。"
echo "  スマホのテザリングやモバイル回線だと、通信量の上限に達したり"
echo "  高額な通信料がかかったりする場合があります。"
echo ""
echo "途中で止まった場合は、もう一度実行すれば続きから再開します。"
echo ""

# --- 搭載メモリ判定（4Bモデルを取得するか） --------------------------------
RAM_BYTES="$(sysctl -n hw.memsize 2>/dev/null || echo 0)"
# 7.5GB。Windows版の 11.5GB より低い理由は otoweave_app/llm_chat.py の
# _MACOS_SUMMARIZE_MIN_RAM_BYTES と同じ: Apple Silicon はユニファイド
# メモリで、要約はサブプロセスで実行して終了時に解放するため、8GB機でも
# 4B Q4（約2.6GB）を省メモリプロファイルで動かせる。
# アプリ側の判定と必ず一致させること（ズレると「4Bを落としたのに
# 要約が出ない」「要約は有効なのにファイルが無い」が起きる）。
RAM_THRESHOLD=8053063680
DOWNLOAD_4B=0
if [ "${RAM_BYTES:-0}" -gt "$RAM_THRESHOLD" ] 2>/dev/null; then
  DOWNLOAD_4B=1
  info "搭載メモリ: 約$((RAM_BYTES / 1024 / 1024 / 1024))GB — AI要約用の4Bモデルもダウンロードします。"
else
  if [ "${RAM_BYTES:-0}" -gt 0 ] 2>/dev/null; then
    info "搭載メモリ: 約$((RAM_BYTES / 1024 / 1024 / 1024))GB — 4Bモデルは取得しません。"
  else
    info "搭載メモリを取得できませんでした — 安全のため4Bモデルは取得しません。"
  fi
  info "（AI要約は「じゅんび中」表示になります。AIチャットは2Bでどの機種でも使えます）"
fi
if [ "$DOWNLOAD_4B" = "1" ]; then
  echo "   ※ 4Bモデルの分だけ、合計は約5.3GBになります。"
fi
echo ""

# --- 1. 英語ASR Parakeet（必須） --------------------------------------------
# URLは Windows版 setup_easy.ps1 と1文字ずつ一致させる（テストで照合している）
download \
  "https://huggingface.co/csukuangfj/sherpa-onnx-nemo-parakeet-tdt-0.6b-v2-int8/resolve/main/encoder.int8.onnx" \
  "$PARAKEET_DIR/encoder.int8.onnx" 629145600 "英語ASR Parakeet (encoder)" \
  || die "英語ASR Parakeet (encoder) の取得に失敗しました。
ネット接続を確認し、もう一度 ./setup_mac.sh を実行してください（続きから再開します）。"
download \
  "https://huggingface.co/csukuangfj/sherpa-onnx-nemo-parakeet-tdt-0.6b-v2-int8/resolve/main/decoder.int8.onnx" \
  "$PARAKEET_DIR/decoder.int8.onnx" 5242880 "英語ASR Parakeet (decoder)" \
  || die "英語ASR Parakeet (decoder) の取得に失敗しました。もう一度実行してください。"
download \
  "https://huggingface.co/csukuangfj/sherpa-onnx-nemo-parakeet-tdt-0.6b-v2-int8/resolve/main/joiner.int8.onnx" \
  "$PARAKEET_DIR/joiner.int8.onnx" 1048576 "英語ASR Parakeet (joiner)" \
  || die "英語ASR Parakeet (joiner) の取得に失敗しました。もう一度実行してください。"
download \
  "https://huggingface.co/csukuangfj/sherpa-onnx-nemo-parakeet-tdt-0.6b-v2-int8/resolve/main/tokens.txt" \
  "$PARAKEET_DIR/tokens.txt" 1024 "英語ASR Parakeet (tokens)" \
  || die "英語ASR Parakeet (tokens) の取得に失敗しました。もう一度実行してください。"

# --- 2. 言語判定 SpeechBrain（必須・zipを展開） ------------------------------
if valid_file "$SPEECHBRAIN_DIR/lang-id-ecapa.onnx.data" 83886080 \
  && valid_file "$SPEECHBRAIN_DIR/lang-id-ecapa.onnx" 512000 \
  && valid_file "$SPEECHBRAIN_DIR/labels.json" 100; then
  info "[済] 言語判定 SpeechBrain （既存ファイルを使用）"
else
  SB_TMP="$(mktemp -d)"
  if download \
    "https://github.com/badge-k2so/otoweave/releases/download/v0.1.0-beta/speechbrain-lang-id-voxlingua107-ecapa-onnx.zip" \
    "$SB_TMP/speechbrain.zip" 73400320 "言語判定 SpeechBrain (zip)"
  then
    unzip -q -o "$SB_TMP/speechbrain.zip" -d "$SB_TMP/extract" \
      || die "言語判定モデルの展開に失敗しました。"
    SB_SRC="$SB_TMP/extract"
    if [ ! -f "$SB_SRC/lang-id-ecapa.onnx" ]; then
      # zip内が1階層フォルダに包まれている場合に対応
      SB_INNER="$(find "$SB_TMP/extract" -mindepth 1 -maxdepth 1 -type d | head -1)"
      [ -n "$SB_INNER" ] && SB_SRC="$SB_INNER"
    fi
    mkdir -p "$SPEECHBRAIN_DIR"
    for f in lang-id-ecapa.onnx lang-id-ecapa.onnx.data labels.json; do
      cp -f "$SB_SRC/$f" "$SPEECHBRAIN_DIR/$f" \
        || die "言語判定モデルの $f が展開結果に見つかりませんでした。"
    done
    info "完了: 言語判定 SpeechBrain"
  else
    rm -rf "$SB_TMP"
    die "言語判定 SpeechBrain の取得に失敗しました。
ネット接続を確認し、もう一度 ./setup_mac.sh を実行してください。"
  fi
  rm -rf "$SB_TMP"
fi

# --- 3. 日本語ASR ReazonSpeech K2（必須・HuggingFaceキャッシュ） -------------
REAZON_FOUND="$(find "$ROOT/hf-cache" -name 'encoder-epoch-99-avg-1.int8.onnx' 2>/dev/null | head -1)"
if [ -n "$REAZON_FOUND" ]; then
  info "[済] 日本語ASR ReazonSpeech K2 v2 （既存ファイルを使用）"
else
  info "取得中: 日本語ASR ReazonSpeech K2 v2（HuggingFace, int8のみ・約153MB）"
  if ! HF_HOME="$ROOT/hf-cache" HF_HUB_OFFLINE=0 "$PY" - <<'PYEOF'
from huggingface_hub import snapshot_download

snapshot_download(
    "reazon-research/reazonspeech-k2-v2",
    allow_patterns=["*.int8.onnx", "tokens.txt"],
)
print("OK")
PYEOF
  then
    die "日本語ASR ReazonSpeech K2 v2 のダウンロードに失敗しました。
ネット接続を確認し、もう一度 ./setup_mac.sh を実行してください。"
  fi
  info "完了: 日本語ASR ReazonSpeech K2 v2"
fi

# --- 4. 話者分離モデル（任意） ------------------------------------------------
DIAR_SEG_DIR="$DIARIZATION_DIR/sherpa-onnx-pyannote-segmentation-3-0"
if valid_file "$DIAR_SEG_DIR/model.onnx" 5242880; then
  info "[済] 話者分離 pyannote segmentation （既存ファイルを使用）"
else
  DIAR_TMP="$(mktemp -d)"
  if download \
    "https://github.com/k2-fsa/sherpa-onnx/releases/download/speaker-segmentation-models/sherpa-onnx-pyannote-segmentation-3-0.tar.bz2" \
    "$DIAR_TMP/seg.tar.bz2" 5242880 "話者分離 pyannote segmentation (tar.bz2)"
  then
    mkdir -p "$DIAR_TMP/extract"
    if tar -xf "$DIAR_TMP/seg.tar.bz2" -C "$DIAR_TMP/extract"; then
      DIAR_FOUND="$(find "$DIAR_TMP/extract" -name 'model.onnx' | head -1)"
      if [ -n "$DIAR_FOUND" ]; then
        mkdir -p "$DIAR_SEG_DIR"
        cp -f "$DIAR_FOUND" "$DIAR_SEG_DIR/model.onnx"
        info "完了: 話者分離 pyannote segmentation"
      else
        note_optional_failure "話者分離 pyannote segmentation"
      fi
    else
      note_optional_failure "話者分離 pyannote segmentation"
    fi
  else
    note_optional_failure "話者分離 pyannote segmentation"
  fi
  rm -rf "$DIAR_TMP"
fi

download \
  "https://github.com/k2-fsa/sherpa-onnx/releases/download/speaker-recongition-models/3dspeaker_speech_eres2net_base_sv_zh-cn_3dspeaker_16k.onnx" \
  "$DIARIZATION_DIR/3dspeaker_speech_eres2net_base_sv_zh-cn_3dspeaker_16k.onnx" 31457280 \
  "話者分離 3D-Speaker embedding" \
  || note_optional_failure "話者分離 3D-Speaker embedding"

# --- 5. AIチャット / AI要約 の gguf（任意） -----------------------------------
download \
  "https://huggingface.co/unsloth/Qwen3.5-2B-GGUF/resolve/main/Qwen3.5-2B-Q4_K_M.gguf" \
  "$MODELS_DIR/Qwen3.5-2B-Q4_K_M.gguf" 1258291200 "AIチャット Qwen3.5-2B Q4_K_M" \
  || note_optional_failure "AIチャット Qwen3.5-2B Q4_K_M"

if [ "$DOWNLOAD_4B" = "1" ]; then
  download \
    "https://huggingface.co/unsloth/Qwen3.5-4B-GGUF/resolve/main/Qwen3.5-4B-Q4_K_M.gguf" \
    "$MODELS_DIR/Qwen3.5-4B-Q4_K_M.gguf" 2726297600 "AI要約 Qwen3.5-4B Q4_K_M" \
    || note_optional_failure "AI要約 Qwen3.5-4B Q4_K_M"
fi

echo ""
if [ "${#FAILED_OPTIONAL[@]}" -eq 0 ]; then
  echo "モデルのダウンロードがすべて完了しました。"
else
  echo "モデルのダウンロードが完了しました（任意モデル ${#FAILED_OPTIONAL[@]} 件は失敗）:"
  for label in "${FAILED_OPTIONAL[@]}"; do
    echo "  - $label"
  done
  echo "もう一度 ./setup_mac.sh を実行すると、失敗した分だけ再取得します。"
fi
