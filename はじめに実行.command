#!/usr/bin/env bash
# OtoWeave — Mac用 初回セットアップ（ダブルクリック用）
#
# テスターはこのファイルを Finder で右クリック →「開く」するだけで、
# セットアップが最後まで進みます。ターミナルへの入力は要りません。
#
# 失敗しても画面は閉じずに残し、内容を setup_log_mac.txt に保存します。
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

LOG="$ROOT/setup_log_mac.txt"
LOCK_DIR="$ROOT/.setup_running.lock"

# 「固まったかな」と思ったテスターが二重に開くと、同じファイルを同時に
# 書き換えて両方とも壊れる。先に始まっている方を優先する。
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  OTHER_PID="$(cat "$LOCK_DIR/pid" 2>/dev/null || echo "")"
  if [ -n "$OTHER_PID" ] && kill -0 "$OTHER_PID" 2>/dev/null; then
    echo "=================================================="
    echo " すでにセットアップが動いています"
    echo "=================================================="
    echo ""
    echo "別のウィンドウで進行中です。そちらの画面をご覧ください。"
    echo "時間がかかっているだけのことが多いので、そのままお待ちください。"
    echo ""
    read -r -p "Enterキーを押すと、この画面だけ閉じます... " _
    exit 1
  fi
  # 前回が強制終了などで残しただけの目印。引き継ぐ。
  rm -rf "$LOCK_DIR"
  mkdir "$LOCK_DIR" 2>/dev/null || true
fi
echo "$$" > "$LOCK_DIR/pid" 2>/dev/null || true
trap 'rm -rf "$LOCK_DIR"' EXIT

# 受け取ったファイルに付く「検疫」の印を外し、実行できるようにする
xattr -dr com.apple.quarantine "$ROOT" >/dev/null 2>&1 || true
for f in "setup_mac.sh" "verify_setup_mac.sh" "run_otoweave.sh" \
         "distribution/setup_runtime_mac.sh" "distribution/download_models_mac.sh" \
         "OtoWeaveを起動.command"; do
  [ -f "$ROOT/$f" ] && chmod +x "$ROOT/$f" 2>/dev/null
done

echo "=================================================="
echo " OtoWeave セットアップ"
echo "=================================================="
echo ""
echo "このままお待ちください。次のことを自動で行います。"
echo ""
echo "  ・OtoWeave専用のPythonとffmpegを用意する"
echo "  ・必要なライブラリを入れる"
echo "  ・AIモデル（約5.3GB）をダウンロードする"
echo ""
echo "★ Wi-Fi に繋いだ状態で始めてください。"
echo "  回線によっては1〜2時間かかります。"
echo "  途中で止まっても、もう一度このファイルを開けば続きから再開します。"
echo ""
echo "  ※ 管理者パスワードの入力は必要ありません。"
echo "     もしパスワードを求められたら、それはOtoWeaveとは無関係です。"
echo ""

if [ ! -f "$ROOT/setup_mac.sh" ]; then
  echo "[エラー] setup_mac.sh が見つかりません。"
  echo "zip を展開したフォルダの中身が揃っているか確認してください。"
  echo ""
  read -r -p "Enterキーを押すと閉じます... " _
  exit 1
fi

bash "$ROOT/setup_mac.sh" 2>&1 | tee "$LOG"
STATUS="${PIPESTATUS[0]}"

echo ""
echo "=================================================="
if [ "$STATUS" = "0" ]; then
  echo " 準備ができました"
  echo "=================================================="
  echo ""
  echo "この画面は閉じてかまいません。"
  echo ""
  echo "アプリを使うときは、同じフォルダの"
  echo "「OtoWeaveを起動.command」をダブルクリックしてください。"
elif [ "$STATUS" = "2" ]; then
  echo " あと少しです"
  echo "=================================================="
  echo ""
  echo "導入は最後まで進みましたが、確認したい項目が残っています。"
  echo "上に出ている [NG] の行をご覧ください。"
  echo ""
  echo "もう一度このファイルをダブルクリックすると直ることが多いです。"
  echo "直らない場合は、同じフォルダにできた"
  echo "  setup_log_mac.txt"
  echo "を開発者に送ってください。"
else
  echo " 途中で止まりました"
  echo "=================================================="
  echo ""
  echo "多くの場合、もう一度このファイルを開くだけで先に進みます"
  echo "（済んだところはやり直しません）。"
  echo ""
  echo "それでも直らないときは、同じフォルダにできた"
  echo "  setup_log_mac.txt"
  echo "を開発者に送ってください。"
fi
echo ""
read -r -p "Enterキーを押すと閉じます... " _
