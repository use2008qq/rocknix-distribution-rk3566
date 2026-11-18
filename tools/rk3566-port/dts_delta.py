#!/usr/bin/env python3
"""比对 GM800 的 BSP DTS 与主线 rk356x-base.dtsi，找出只在板级 DTS 里出现的节点。"""
import re, sys, json

GM = "/root/CheckPoint/RKSOC/rk3566/workspace/Devices/GM800/rk3566-guomeiyun-armbian/dts/rk3566-guomeiyun.dts"
BASE = "/tmp/kdts/linux-7.2.11/arch/arm64/boot/dts/rockchip/rk356x-base.dtsi"

NODE_RE = re.compile(r'^\s*([A-Za-z0-9,_-]+):\s*([A-Za-z0-9,_@ -]+?)\s*\{', re.M)

def nodes(path):
    t = open(path, encoding="utf-8", errors="ignore").read()
    out = {}
    for m in NODE_RE.finditer(t):
        label, name = m.group(1), m.group(2).strip()
        key = name.split("@")[0] if "@" in name else name
        addr = name.split("@")[1] if "@" in name else ""
        out.setdefault(key, set()).add(addr)
    return out

gm = nodes(GM)
bs = nodes(BASE)

# 主线 base 里有同名的 -> 视为 SoC 级
only_gm = {k: v for k, v in gm.items() if k not in bs}

print("=== 只出现在 GM800 BSP DTS 里的节点类型（主线 rk356x-base.dtsi 没有）===")
print(f"GM800 节点种类 {len(gm)}，主线 base {len(bs)}，差集 {len(only_gm)}\n")
for k in sorted(only_gm):
    v = ",".join(sorted(x for x in only_gm[k] if x))
    print(f"  {k:34s} {v}")
