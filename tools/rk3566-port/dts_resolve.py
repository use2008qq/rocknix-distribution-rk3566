#!/usr/bin/env python3
"""把 BSP DTS 中的数值 phandle 引用解析成对应节点的 label，便于移植到主线。"""
import re, sys, collections

GM = "/root/CheckPoint/RKSOC/rk3566/workspace/Devices/GM800/rk3566-guomeiyun-armbian/dts/rk3566-guomeiyun.dts"

txt = open(GM, encoding="utf-8", errors="ignore").read()
lines = txt.split("\n")

# phandle -> (label, node-name, line)
ph2label = {}
for i, ln in enumerate(lines):
    m = re.match(r'^\s*([A-Za-z0-9,_-]+):\s*([A-Za-z0-9,_@ -]+?)\s*\{', ln)
    if m:
        ph = re.search(r'phandle\s*=\s*<0x([0-9a-fA-F]+)>', "\n".join(lines[i:i+40]))
        if ph:
            ph2label[int(ph.group(1), 16)] = (m.group(1), m.group(2).strip(), i + 1)

# 反查：某个 label 的 phandle
label2ph = {v[0]: k for k, v in ph2label.items()}

def ph(v):
    return ph2label.get(v, (f"0x{v:x}", "?", 0))

if __name__ == "__main__":
    if sys.argv[1] == "--list":
        # 列出所有带 label 的节点 + phandle
        for k in sorted(ph2label):
            lab, nm, ln = ph2label[k]
            print(f"  0x{k:04x} = {lab:28s} ({nm})  line {ln}")
    else:
        for a in sys.argv[1:]:
            if a.startswith("0x"):
                v = int(a, 16)
                lab, nm, ln = ph(v)
                print(f"{a} -> {lab:28s} ({nm})  line {ln}")
            else:
                print(f"{a} -> phandle 0x{label2ph.get(a,0):x}" if a in label2ph else f"{a} -> 未找到")
