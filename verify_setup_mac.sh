#!/usr/bin/env bash
# OtoWeave (macOS / Apple Silicon・Intel) セットアップ検証。
#
# setup_mac.sh の最後に自動実行されます。単独でも実行できます:
#   ./verify_setup_mac.sh
#
# Windows版 distribution/verify_setup.py と同じ考え方: 依存ライブラリの
# import・モデルファイルの有無・読み上げ音声・マイクなどを確認し、
# 「起動する前に何が足りないか」を [OK]/[NG] の一覧で日本語表示します。
# 結果は同じフォルダの setup_report_mac.txt にも保存します。
set -uo pipefail   # -e はあえて外す: 1項目の失敗で全体を止めないため

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

if [ -x ".venv/bin/python" ]; then
  PY="$ROOT/.venv/bin/python"
else
  PY="python3"
fi

REPORT="$ROOT/setup_report_mac.txt"
LINES=()
OK_COUNT=0
NG_COUNT=0

log() {
  LINES+=("$1")
  echo "$1"
}

check() {
  # check "表示名" <0=OK/他=NG> ["補足"]
  local label="$1" code="$2" detail="${3:-}"
  if [ "$code" -eq 0 ]; then
    OK_COUNT=$((OK_COUNT + 1))
    log "[OK] $label"
  else
    NG_COUNT=$((NG_COUNT + 1))
    if [ -n "$detail" ]; then
      log "[NG] $label : $detail"
    else
      log "[NG] $label"
    fi
  fi
}

log "========================================================"
log "OtoWeave セットアップ検証 (macOS)"
log "実行日時: $(date '+%Y-%m-%d %H:%M:%S')"
log "========================================================"

# --- Python ---------------------------------------------------------------
PY_VER="$("$PY" -c 'import sys; print("%d.%d.%d" % sys.version_info[:3])' 2>/dev/null || echo "不明")"
PY_MAJMIN="$("$PY" -c 'import sys; print("%d.%d" % sys.version_info[:2])' 2>/dev/null || echo "")"
if [ "$PY_MAJMIN" = "3.12" ]; then
  check "Python $PY_VER" 0
else
  check "Python $PY_VER" 1 "3.12 が必要です。./setup_mac.sh を実行してください"
fi

# --- 専用Python / 画面表示 (tkinter) -----------------------------------------
# .venv は runtime/python（同梱の専用Python）から作られている必要がある。
# 古い版の setup_mac.sh が作った Homebrew 由来の .venv だと tkinter が無い。
BASE_PREFIX="$("$PY" -c 'import sys; print(sys.base_prefix)' 2>/dev/null || echo "")"
if [ "$BASE_PREFIX" = "$ROOT/runtime/python" ]; then
  check "専用Python（フォルダ内で完結）" 0
else
  check "専用Python（フォルダ内で完結）" 1 "別のPythonから作られた環境です（${BASE_PREFIX:-不明}）。「はじめに実行.command」をもう一度開くと作り直します"
fi

if "$PY" -c "import tkinter" >/dev/null 2>&1; then
  check "ライブラリ tkinter（画面表示）" 0
else
  check "ライブラリ tkinter（画面表示）" 1 "「はじめに実行.command」をもう一度開いてください（済んだところはやり直しません）"
fi

# --- ライブラリ -------------------------------------------------------------
MODULES=(
  "customtkinter:UI"
  "darkdetect:ダーク/ライト自動判定"
  "tkinterdnd2:ドラッグ＆ドロップ"
  "PIL:アイコン描画"
  "numpy:音声処理"
  "scipy:リサンプリング"
  "sounddevice:録音・再生"
  "soundfile:音声ファイル入出力"
  "librosa:音声解析"
  "sherpa_onnx:文字起こし・話者分離エンジン"
  "onnxruntime:言語判定エンジン"
  "huggingface_hub:モデル読み込み"
  "reazonspeech.k2.asr:日本語文字起こし"
)
for entry in "${MODULES[@]}"; do
  name="${entry%%:*}"
  purpose="${entry##*:}"
  if "$PY" -c "import $name" >/dev/null 2>&1; then
    check "ライブラリ ${name}（${purpose}）" 0
  else
    err="$("$PY" -c "import $name" 2>&1 | tail -1)"
    check "ライブラリ ${name}（${purpose}）" 1 "${err:0:100}"
  fi
done

# --- モデルファイル ---------------------------------------------------------
MODEL_FILES=(
  "英語ASR (Parakeet):models/sherpa-onnx-nemo-parakeet-tdt-0.6b-v2-int8/encoder.int8.onnx"
  "言語判定 (SpeechBrain):models/speechbrain-lang-id-voxlingua107-ecapa-onnx/lang-id-ecapa.onnx"
  "AIチャット (Qwen3.5-2B):models/Qwen3.5-2B-Q4_K_M.gguf"
  "話者分離 セグメンテーション:models/diarization/sherpa-onnx-pyannote-segmentation-3-0/model.onnx"
  "話者分離 話者埋め込み:models/diarization/3dspeaker_speech_eres2net_base_sv_zh-cn_3dspeaker_16k.onnx"
  "ffmpeg (engines同梱):engines/ffmpeg/ffmpeg"
)
for entry in "${MODEL_FILES[@]}"; do
  label="${entry%%:*}"
  relpath="${entry#*:}"
  if [ "$label" = "ffmpeg (engines同梱)" ]; then
    # engines/ffmpeg/ffmpeg は任意（brewのffmpegで代用できるため、後段で別途確認）
    continue
  fi
  if [ -f "$ROOT/$relpath" ]; then
    check "ファイル $label" 0
  else
    check "ファイル $label" 1 "${relpath} が見つかりません（「はじめに実行.command」をもう一度開くと、足りない分だけ取り直します）"
  fi
done

# 4B は macOS では 7.5GB 超の機種で取得する（llm_chat.py の
# _MACOS_SUMMARIZE_MIN_RAM_BYTES と同じしきい値）。実8GB Mac も対象。
MAC_4B_MIN_RAM=8053063680
RAM_BYTES_CHECK="$(sysctl -n hw.memsize 2>/dev/null || echo 0)"
if [ -f "$ROOT/models/Qwen3.5-4B-Q4_K_M.gguf" ]; then
  log "[OK] ファイル AI要約 (Qwen3.5-4B) : あり"
  OK_COUNT=$((OK_COUNT + 1))
elif [ "${RAM_BYTES_CHECK:-0}" -gt "$MAC_4B_MIN_RAM" ] 2>/dev/null; then
  log "[NG] ファイル AI要約 (Qwen3.5-4B) : なし（このMacでは要約が使えるはずです。「はじめに実行.command」をもう一度開いて取得してください）"
  NG_COUNT=$((NG_COUNT + 1))
else
  log "[--] ファイル AI要約 (Qwen3.5-4B) ※任意 : なし（このMacはメモリが少ないため正常です。チャットは2Bで動作します）"
fi

# --- ReazonSpeech K2 (HFキャッシュ) -----------------------------------------
HF_CHECK_OUT="$(HF_HOME="$ROOT/hf-cache" HF_HUB_OFFLINE=1 "$PY" - <<'PYEOF' 2>&1
from pathlib import Path
try:
    from huggingface_hub import snapshot_download
    model_dir = Path(snapshot_download("reazon-research/reazonspeech-k2-v2", local_files_only=True))
    encoder = model_dir / "encoder-epoch-99-avg-1.int8.onnx"
    print("OK" if encoder.is_file() else "MISSING")
    print(model_dir)
except Exception as exc:
    print("ERROR")
    print(str(exc)[:150])
PYEOF
)"
HF_STATUS="$(printf '%s\n' "$HF_CHECK_OUT" | head -1)"
HF_DETAIL="$(printf '%s\n' "$HF_CHECK_OUT" | tail -1)"
if [ "$HF_STATUS" = "OK" ]; then
  check "日本語ASR (ReazonSpeech K2, hf-cache)" 0
else
  check "日本語ASR (ReazonSpeech K2, hf-cache)" 1 "$HF_DETAIL （「はじめに実行.command」をもう一度開くと取り直します）"
fi

# --- ffmpeg -----------------------------------------------------------------
if command -v ffmpeg >/dev/null 2>&1 || [ -x "$ROOT/engines/ffmpeg/ffmpeg" ]; then
  check "ffmpeg" 0
else
  check "ffmpeg" 1 "「はじめに実行.command」をもう一度開いてください（engines/ffmpeg/ffmpeg を取り直します）"
fi

# --- 読み上げ (say -v Kyoko) -------------------------------------------------
if command -v say >/dev/null 2>&1 && say -v '?' 2>/dev/null | grep -qi 'kyoko'; then
  check "読み上げ用 日本語音声 (say -v Kyoko)" 0
else
  check "読み上げ用 日本語音声 (say -v Kyoko)" 1 \
    "システム設定 > アクセシビリティ > 読み上げコンテンツ > システムの声 で「Kyoko」（日本語）を追加してください"
fi

# --- マイク (sounddevice) ----------------------------------------------------
MIC_OUT="$("$PY" - <<'PYEOF' 2>&1
try:
    import sounddevice as sd
    devices = sd.query_devices()
    mics = [d for d in devices if d.get("max_input_channels", 0) > 0]
    print("OK:%d" % len(mics))
    for d in mics:
        print("  - %s" % d.get("name", "?"))
except Exception as exc:
    print("ERROR:%s" % str(exc)[:120])
PYEOF
)"
MIC_STATUS="$(printf '%s\n' "$MIC_OUT" | head -1)"
if [[ "$MIC_STATUS" == OK:* ]]; then
  count="${MIC_STATUS#OK:}"
  if [ "${count:-0}" -gt 0 ]; then
    check "マイク入力（${count}台検出）" 0
  else
    check "マイク入力" 1 "マイクが見つかりません（システム設定 > プライバシーとセキュリティ > マイク でターミナル/Pythonの許可を確認してください）"
  fi
else
  check "マイク入力" 1 "${MIC_STATUS#ERROR:}"
fi

# --- AI要約・チャット用エンジン（任意項目） -----------------------------------
# 無くても録音・文字起こし・読み上げは使えるため、[NG] ではなく [--] で扱う。
#
# GPUが使えるかは llama.cpp 本体に聞く。ファイル名で判定していた頃は、
# Metal を無効にしてビルドした Intel 版にも libggml-metal.dylib が同梱される
# ため「GPU有効」と誤表示していた。
LLAMA_GPU="$("$PY" -c 'import llama_cpp; print("yes" if llama_cpp.llama_supports_gpu_offload() else "no")' 2>/dev/null || echo "")"
case "$LLAMA_GPU" in
  yes)
    log "[OK] AI要約・チャット用エンジン（GPUで高速化されます）"
    OK_COUNT=$((OK_COUNT + 1))
    ;;
  no)
    log "[OK] AI要約・チャット用エンジン（CPUのみ — 要約に時間がかかります）"
    OK_COUNT=$((OK_COUNT + 1))
    ;;
  *)
    log "[--] AI要約・チャット用エンジン ※任意 : 未導入（録音・文字起こし・読み上げは使えます。要約とチャットを使いたい場合は開発者に連絡してください）"
    ;;
esac

# --- ディスク空き容量 ---------------------------------------------------------
FREE_GB="$(df -g "$ROOT" 2>/dev/null | tail -1 | awk '{print $4}')"
if [ -z "${FREE_GB:-}" ]; then
  FREE_KB="$(df -k "$ROOT" 2>/dev/null | tail -1 | awk '{print $4}')"
  if [ -n "${FREE_KB:-}" ]; then
    FREE_GB=$((FREE_KB / 1024 / 1024))
  fi
fi
if [ "${FREE_GB:-0}" -ge 2 ] 2>/dev/null; then
  check "ディスク空き容量（約${FREE_GB}GB）" 0
else
  check "ディスク空き容量（約${FREE_GB:-不明}GB）" 1 "2GB以上の空きを確保してください"
fi

log "--------------------------------------------------------"
if [ "$NG_COUNT" -eq 0 ]; then
  SUMMARY="すべてOKです。「OtoWeaveを起動.command」をダブルクリックすると始められます。"
else
  SUMMARY="NG ${NG_COUNT}件: 上の [NG] の行に書かれた対処をしてから起動してください。"
fi
log "$SUMMARY"

printf '%s\n' "${LINES[@]}" > "$REPORT"
echo "この結果を $(basename "$REPORT") に保存しました。"

if [ "$NG_COUNT" -eq 0 ]; then
  exit 0
else
  exit 1
fi
