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
#
# 属主：以 root 运行时，解包后自动把 sources/ 交给仓库属主（通常是 builder），
#       否则 builder 无权写入 build 目录，构建会失败。

set -euo pipefail

DIST="${1:?用法: restore-sources.sh <distribution路径> <快照.tar.zst|分卷>}"
ARCHIVE="${2:?用法: restore-sources.sh <distribution路径> <快照.tar.zst|分卷>}"
DIST="$(cd "${DIST}" && pwd)"
SOURCES="${DIST}/sources"

[ -d "${DIST}/projects/ROCKNIX" ] || { echo "错误: ${DIST} 不是 distribution 仓库" >&2; exit 1; }
command -v zstd >/dev/null || { echo "错误: 需要 zstd（apt install zstd）" >&2; exit 1; }

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
SHA=""
cleanup() { [ -n "${TMP}" ] && rm -f "${TMP}"; }
trap cleanup EXIT

# ---- 分卷处理 ----
if [[ "${ARCHIVE}" == *.part-* ]]; then
    PREFIX="${ARCHIVE%%.part-*}"
    SHA="${PREFIX}.sha256"
    parts=( "${PREFIX}".part-* )
    echo "检测到分卷，共 ${#parts[@]} 个"
    merged_kb=0
    for p in "${parts[@]}"; do
        merged_kb=$(( merged_kb + $(du -sk "$p" | awk '{print $1}') ))
    done
    # 合并后的整包要落在 /tmp，先确认放得下
    avail_tmp_kb=$(df -k /tmp | tail -1 | awk '{print $4}')
    if [ "${avail_tmp_kb}" -lt "$(( merged_kb + 1024*1024 ))" ]; then
        echo "错误: /tmp 空间不足（需约 $((merged_kb/1024/1024))G，可用 $((avail_tmp_kb/1024/1024))G）" >&2
        echo "      可先自行合并: cat ${PREFIX}.part-* > /其他分区/sources.tar.zst" >&2
        exit 1
    fi
    echo "  合并中（约 $((merged_kb/1024/1024))G）..."
    TMP="$(mktemp -u /tmp/sources-restore-XXXXXX.tar.zst)"
    cat "${parts[@]}" > "${TMP}"
    ARCHIVE="${TMP}"
else
    SHA="${ARCHIVE}.sha256"
fi

# ---- 校验（只比对哈希值，不依赖文件名字段）----
if [ -f "${SHA}" ]; then
    echo "校验快照完整性..."
    want="$(awk '{print $1}' "${SHA}" | head -1)"
    got="$(sha256sum "${ARCHIVE}" | awk '{print $1}')"
    if [ "${want}" = "${got}" ]; then
        echo "  sha256 OK"
    else
        echo "错误: sha256 校验失败" >&2
        echo "  期望: ${want}" >&2
        echo "  实际: ${got}" >&2
        echo "  分卷可能下载不全，请核对每个分卷大小" >&2
        exit 1
    fi
else
    echo "提示: 未找到 ${SHA}，跳过校验"
fi

# ---- 空间检查 ----
need_gb=20
avail_gb=$(df -BG "${DIST}" | tail -1 | awk '{print $4}' | tr -d 'G')
if [ "${avail_gb}" -lt "${need_gb}" ]; then
    echo "错误: ${DIST} 所在分区仅剩 ${avail_gb}G，解包后还需追加编译，建议 ≥${need_gb}G" >&2
    exit 1
fi

# ---- 解包 ----
mkdir -p "${SOURCES}"
echo "还原到 ${SOURCES} ..."
tar -C "${SOURCES}" --use-compress-program=unzstd -xf "${ARCHIVE}"

# ---- 属主修正 ----
# 构建以普通用户（builder）运行；root 解包出的文件它改不动，会导致 git clean 失败被判定无效
if [ "$(id -u)" -eq 0 ]; then
    OWNER="$(stat -c %U "${DIST}")"
    if [ "${OWNER}" != "root" ] && id "${OWNER}" >/dev/null 2>&1; then
        echo "修正属主为 ${OWNER} ..."
        chown -R "${OWNER}":"$(stat -c %G "${DIST}")" "${SOURCES}"
    fi
fi

# ---- 健康检查 ----
echo
echo "还原完成，检查仓库状态："
fail=0
total=0
while IFS= read -r g; do
    d="$(dirname "$g")"
    total=$((total+1))
    if ! git -C "$d" rev-parse --verify HEAD >/dev/null 2>&1; then
        echo "  [异常] ${d} 没有有效 HEAD"
        fail=$((fail+1))
        continue
    fi
    # detached HEAD 下次构建会触发删库重下
    if ! git -C "$d" symbolic-ref -q HEAD >/dev/null 2>&1; then
        echo "  [警告] ${d} 处于 detached HEAD"
        fail=$((fail+1))
    fi
done < <(find "${SOURCES}" -maxdepth 3 -name .git -type d 2>/dev/null | sort)

echo "  共检查 ${total} 个 git 仓库"
if [ "${fail}" -eq 0 ]; then
    echo "  状态全部正常"
else
    echo "  有 ${fail} 处异常，请运行: tools/rk3566-port/repair-sources.sh \"${DIST}\" --fix"
fi

echo
echo "下一步:"
echo "  cd ${DIST}"
echo "  su builder -c 'ARCH=aarch64 PROJECT=ROCKNIX DEVICE=RK3566 DEVICE_ROOT=RK3566 ./scripts/build_distro'"
