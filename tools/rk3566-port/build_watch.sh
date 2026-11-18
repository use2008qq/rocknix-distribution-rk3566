#!/bin/bash
# 构建状态轮询（锚定在最后一次 RESUME START 之后，避免匹配到历史日志）
L=/home/builder/build.log
last_count=0
last_emit=0

emit() {
    local n arm cur disk load
    n=$(tail -n +${OFFSET} "$L" 2>/dev/null | grep -acE '\[DONE\]')
    arm=$(tail -n +${OFFSET} "$L" 2>/dev/null | grep -acE '^\[[0-9]+/253\]')
    cur=$(tail -n +${OFFSET} "$L" 2>/dev/null | grep -aE '^\[[0-9]+/[0-9]+\] \[DONE\]' | tail -1 | sed 's/.*\] //')
    disk=$(df -h /root | tail -1 | awk '{print $4}')
    load=$(cut -d' ' -f1-3 /proc/loadavg)
    echo "$1 | done=${n} last=${cur} disk=${disk} load=${load}"
    last_emit=$(date +%s)
}

# 锚定到最后一个 RESUME START 行号
OFFSET=$(grep -an "### RESUME START" "$L" | tail -1 | cut -d: -f1)
OFFSET=${OFFSET:-1}
echo "锚定行号 OFFSET=$OFFSET"

while true; do
    [ -f "$L" ] || { sleep 60; continue; }

    NEW=$(grep -an "### RESUME START" "$L" | tail -1 | cut -d: -f1)
    if [ -n "$NEW" ] && [ "$NEW" -gt "$OFFSET" ]; then
        OFFSET=$NEW
        last_count=0
        echo "检测到新一轮构建，锚定行号 OFFSET=$OFFSET"
    fi

    TAIL=$(tail -n +${OFFSET} "$L" 2>/dev/null)

    if echo "$TAIL" | grep -qa "### RESUME END"; then
        echo "### RESUME END: $(echo "$TAIL" | grep -a '### RESUME END' | tail -1)"
        break
    fi

    if echo "$TAIL" | grep -qaE '\[FAILED\]|Build failed|Parallel build failure'; then
        emit "!!! FAILURE"
        echo "$TAIL" | grep -aE '\[FAILED\]|Build failed|Parallel build failure' | tail -5
        sleep 60
        continue
    fi

    n=$(echo "$TAIL" | grep -acE '\[DONE\]')
    now=$(date +%s)
    if [ "$n" -ge $((last_count + 10)) ]; then
        emit "progress"
        last_count=$n
    elif [ $((now - last_emit)) -ge 480 ]; then
        emit "heartbeat"
    fi

    sleep 120
done
