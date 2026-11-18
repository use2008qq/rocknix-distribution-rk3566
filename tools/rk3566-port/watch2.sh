#!/bin/bash
# 针对当前实例的监控：以 pkgbuilder 进程存活为终止条件
L=/home/builder/build.log
J=/root/CheckPoint/RKSOC/rk3566/workspace/Platform/rocknix/distribution/build.ROCKNIX-RK3566.aarch64/.threads/joblog
last=0
last_emit=0

emit() {
    local d f n disk load avail
    d=$(grep -c '^DONE' "$J" 2>/dev/null)
    f=$(grep -cE '^(FAIL|ERROR)' "$J" 2>/dev/null)
    n=$(tail -1 "$J" 2>/dev/null | awk '{print $4}')
    avail=$(df -BG /root/CheckPoint | tail -1 | awk '{gsub(/G/,"",$4); print $4}')
    disk=$(df -h /root/CheckPoint | tail -1 | awk '{print $4}')
    load=$(cut -d' ' -f1-3 /proc/loadavg)
    echo "$1 | DONE=${d} FAIL=${f} last=${n} disk=${disk} load=${load}"
    if [ "${avail:-999}" -lt 40 ]; then
        echo "!!! 磁盘告警: 仅剩 ${avail}G（低于 40G），后续 image/rootfs 可能失败"
    fi
    last_emit=$(date +%s)
}

echo "监控已启动（当前实例）"

while true; do
    alive=0
    for p in $(ls /proc 2>/dev/null | grep -E '^[0-9]+$'); do
        c=$(tr '\0' ' ' < "/proc/$p/cmdline" 2>/dev/null) || continue
        case "$c" in
            *scripts/pkgbuilder.py*) alive=1; break ;;
        esac
    done

    d=$(grep -c '^DONE' "$J" 2>/dev/null)
    f=$(grep -cE '^(FAIL|ERROR)' "$J" 2>/dev/null)

    if [ "$alive" -eq 0 ]; then
        emit "构建进程已退出"
        if [ "$f" -gt 0 ]; then
            echo "!!! 有失败项，详情："
            grep -aE '^(FAIL|ERROR)' "$J" | tail -5
        fi
        break
    fi

    if [ "$f" -gt 0 ]; then
        emit "!!! 检测到 FAIL"
        grep -aE '^(FAIL|ERROR)' "$J" | tail -5
    fi

    now=$(date +%s)
    if [ "$d" -ge $((last + 20)) ]; then
        emit "progress"
        last=$d
    elif [ $((now - last_emit)) -ge 480 ]; then
        emit "heartbeat"
    fi

    sleep 120
done
