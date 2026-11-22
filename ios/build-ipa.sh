#!/bin/bash
#
# 在 macOS 上构建未签名 IPA（需要安装 Xcode 或 Xcode Command Line Tools）
#
# 用法:
#   chmod +x build-ipa.sh
#   ./build-ipa.sh
#
# 产物:
#   build/LHJ-unsigned.ipa
#
# 之后用你自己的证书/描述文件重签，例如:
#   unzip LHJ-unsigned.ipa
#   ldid -Syour_entitlements.plist Payload/LHJ.app
#   # 或用 iOS App Signer / zsign / 企业签名工具重签后安装
#
# 没有 Mac 时，可以把整个 ios 目录推到 GitHub 仓库，
# 用 macos-14 的 GitHub Actions 执行本脚本并下载 Artifact（见文末注释）。

set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
GAME="$ROOT/Game"
OUT="$ROOT/build"
APP="$OUT/Payload/LHJ.app"

rm -rf "$OUT"
mkdir -p "$APP"

echo "==> 编译 Swift 源码 (arm64, iOS 13+)"
SDK_PATH="$(xcrun --sdk iphoneos --show-sdk-path)"
xcrun --sdk iphoneos swiftc \
    -target arm64-apple-ios13.0 \
    -sdk "$SDK_PATH" \
    -swift-version 5 \
    -O \
    -whole-module-optimization \
    -framework UIKit \
    -framework Foundation \
    -framework AVFoundation \
    -framework QuartzCore \
    "$GAME"/Sources/main.swift \
    "$GAME"/Sources/AppDelegate.swift \
    "$GAME"/Sources/GameModel.swift \
    "$GAME"/Sources/SoundPlayer.swift \
    "$GAME"/Sources/GameView.swift \
    "$GAME"/Sources/GameViewController.swift \
    "$GAME"/Sources/MenuView.swift \
    "$GAME"/Sources/RedeemViewController.swift \
    "$GAME"/Sources/LHJWebViewController.swift \
    -o "$APP/LHJ"

echo "==> 拷贝 Info.plist 与资源"
cp "$GAME/Info.plist" "$APP/Info.plist"
cp "$GAME"/Resources/* "$APP"/

# 转成二进制 plist（可选）
plutil -convert binary1 "$APP/Info.plist"

echo "==> 打包 Payload"
pushd "$OUT" >/dev/null
zip -qry "LHJ-unsigned.ipa" Payload
popd >/dev/null

echo ""
echo "构建完成: $OUT/LHJ-unsigned.ipa"
ls -lh "$OUT/LHJ-unsigned.ipa"

# ---------------------------------------------------------------------------
# GitHub Actions（无 Mac 时）:
#
# .github/workflows/build-ipa.yml:
#
# name: build-ipa
# on: [push, workflow_dispatch]
# jobs:
#   build:
#     runs-on: macos-14
#     steps:
#       - uses: actions/checkout@v4
#       - run: chmod +x ios/build-ipa.sh && ./ios/build-ipa.sh
#       - uses: actions/upload-artifact@v4
#         with:
#           name: LHJ-unsigned-ipa
#           path: ios/build/LHJ-unsigned.ipa
# ---------------------------------------------------------------------------
