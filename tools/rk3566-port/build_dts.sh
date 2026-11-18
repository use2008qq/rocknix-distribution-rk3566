#!/bin/bash
# 搭好主线内核的 DTS include 树，编译验证 GM800 设备树
set -u
S=/root/CheckPoint/RKSOC/rk3566/workspace/Platform/rocknix/distribution/sources/linux/linux-7.2.11.tar.xz
B=/tmp/dtsbuild
SRC=/root/CheckPoint/RKSOC/rk3566/workspace/Devices/GM800/rk3566-guomeiyun-armbian/mainline/rk3566-guomeiyun.dts

rm -rf "$B"; mkdir -p "$B"

cd "$B" || exit 1
timeout 300 tar -xf "$S" \
  linux-7.2.11/include/dt-bindings/ \
  linux-7.2.11/include/uapi/linux/input-event-codes.h \
  linux-7.2.11/arch/arm64/boot/dts/rockchip/rk356x-base.dtsi \
  linux-7.2.11/arch/arm64/boot/dts/rockchip/rk3568-pinctrl.dtsi \
  linux-7.2.11/arch/arm64/boot/dts/rockchip/rockchip-pinconf.dtsi 2>/dev/null
echo "解出 dt-bindings: $(find "$B/linux-7.2.11/include/dt-bindings" -name '*.h' 2>/dev/null | wc -l) 个头文件"
ls "$B/linux-7.2.11/arch/arm64/boot/dts/rockchip/" 2>/dev/null
cp "$SRC" "$B/rk3566-guomeiyun.dts"
cd "$B" || exit 1

echo "=== 预处理 ==="
cpp -nostdinc -I linux-7.2.11/include -I linux-7.2.11/arch/arm64/boot/dts/rockchip \
    -undef -D__DTS__ -x assembler-with-cpp \
    rk3566-guomeiyun.dts -o rk3566-guomeiyun.dts.pp 2>&1 | head -30
[ -s rk3566-guomeiyun.dts.pp ] || { echo "!! 预处理失败"; exit 1; }
echo "预处理 OK ($(wc -l < rk3566-guomeiyun.dts.pp) 行)"

echo
echo "=== dtc 编译 ==="
dtc -I dts -O dtb -o rk3566-guomeiyun.dtb -Wno-unit_address_vs_reg \
    -Wno-unit_address_vs_reg -Wno-avoid_unnecessary_addr_size \
    -Wno-graph_child_address -Wno-unique_unit_address \
    -Wno-interrupt_provider -Wno_alias_paths \
    rk3566-guomeiyun.dts.pp 2>&1 | head -40
rc=${PIPESTATUS[0]}
echo "dtc rc=$rc"

if [ -f rk3566-guomeiyun.dtb ]; then
    echo
    echo "=== 产物 ==="
    ls -la rk3566-guomeiyun.dtb
    echo "--- 反查关键节点 ---"
    for n in model compatible gm800-panel backlight pdm-mic-array rtl8201f mxc6655xa spk-amp; do
        if dtc -I dtb -O dts rk3566-guomeiyun.dtb 2>/dev/null | grep -q "$n"; then
            echo "  ✓ $n"
        else
            echo "  ✗ $n  (缺失)"
        fi
    done
fi
