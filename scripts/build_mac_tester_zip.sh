#!/usr/bin/env bash
# OtoWeave — Mac テスター配布用 zip の作成
#
# mac-port-m2 ブランチの内容から、テスターにそのまま渡せる zip を作ります。
# AIモデルは同梱しません（setup_mac.sh が公開配布元から自動取得するため）。
# 出来上がる zip は数MB程度で、メールや通常のファイル便で送れます。
#
# 使い方（リポジトリのルートで）:
#   ./scripts/build_mac_tester_zip.sh                 # 今チェックアウト中の内容から
#   ./scripts/build_mac_tester_zip.sh mac-port-m2     # ブランチ/タグを指定
#
# 出力: dist/OtoWeave-mac-<ブランチ名>-<日付>.zip
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

REF="${1:-HEAD}"
STAMP="$(date '+%Y%m%d')"
if [ "$REF" = "HEAD" ]; then
  SAFE_REF="$(git rev-parse --abbrev-ref HEAD | tr '/' '-')"
else
  SAFE_REF="$(printf '%s' "$REF" | tr '/' '-')"
fi
NAME="OtoWeave-mac-${SAFE_REF}-${STAMP}"
OUT_DIR="$ROOT/dist"
STAGE="$OUT_DIR/$NAME"
ZIP_PATH="$OUT_DIR/${NAME}.zip"

command -v git >/dev/null 2>&1 || { echo "[エラー] git が見つかりません。" >&2; exit 1; }
command -v zip >/dev/null 2>&1 || { echo "[エラー] zip が見つかりません。" >&2; exit 1; }

git rev-parse --verify "$REF" >/dev/null 2>&1 \
  || { echo "[エラー] '$REF' というブランチ/タグが見つかりません。" >&2; exit 1; }

echo "==> $REF の内容を取り出しています"
rm -rf "$STAGE" "$ZIP_PATH"
mkdir -p "$STAGE"
# 作業ツリーの変更やビルド生成物を混ぜないよう、必ず git の内容から作る
git archive "$REF" | tar -x -C "$STAGE"

echo "==> 配布に不要なファイルを除いています"
# 開発専用・Windows専用でテスターが触らないものを外す
rm -rf \
  "$STAGE/scripts/benchmarks" \
  "$STAGE/scripts/prototypes" \
  "$STAGE/tests" \
  "$STAGE/prompts" \
  "$STAGE/MAC_PORT_PLAN.md" \
  "$STAGE/PROJECT_RECORD.md" \
  "$STAGE/docs/images"
# Windows専用のセットアップ資材（Mac版テスターの誤操作を防ぐ）
rm -f \
  "$STAGE/setup_otoweave.ps1" \
  "$STAGE/run_otoweave.ps1" \
  "$STAGE/distribution/setup.bat" \
  "$STAGE/distribution/setup_easy.ps1" \
  "$STAGE/distribution/setup_test_pc.ps1" \
  "$STAGE/distribution/build_distribution.ps1" \
  "$STAGE/distribution/download_9b_model.ps1" \
  "$STAGE/distribution/verify_offline.ps1" \
  "$STAGE/distribution/verify_setup.py" \
  "$STAGE/distribution/OtoWeaveを起動.bat" \
  "$STAGE/distribution/はじめにお読みください.txt" \
  "$STAGE/distribution/requirements_dist.txt"

echo "==> 実行権限を付け直しています"
# zip は実行ビットを保持するが、git archive 経由でも確実にしておく。
# 指定refに未導入のファイルがあっても止めない（古いブランチからも作れるように）。
for f in \
  "setup_mac.sh" \
  "verify_setup_mac.sh" \
  "run_otoweave.sh" \
  "distribution/download_models_mac.sh" \
  "OtoWeaveを起動.command"
do
  if [ -f "$STAGE/$f" ]; then
    chmod +x "$STAGE/$f"
  else
    echo "   [注意] $f がこのrefに含まれていません" >&2
  fi
done

echo "==> テスター向けの入口ファイルを置いています"
cp "$STAGE/distribution/docs/Macテスト手順書.md" "$STAGE/はじめにお読みください（Mac）.md"

echo "==> zip を作成しています"
cd "$OUT_DIR"
# -X: macOS の拡張属性やリソースフォークを入れない（余計な __MACOSX を避ける）
zip -q -r -X "${NAME}.zip" "$NAME"
cd "$ROOT"
rm -rf "$STAGE"

echo ""
echo "=================================================="
echo "完成しました:"
echo "  $ZIP_PATH"
echo "  サイズ: $(du -h "$ZIP_PATH" | cut -f1)"
echo ""
echo "AIモデル（約2.7GB）はこのzipには入っていません。"
echo "テスターのMacで ./setup_mac.sh を実行したときに自動で取得されます。"
echo "=================================================="
