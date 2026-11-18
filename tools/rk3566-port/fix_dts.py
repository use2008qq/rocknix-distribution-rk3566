#!/usr/bin/env python3
"""用原厂 DTB 的精确数据修正主线设备树。"""
import re

GM = "/root/CheckPoint/RKSOC/rk3566/workspace/Devices/GM800/rk3566-guomeiyun-armbian/dts/rk3566-guomeiyun.dts"
DTS = "/root/CheckPoint/RKSOC/rk3566/workspace/Devices/GM800/rk3566-guomeiyun-armbian/mainline/rk3566-guomeiyun.dts"

gm = open(GM, encoding="utf-8", errors="ignore").read()
dt = open(DTS, encoding="utf-8", errors="ignore").read()

# 1) 取原厂 backlight1 的 brightness-levels 原样
m = re.search(r'brightness-levels\s*=\s*<([^>]+)>', gm)
levels = " ".join(m.group(1).split())
print(f"brightness-levels: {levels[:70]} ... ({len(levels.split())} 项)")

# 2) 取原厂 backlight1 的 default-brightness-level
m2 = re.search(r'default-brightness-level\s*=\s*<0x([0-9a-fA-F]+)>', gm)
dflt = int(m2.group(1), 16)
print(f"default-brightness-level: {dflt}")

# 3) 替换主线 DTS 里的 brightness-levels 块
new_levels = "\t\tbrightness-levels =\n\t\t\t" + levels + ";"
dt = re.sub(r'\t\tbrightness-levels =\n(?:\t\t\t.*\n)+?\t\t\t.*;\n',
            new_levels + "\n", dt, count=1)
dt = re.sub(r'default-brightness-level = <200>;', f'default-brightness-level = <{dflt}>;', dt)

# 4) pwm-backlight 的 pwms：原厂是 <&pwm5 0 25000 0>（与主线 x55 一致）
dt = dt.replace("pwms = <&pwm5 0 25000000>;", "pwms = <&pwm5 0 25000 0>;")

# 5) mdio 节点补 cell 声明（主线 rk356x-base.dtsi 的写法）
dt = dt.replace(
    "\tmdio1 {\n\t\trgmii_phy0: ethernet-phy@0 {",
    "\tmdio1 {\n\t\t#address-cells = <1>;\n\t\t#size-cells = <0>;\n\n\t\trgmii_phy0: ethernet-phy@0 {")

open(DTS, "w", encoding="utf-8").write(dt)
print("已写入修正后的 DTS")

# 自检
for k in ["brightness-levels", "default-brightness-level", "pwms = <&pwm5", "#address-cells = <1>"]:
    print(f"  {'✓' if k in dt else '✗'} {k}")
