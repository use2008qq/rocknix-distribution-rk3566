#!/bin/bash
# 还原 git 类包源码快照到 sources/
#
# 用法:
#   ./restore-sources.sh <distribution路径> <快照文件.tar.zst>
#   ./restore-sources.sh <distribution路径> <分卷目录或首个分卷>
#
# 效果：把这些包的源码、子模块、占位文件一次性放回原位，
#       构建时 pkgbuilder 会判定仓库有效并直接复用，不再联网下载。
#
# 支持分卷：如果传入的是 xxx.part-aa，会自动按顺序合并全部分卷；
#          如果传入目录，会自动找到其中的 .tar.zst 或 .part-* 并处理。

set -euo pipefail

DIST="${1:?用法: restore-sources.sh <distribution路径> <快照.tar.zst|分卷>}"
ARCHIVE="${2:?用法: restore-sources.sh <distribution路径> <快照.tar.zst|分卷>}"
SOURCES="${DIST}/sources"

[ -d "${DIST}/projects/ROCKNIX" ] || { echo "错误: ${DIST} 不是 distribution 仓库" >&2; exit 1; }
command -v zstd >/dev/null || { echo "错误: 需要 zstd" >&2; exit 1; }

# 传目录时自动探测
if [ -d "${ARCHIVE}" ]; then
    cand="$(ls "${ARCHIVE}"/*.tar.zst 2>/dev/null | head -1)"
    if [ -z "${cand}" ]; then
        cand="$(ls "${ARCHIVE}"/*.part-* 2>/dev/null | head -1)"
    fi
    [ -n "${cand}" ] || { echo "错误: ${ARCHIVE} 下没有快照文件" >&2; exit 1; }
    ARCHIVE="${cand}"
fi

[ -f "${ARCHIVE}" ] || { echo "错误: 快照不存在: ${ARCHIVE}" >&2; exit 1; }

TMP=""
cleanup() { [ -n "${TMP}" ] && rm -f "${TMP}"; }
trap cleanup EXIT

# 分卷处理
if [[ "${ARCHIVE}" == *.part-* ]]; then
    PREFIX="${ARCHIVE%%.part-*}"
    echo "检测到分卷，合并中..."
    parts=( "${PREFIX}".part-* )
    echo "  ${#parts[@]} 个分卷"
    TMP="$(mktemp -u /tmp/sources-restore-XXXXXX.tar.zst)"
    cat "${parts[@]}" > "${TMP}"
    ARCHIVE="${TMP}"
fi

# 校验
if [ -f "${ARCHIVE}.sha256" ]; then
    echo "校验快照完整性..."
    ( cd "$(dirname "${ARCHIVE}")" && sha256sum -c "$(basename "${ARCHIVE}").sha256" ) || {
        echo "错误: sha256 校验失败，快照可能损坏" >&2; exit 1
    }
elif [ -f "${ARCHIVE%.part-*}.sha256" ]; then
    echo "校验合并后的快照..."
    sha256sum -c "${ARCHIVE%.part-*}.sha256" || {
        echo "错误: sha256 校验失败" >&2; exit 1
    }
fi

mkdir -p "${SOURCES}"
echo "还原到 ${SOURCES} ..."
tar -C "${SOURCES}" --use-compress-program=unzstd -xf "${ARCHIVE}"

echo
echo "还原完成，检查仓库状态："
fail=0
while IFS= read -r g; do
    d="$(dirname "$g")"
    if ! git -C "$d" rev-parse --verify HEAD >/dev/null 2>&1; then
        echo "  [异常] ${d} 没有有效 HEAD"
        fail=$((fail+1))
    fi
done < <(find "${SOURCES}" -maxdepth 3 -name .git -type d 2>/dev/null)

if [ "$fail" -eq 0 ]; then
    echo "  所有 git 仓库状态正常"
else
    echo "  有 ${fail} 个仓库异常，建议运行 repair-sources.sh"
fi

echo
echo "下一步：su builder -c './scripts/build_distro'"
