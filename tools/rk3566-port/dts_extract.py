#!/usr/bin/env python3
"""按 label 从 BSP DTS 中提取节点正文（自动配平花括号）。"""
import re, sys

GM = "/root/CheckPoint/RKSOC/rk3566/workspace/Devices/GM800/rk3566-guomeiyun-armbian/dts/rk3566-guomeiyun.dts"

def load():
    return open(GM, encoding="utf-8", errors="ignore").read().split("\n")

def extract(lines, label):
    """返回 label: xxx { ... } 的完整文本（含行号前缀）"""
    pat = re.compile(r'^\s*' + re.escape(label) + r':\s*')
    out = []
    for i, ln in enumerate(lines):
        if not pat.match(ln):
            continue
        depth = 0
        started = False
        for j in range(i, len(lines)):
            l = lines[j]
            out.append(f"{j+1}: {l}")
            depth += l.count("{") - l.count("}")
            if "{" in l:
                started = True
            if started and depth <= 0:
                break
        return "\n".join(out)
    return f"### 未找到 label: {label}"

if __name__ == "__main__":
    lines = load()
    labels = sys.argv[1:]
    if not labels:
        print("用法: dts_extract.py <label> [label...]")
        sys.exit(1)
    for l in labels:
        print(extract(lines, l))
        print()
