#!/bin/bash
# 交叉编译 ffmpeg 6.0（含 truehd/mlp/pgssub），单架构
# 用法: ./build-ffmpeg.sh <iphoneos|iphonesimulator> <arm64|x86_64>
set -e

SDK_NAME=$1
ARCH=$2
MIN=$3
MIN=${MIN:-12.0}

SDK=$(xcrun --sdk "$SDK_NAME" --show-sdk-path)
OUT="/tmp/ffbuild/out-${SDK_NAME}-${ARCH}"
rm -rf "$OUT"
mkdir -p "$OUT"

# dav1d framework 目录（按 SDK 选 slice）
if [ "$SDK_NAME" = "iphoneos" ]; then
  DAV1D_FW_DIR="/Users/xiamu/Desktop/GitHub/fryfrog-hub-apple/Vendor/Dav1d.xcframework/ios-arm64"
  MINFLAG="-mios-version-min=$MIN"
else
  DAV1D_FW_DIR="/Users/xiamu/Desktop/GitHub/fryfrog-hub-apple/Vendor/Dav1d.xcframework/ios-arm64_x86_64-simulator"
  MINFLAG="-mios-simulator-version-min=$MIN"
fi

# 生成架构对应的 dav1d.pc
sed "s|@DAV1D_FW_DIR@|$DAV1D_FW_DIR|g" /tmp/ffbuild/dav1d.pc > /tmp/ffbuild/dav1d-$ARCH.pc
export PKG_CONFIG_PATH="/tmp/ffbuild"

NEON=""
[ "$ARCH" = "arm64" ] && NEON="--enable-neon"

cd /tmp/ffbuild/ffmpeg-6.0
make distclean >/dev/null 2>&1 || true

./configure \
  --prefix="$OUT" \
  --enable-cross-compile \
  --target-os=darwin \
  --arch="$ARCH" \
  --sysroot="$SDK" \
  --cc="xcrun -sdk $SDK_NAME clang" \
  --extra-cflags="-arch $ARCH $MINFLAG -I/tmp/ffbuild/dav1d-install/include" \
  --extra-ldflags="-arch $ARCH $MINFLAG -F$DAV1D_FW_DIR -framework Security -framework CoreFoundation" \
  --enable-securetransport \
  --disable-autodetect \
  --disable-all \
  --disable-x86asm \
  --disable-runtime-cpudetect \
  --disable-debug \
  --disable-stripping \
  --enable-small \
  --enable-optimizations \
  --enable-shared \
  --enable-network \
  --enable-pthreads \
  --enable-pic \
  --enable-version3 \
  --enable-safe-bitstream-reader \
  --enable-avcodec \
  --enable-avformat \
  --enable-swresample \
  --enable-swscale \
  --enable-avfilter \
  --enable-zlib \
  --enable-audiotoolbox \
  --enable-videotoolbox \
  $NEON \
  --enable-libdav1d \
  --enable-decoder='aac*' \
  --enable-decoder=ac3 \
  --enable-decoder=alac \
  --enable-decoder=als \
  --enable-decoder=ape \
  --enable-decoder=ass \
  --enable-decoder='atrac*' \
  --enable-decoder=av1 \
  --enable-decoder=dca \
  --enable-decoder='dsd*' \
  --enable-decoder=dvbsub \
  --enable-decoder=dvdsub \
  --enable-decoder=eac3 \
  --enable-decoder=flac \
  --enable-decoder=flv \
  --enable-decoder='gsm*' \
  --enable-decoder=h263 \
  --enable-decoder=h263i \
  --enable-decoder=h263p \
  --enable-decoder=h264 \
  --enable-decoder=hevc \
  --enable-decoder=libdav1d \
  --enable-decoder=mjpeg \
  --enable-decoder=movtext \
  --enable-decoder='mp1*' \
  --enable-decoder='mp2*' \
  --enable-decoder='mp3*' \
  --enable-decoder='mpc*' \
  --enable-decoder=mpeg1video \
  --enable-decoder=mpeg2video \
  --enable-decoder=mpeg4 \
  --enable-decoder=msmpeg4v1 \
  --enable-decoder=msmpeg4v2 \
  --enable-decoder=msmpeg4v3 \
  --enable-decoder=opus \
  --enable-decoder='pcm*' \
  --enable-decoder='ra*' \
  --enable-decoder=ralf \
  --enable-decoder=shorten \
  --enable-decoder=srt \
  --enable-decoder=ssa \
  --enable-decoder=stl \
  --enable-decoder=subrip \
  --enable-decoder=subviewer \
  --enable-decoder=subviewer1 \
  --enable-decoder=tak \
  --enable-decoder=text \
  --enable-decoder=theora \
  --enable-decoder=tta \
  --enable-decoder=vorbis \
  --enable-decoder=vp6 \
  --enable-decoder=vp6a \
  --enable-decoder=vp6f \
  --enable-decoder=vp8 \
  --enable-decoder=vp9 \
  --enable-decoder=vplayer \
  --enable-decoder=wavpack \
  --enable-decoder=webvtt \
  --enable-decoder='wma*' \
  --enable-decoder=wmv1 \
  --enable-decoder=wmv2 \
  --enable-decoder=wmv3 \
  --enable-decoder=wmv3image \
  --enable-decoder=truehd \
  --enable-decoder=mlp \
  --enable-decoder=pgssub \
  --enable-parser='aac*' \
  --enable-parser=ac3 \
  --enable-parser=av1 \
  --enable-parser=cook \
  --enable-parser=dca \
  --enable-parser=flac \
  --enable-parser=gsm \
  --enable-parser=h263 \
  --enable-parser=h264 \
  --enable-parser=hevc \
  --enable-parser=mpegaudio \
  --enable-parser=mpeg4video \
  --enable-parser=mpegvideo \
  --enable-parser=tak \
  --enable-parser=vorbis \
  --enable-demuxer=aac \
  --enable-demuxer=ac3 \
  --enable-demuxer=aiff \
  --enable-demuxer=ape \
  --enable-demuxer=asf \
  --enable-demuxer=ass \
  --enable-demuxer=au \
  --enable-demuxer=av1 \
  --enable-demuxer=avi \
  --enable-demuxer=concat \
  --enable-demuxer=data \
  --enable-demuxer=dash \
  --enable-demuxer=dsf \
  --enable-demuxer=dts \
  --enable-demuxer=flac \
  --enable-demuxer=flv \
  --enable-demuxer=hls \
  --enable-demuxer=live_flv \
  --enable-demuxer=loas \
  --enable-demuxer=m4v \
  --enable-demuxer=matroska \
  --enable-demuxer=mjpeg \
  --enable-demuxer=mov \
  --enable-demuxer=mp3 \
  --enable-demuxer='mpc*' \
  --enable-demuxer=mpegps \
  --enable-demuxer=mpegts \
  --enable-demuxer=mpegvideo \
  --enable-demuxer=ogg \
  --enable-demuxer='pcm*' \
  --enable-demuxer=rm \
  --enable-demuxer=rtsp \
  --enable-demuxer=shorten \
  --enable-demuxer=srt \
  --enable-demuxer=stl \
  --enable-demuxer=subviewer \
  --enable-demuxer=subviewer1 \
  --enable-demuxer=tak \
  --enable-demuxer=truehd \
  --enable-demuxer=tta \
  --enable-demuxer=vplayer \
  --enable-demuxer=webm_dash_manifest \
  --enable-demuxer=webvtt \
  --enable-demuxer=wv \
  --enable-demuxer=xwma \
  --enable-protocol=async \
  --enable-protocol=cache \
  --enable-protocol=crypto \
  --enable-protocol=data \
  --enable-protocol=ffrtmphttp \
  --enable-protocol=file \
  --enable-protocol=ftp \
  --enable-protocol=hls \
  --enable-protocol=http \
  --enable-protocol=httpproxy \
  --enable-protocol=https \
  --enable-protocol=pipe \
  --enable-protocol=rtmp \
  --enable-protocol=rtmps \
  --enable-protocol=rtmpt \
  --enable-protocol=rtmpts \
  --enable-protocol=rtp \
  --enable-protocol=subfile \
  --enable-protocol=tcp \
  --enable-protocol=tls \
  --enable-filter=overlay \
  --enable-filter=equalizer \
  --enable-hwaccel=h263_videotoolbox \
  --enable-hwaccel=h264_videotoolbox \
  --enable-hwaccel=hevc_videotoolbox \
  --enable-hwaccel=mpeg1_videotoolbox \
  --enable-hwaccel=mpeg2_videotoolbox \
  --enable-hwaccel=mpeg4_videotoolbox \
  --enable-hwaccel=vp9_videotoolbox \
  --disable-doc \
  --disable-ffmpeg \
  --disable-ffplay \
  --disable-ffprobe

make -j8 2>&1 | tail -5
make install >/dev/null 2>&1
echo "BUILD OK: $OUT"
