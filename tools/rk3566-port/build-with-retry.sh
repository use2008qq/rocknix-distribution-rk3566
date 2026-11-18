#!/bin/bash
# 带自动修复和重试的构建包装
#
# 失败后做三件事：
#   1. 扫描 sources/ 并修复 detached HEAD / 未初始化子模块
#   2. 检查源码目录是否被 pkgbuilder 删掉（死循环征兆）-> 提示还原快照
#   3. 重新跑 build_distro（pkgbuilder 靠 joblog 跳过已完成的包）
#
# 用法:
#   ./build-with-retry.sh [最大尝试次数] [快照文件]
#   默认 3 次

set -uo pipefail

MAX="${1:-3}"
SNAPSHOT="${2:-}"
DIST="$(pwd)"
LOG_DIR="${DIST}/build-logs"
mkdir -p "${LOG_DIR}"

[ -d "${DIST}/scripts" ] || { echo "错误: 请在 distribution 根目录运行" >&2; exit 1; }

baseline="$(find "${DIST}/sources" -maxdepth 3 -name .git -type d 2>/dev/null | wc -l)"
echo "当前 git 类包: ${baseline} 个"

for i in $(seq 1 "${MAX}"); do
    STAMP="$(date +%Y%m%d-%H%M%S)"
    LOG="${LOG_DIR}/build-attempt-${i}-${STAMP}.log"

    echo
    echo "========== 第 ${i}/${MAX} 次构建 =========="
    echo "日志: ${LOG}"

    set +e
    ./scripts/build_distro 2>&1 | tee "${LOG}"
    rc="${PIPESTATUS[0]}"
    set -e

    if [ "${rc}" -eq 0 ]; then
        echo
        echo "构建成功。"
        exit 0
    fi

    echo
    echo "构建失败 (exit=${rc})，开始诊断..."

    # 失败的包
    B="$(ls -d build.ROCKNIX-* 2>/dev/null | head -1)"
    if [ -n "${B}" ] && [ -f "${B}/.threads/joblog" ]; then
        echo "失败任务:"
        grep -E '^(FAIL|ERROR)' "${B}/.threads/joblog" | tail -5
    fi

    # 检查源码是否被删（死循环征兆）
    now="$(find "${DIST}/sources" -maxdepth 3 -name .git -type d 2>/dev/null | wc -l)"
    if [ "${now}" -lt "${baseline}" ]; then
        echo
        echo "!! 警告: git 类包从 ${baseline} 减少到 ${now}，说明有源码被删除重下"
        if [ -n "${SNAPSHOT}" ] && [ -f "${SNAPSHOT}" ]; then
            echo "   从快照还原..."
            "$(dirname "$0")/restore-sources.sh" "${DIST}" "${SNAPSHOT}"
        else
            echo "   建议先还原快照，再继续。"
        fi
    else
        echo "修复源码状态..."
        "$(dirname "$0")/repair-sources.sh" "${DIST}" --fix
    fi

    if [ "${i}" -lt "${MAX}" ]; then
        echo "10 秒后重试..."
        sleep 10
    fi
done

echo
echo "已达最大尝试次数，需要人工介入。"
echo "参考: documentation/PER_DEVICE_DOCUMENTATION/RK3566/GM800-PORT-NOTES.md"
exit 1
