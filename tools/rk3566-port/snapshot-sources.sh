#!/bin/bash
# 打包 ROCKNIX 构建中「git 类」包源码（约 15.5G / 35 个包）
#
# 为什么只打包 git 类：
#   sources/ 下 1600+ 个包是 tarball，走 PKG_SHA256 校验，下载失败率极低；
#   真正反复失败的是 35 个 git 仓库（含 28 个带子模块的），它们是全部风险的来源。
#
# 用法:
#   ./snapshot-sources.sh [distribution路径] [输出目录]
#   默认: 当前目录 / $HOME/sources-snapshot
#
# 产物:
#   sources-git-<日期>.tar.zst        约 3-4G
#   sources-git-<日期>.tar.zst.sha256
#   sources-git-<日期>.manifest.txt   包清单（含 commit）

set -euo pipefail

DIST="${1:-$(pwd)}"
OUT="${2:-$HOME/sources-snapshot}"
SOURCES="${DIST}/sources"

if [ ! -d "${SOURCES}" ]; then
    echo "错误: 找不到 ${SOURCES}" >&2
    exit 1
fi

command -v zstd >/dev/null || { echo "错误: 需要 zstd" >&2; exit 1; }

mkdir -p "${OUT}"
STAMP="$(date +%Y%m%d-%H%M)"
ARCHIVE="${OUT}/sources-git-${STAMP}.tar.zst"
MANIFEST="${OUT}/sources-git-${STAMP}.manifest.txt"

echo "扫描 git 类包..."
mapfile -t PKGS < <(find "${SOURCES}" -maxdepth 3 -name .git -type d 2>/dev/null | sed 's|/.git$||' | sed "s|^${SOURCES}/||" | sort)

if [ ${#PKGS[@]} -eq 0 ]; then
    echo "错误: 没有找到 git 类包" >&2
    exit 1
fi

echo "找到 ${#PKGS[@]} 个 git 类包"

{
    echo "# sources git snapshot ${STAMP}"
    echo "# 共 ${#PKGS[@]} 个包"
    for p in "${PKGS[@]}"; do
        sha="$(git -C "${SOURCES}/${p}" rev-parse HEAD 2>/dev/null || echo '?')"
        br="$(git -C "${SOURCES}/${p}" symbolic-ref -q --short HEAD 2>/dev/null || echo 'DETACHED')"
        sz="$(du -sm "${SOURCES}/${p}" 2>/dev/null | cut -f1)"
        printf '%-70s %s %8sM  %s\n' "$p" "$sha" "$sz" "$br"
    done
} > "${MANIFEST}"

echo "清单: ${MANIFEST}"
echo "总大小: $(du -sm "${SOURCES}" 2>/dev/null | cut -f1)M (含 tarball)"
echo
echo "开始压缩（zstd -T0 -12，预计 5-15 分钟）..."

# 用 -T 传文件列表，避免路径中的特殊字符问题
printf '%s\0' "${PKGS[@]}" | tar -C "${SOURCES}" --null -T - -cf - | zstd -T0 -12 -q -o "${ARCHIVE}"

echo "生成校验值..."
sha256sum "${ARCHIVE}" > "${ARCHIVE}.sha256"

echo
echo "完成: ${ARCHIVE}"
ls -lh "${ARCHIVE}"
echo
echo "还原方式:"
echo "  ./restore-sources.sh <distribution路径> ${ARCHIVE}"
