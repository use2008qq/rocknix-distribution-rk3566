#!/bin/bash
# 扫描并修复 sources/ 下 git 类包的常见故障
#
# 背景：pkgbuilder 用 _repo_exists_and_valid 判断已有源码能否复用：
#   1. git clean -fdx + git restore --staged . || git switch --force
#   2. git ls-remote . | grep -q -m1 "^<PKG_VERSION>"
#   3. origin URL 匹配
# 任一失败 -> 删除整个源码目录重新下载（表现为同一包反复 clone，数小时无进展）
#
# 已知最致命的两种状态：
#   - HEAD detached：git switch --force 失败 -> 判定无效 -> 死循环
#   - 子模块只登记 gitlink 但工作树为空 -> CMake add_subdirectory 失败
#
# 用法:
#   ./repair-sources.sh <distribution路径>          # 只检查，不改动
#   ./repair-sources.sh <distribution路径> --fix    # 检查并修复

set -uo pipefail

DIST="${1:?用法: repair-sources.sh <distribution路径> [--fix]}"
FIX="${2:-}"
SOURCES="${DIST}/sources"

[ -d "${SOURCES}" ] || { echo "错误: 找不到 ${SOURCES}" >&2; exit 1; }

# 这些子模块是故意不初始化的，不要尝试拉取
should_skip_sub() {
    case "$1" in
        */ffmpeg)          return 0 ;;   # ppsspp-lr: 用占位 linux_arm64.sh 替代
        */Externals/Qt)    return 0 ;;   # dolphin-sa/vita3k-sa: Windows 预编译
        */Externals/Qt*)   return 0 ;;
        *)                 return 1 ;;
    esac
}

total=0 detached=0 emptytree=0 uninit=0 fixed=0

echo "扫描 ${SOURCES} ..."
echo

while IFS= read -r gitdir; do
    d="$(dirname "${gitdir}")"
    rel="${d#${SOURCES}/}"
    total=$((total + 1))
    issues=()

    # 1. HEAD 是否 detached
    if ! git -C "${d}" symbolic-ref -q HEAD >/dev/null 2>&1; then
        detached=$((detached + 1))
        issues+=("DETACHED")
        if [ "${FIX}" = "--fix" ]; then
            if git -C "${d}" checkout -B rocknix-pin >/dev/null 2>&1; then
                issues+=("-> 已建分支 rocknix-pin")
                fixed=$((fixed + 1))
            else
                issues+=("-> 修复失败(工作树脏)")
            fi
        fi
    fi

    # 2. 工作树是否为空（只有 .git）
    if [ "$(find "${d}" -mindepth 1 -maxdepth 1 ! -name .git | wc -l)" -eq 0 ]; then
        emptytree=$((emptytree + 1))
        issues+=("EMPTY_TREE(需重新下载)")
    fi

    # 3. 未初始化子模块
    if [ -f "${d}/.gitmodules" ]; then
        subs="$(git -C "${d}" submodule status 2>/dev/null | awk '$1 ~ /^-/ {print $2}')"
        if [ -n "${subs}" ]; then
            while IFS= read -r s; do
                [ -z "${s}" ] && continue
                if should_skip_sub "${d}/${s}"; then
                    continue
                fi
                uninit=$((uninit + 1))
                issues+=("SUBMODULE:${s}")
                if [ "${FIX}" = "--fix" ]; then
                    if git -C "${d}" submodule update --init --recursive --depth 1 "${s}" >/dev/null 2>&1; then
                        issues+=("-> 已拉取 ${s}")
                        fixed=$((fixed + 1))
                    else
                        issues+=("-> ${s} 拉取失败(网络?)")
                    fi
                fi
            done <<< "${subs}"
        fi
    fi

    if [ ${#issues[@]} -gt 0 ]; then
        echo "[${rel}]"
        for i in "${issues[@]}"; do echo "    ${i}"; done
    fi
done < <(find "${SOURCES}" -maxdepth 3 -name .git -type d 2>/dev/null | sort)

echo
echo "===== 汇总 ====="
echo "git 类包总数      : ${total}"
echo "HEAD detached     : ${detached}"
echo "工作树为空        : ${emptytree}"
echo "未初始化子模块    : ${uninit}"
if [ "${FIX}" = "--fix" ]; then
    echo "已修复项          : ${fixed}"
else
    echo
    echo "当前为只读检查。加 --fix 执行修复："
    echo "  ./repair-sources.sh ${DIST} --fix"
fi
