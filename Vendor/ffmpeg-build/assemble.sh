#!/bin/bash
# 组装自编译 ffmpeg 为 xcframework（bash 3.2 兼容）
# 依赖改写：ffmpeg install 后依赖是绝对路径，需按 /tmp/ffbuild/out-*/lib/ 形式匹配
set -e
cd /tmp/ffbuild

VENDOR="/Users/xiamu/Desktop/GitHub/fryfrog-hub-apple/Vendor"

fw_name() {
  case "$1" in
    libavcodec.60.dylib) echo Avcodec ;;
    libavformat.60.dylib) echo Avformat ;;
    libavutil.58.dylib) echo Avutil ;;
    libswresample.4.dylib) echo Swresample ;;
    libswscale.7.dylib) echo Swscale ;;
    libavfilter.9.dylib) echo Avfilter ;;
  esac
}

DYLIB_LIST="libavcodec.60.dylib libavformat.60.dylib libavutil.58.dylib libswresample.4.dylib libswscale.7.dylib libavfilter.9.dylib"

STAGE=/tmp/ffbuild/stage
rm -rf "$STAGE"
mkdir -p "$STAGE/device" "$STAGE/sim" "$STAGE/tmp-arm64" "$STAGE/tmp-x86_64"

for dylib in $DYLIB_LIST; do
  fw=$(fw_name "$dylib")

  # ---- device slice ----
  mkdir -p "$STAGE/device/$fw.framework"
  cp "out-iphoneos-arm64/lib/$dylib" "$STAGE/device/$fw.framework/$fw"
  install_name_tool -id "@rpath/$fw.framework/$fw" "$STAGE/device/$fw.framework/$fw"
  for dep in $DYLIB_LIST; do
    depfw=$(fw_name "$dep")
    install_name_tool -change "/tmp/ffbuild/out-iphoneos-arm64/lib/$dep" "@rpath/$depfw.framework/$depfw" \
      "$STAGE/device/$fw.framework/$fw"
  done

  # ---- simulator slice（lipo 前先分别改两个架构的依赖）----
  cp "out-iphonesimulator-arm64/lib/$dylib" "$STAGE/tmp-arm64/$fw"
  cp "out-iphonesimulator-x86_64/lib/$dylib" "$STAGE/tmp-x86_64/$fw"
  install_name_tool -id "@rpath/$fw.framework/$fw" "$STAGE/tmp-arm64/$fw"
  install_name_tool -id "@rpath/$fw.framework/$fw" "$STAGE/tmp-x86_64/$fw"
  for dep in $DYLIB_LIST; do
    depfw=$(fw_name "$dep")
    install_name_tool -change "/tmp/ffbuild/out-iphonesimulator-arm64/lib/$dep" "@rpath/$depfw.framework/$depfw" "$STAGE/tmp-arm64/$fw"
    install_name_tool -change "/tmp/ffbuild/out-iphonesimulator-x86_64/lib/$dep" "@rpath/$depfw.framework/$depfw" "$STAGE/tmp-x86_64/$fw"
  done
  mkdir -p "$STAGE/sim/$fw.framework"
  lipo -create "$STAGE/tmp-arm64/$fw" "$STAGE/tmp-x86_64/$fw" -output "$STAGE/sim/$fw.framework/$fw"

  # Info.plist
  cp "$VENDOR/$fw.xcframework/ios-arm64/$fw.framework/Info.plist" "$STAGE/device/$fw.framework/Info.plist"
  cp "$VENDOR/$fw.xcframework/ios-arm64_x86_64-simulator/$fw.framework/Info.plist" "$STAGE/sim/$fw.framework/Info.plist"

  echo "assembled $fw"
done

# ---- 替换 Vendor ----
mkdir -p /tmp/ffbuild/vendor-backup
for fw in Avcodec Avformat Avutil Swresample Swscale Avfilter; do
  [ -d "$VENDOR/$fw.xcframework" ] && mv "$VENDOR/$fw.xcframework" "/tmp/ffbuild/vendor-backup/$fw.xcframework"
  xcodebuild -create-xcframework \
    -framework "$STAGE/device/$fw.framework" \
    -framework "$STAGE/sim/$fw.framework" \
    -output "$VENDOR/$fw.xcframework" 2>&1 | tail -1
done
echo "VENDOR REPLACED OK"
