#!/bin/bash
# 修复 file-5.48 源码下载失败：ftp.astron.com 经代理超时，
# 改从 macports distfiles 取，放入 ROCKNIX 本地缓存并补齐 stamp
set -e
export https_proxy=http://192.168.6.121:7890
export http_proxy=http://192.168.6.121:7890

DIST=/root/CheckPoint/RKSOC/rk3566/workspace/Platform/rocknix/distribution
DEST="$DIST/sources/file"
NAME="file-5.48.tar.gz"
WANT="ed14656883b23a364b4057c05595d93252da9bc473d30106519519d0da141283"

mkdir -p "$DEST"

if [ -f "$DEST/$NAME" ] && [ "$(sha256sum "$DEST/$NAME" | cut -d' ' -f1)" = "$WANT" ]; then
    echo "已在缓存且校验通过，跳过下载"
else
    rm -f "$DEST/$NAME"
    for u in \
        "https://distfiles.macports.org/file/$NAME" \
        "https://distfiles.macports.org/pub/file/$NAME" \
        "https://ftp.astron.com/pub/file/$NAME" \
        "https://astron.com/pub/file/$NAME"; do
        echo "尝试: $u"
        if timeout 90 curl -fsSL --retry 2 -o "$DEST/$NAME" "$u"; then
            GOT=$(sha256sum "$DEST/$NAME" | cut -d' ' -f1)
            if [ "$GOT" = "$WANT" ]; then
                echo "  校验通过 ($GOT)"
                echo "$u" > "$DEST/$NAME.url"
                echo "$GOT" > "$DEST/$NAME.sha256"
                echo "OK from $u"
                exit 0
            fi
            echo "  校验不符: got=$GOT want=$WANT"
            rm -f "$DEST/$NAME"
        fi
    done
    echo "!! 所有镜像均失败"
    exit 1
fi

echo "--- 缓存状态 ---"
ls -la "$DEST"
cat "$DEST/$NAME.sha256"
