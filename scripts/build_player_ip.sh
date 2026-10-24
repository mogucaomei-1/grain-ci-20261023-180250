#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

GH_BIN="/Users/a1/.local/bin/gh"
REPO="mogucaomei-1/grain-ci-20261023-180250"
WORKFLOW_ID="395183104"

echo "==> 1. 推送代码至远程仓库..."
git push origin main || true
git push ci-180250 main || true

echo "==> 2. 触发 GitHub Actions 编译流水线 (Build Unsigned Player IPA)..."
TRIGGER_OUTPUT=$("$GH_BIN" workflow run "$WORKFLOW_ID" --repo "$REPO" --ref main)
echo "$TRIGGER_OUTPUT"

# 获取最新触发的 run id
RUN_ID=""
for i in {1..10}; do
  sleep 3
  RUN_ID=$("$GH_BIN" run list --workflow=build-unsigned-player-ipa.yml --repo "$REPO" --limit 1 --json databaseId --jq '.[0].databaseId')
  if [[ -n "$RUN_ID" && "$RUN_ID" != "null" ]]; then
    break
  fi
done

if [[ -z "$RUN_ID" || "$RUN_ID" == "null" ]]; then
  echo "错误：未能获取到构建 Run ID" >&2
  exit 1
fi

echo "==> 3. 正在等待云端 macOS Xcode 编译构建 (Run ID: $RUN_ID)..."
"$GH_BIN" run watch "$RUN_ID" --repo "$REPO" --exit-status

echo "==> 4. 下载编译产物..."
TMP_DIR=$(mktemp -d /tmp/grain-player-build.XXXXXX)
"$GH_BIN" run download "$RUN_ID" --repo "$REPO" --dir "$TMP_DIR"

# 计算 Build 序号
BUILD_NUM=1
while [[ -d "$ROOT_DIR/outputs/GRAINPlayer-build$BUILD_NUM" ]]; do
  BUILD_NUM=$((BUILD_NUM + 1))
done

OUT_DIR="$ROOT_DIR/outputs/GRAINPlayer-build$BUILD_NUM"
mkdir -p "$OUT_DIR/GRAINPlayer-unsigned-archive-log"

IP_SRC=$(find "$TMP_DIR" -name "*.ip" -o -name "*.ipa" | head -n 1)
LOG_SRC=$(find "$TMP_DIR" -name "archive.log" | head -n 1)

TARGET_IP_NAME="GRAINPlayer-1.0-build${BUILD_NUM}-unsigned.ip"

cp "$IP_SRC" "$OUT_DIR/$TARGET_IP_NAME"
cp "$IP_SRC" "$ROOT_DIR/outputs/$TARGET_IP_NAME"
mkdir -p "/Users/a1/.gemini/antigravity/scratch"
cp "$IP_SRC" "/Users/a1/.gemini/antigravity/scratch/$TARGET_IP_NAME"

if [[ -f "$LOG_SRC" ]]; then
  cp "$LOG_SRC" "$OUT_DIR/GRAINPlayer-unsigned-archive-log/archive.log"
fi

cd "$OUT_DIR"
shasum -a 256 "$TARGET_IP_NAME" > "$TARGET_IP_NAME.sha256"
cp "$TARGET_IP_NAME.sha256" "$ROOT_DIR/outputs/$TARGET_IP_NAME.sha256"

rm -rf "$TMP_DIR"

echo "==> 构建成功！安装包输出路径："
echo "$OUT_DIR/$TARGET_IP_NAME"

echo "==> 5. 弹出存放目录..."
open "$OUT_DIR"
