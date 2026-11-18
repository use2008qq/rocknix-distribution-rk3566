#!/usr/bin/env python3
"""检查 ROCKNIX 各包源码 URL 的可达性，只测试尚未进入本地缓存的包。"""
import os, re, sys, subprocess, glob, concurrent.futures

DIST = "/root/CheckPoint/RKSOC/rk3566/workspace/Platform/rocknix/distribution"
SOURCES = os.path.join(DIST, "sources")

# 收集所有 package.mk 的 (PKG_NAME, PKG_URL, PKG_VERSION, PKG_SOURCE_NAME)
pkgs = {}
for root in ("packages", "projects"):
    for pm in glob.glob(os.path.join(DIST, root, "**", "package.mk"), recursive=True):
        try:
            txt = open(pm, encoding="utf-8", errors="ignore").read()
        except Exception:
            continue
        name = re.search(r'^PKG_NAME="?([^"\n]+)"?', txt, re.M)
        if not name:
            continue
        n = name.group(1).strip()
        if n in pkgs:          # 已收录则先到先得（顶层 packages 优先被遍历）
            continue
        url = re.search(r'^PKG_URL="?([^"\n]+)"?', txt, re.M)
        ver = re.search(r'^PKG_VERSION="?([^"\n]+)"?', txt, re.M)
        sn  = re.search(r'^PKG_SOURCE_NAME="?([^"\n]+)"?', txt, re.M)
        if not url:
            continue
        pkgs[n] = {
            "url": url.group(1).strip(),
            "ver": ver.group(1).strip() if ver else "",
            "src": sn.group(1).strip() if sn else None,
            "pm": pm,
        }

def source_name(p):
    if p["src"]:
        return p["src"]
    u = p["url"]
    base = os.path.basename(u.split("?")[0])
    # URL 无扩展名时按 PKG_NAME-VERSION 拼
    if "." not in base:
        ext = ""
        for e in (".tar.gz", ".tar.xz", ".tar.bz2", ".tgz", ".zip", ".tar"):
            if e in u:
                ext = e
                break
        return f"{p['name']}-{p['ver']}{ext}"
    return base

missing = []
for n, p in pkgs.items():
    p["name"] = n
    sn = source_name(p)
    d = os.path.join(SOURCES, n)
    pkg = os.path.join(d, sn)
    if os.path.isfile(pkg) and os.path.isfile(pkg + ".sha256"):
        continue
    missing.append(p)

print(f"包总数 {len(pkgs)}，未缓存 {len(missing)}", flush=True)

env = dict(os.environ)
env["https_proxy"] = env["http_proxy"] = "http://192.168.6.121:7890"

def check(p):
    url = p["url"]
    if not url.startswith("http"):
        return (p["name"], url, "skip")
    try:
        r = subprocess.run(
            ["curl", "-sS", "-o", "/dev/null", "-w", "%{http_code}", "-I", "--max-time", "15", url],
            env=env, capture_output=True, text=True, timeout=25)
        code = r.stdout.strip()
    except Exception:
        code = "000"
    ok = code.startswith(("2", "3")) or code in ("405", "403", "401")
    return (p["name"], url, "OK" if ok else f"HTTP {code}")

bad = []
with concurrent.futures.ThreadPoolExecutor(max_workers=12) as ex:
    for name, url, st in ex.map(check, missing):
        if st != "OK":
            bad.append((name, url, st))
            print(f"  !! {name:28s} {st:12s} {url}", flush=True)

print(f"\n不可达/异常的包: {len(bad)}")
with open("/tmp/bad_sources.txt", "w") as f:
    for name, url, st in bad:
        f.write(f"{name}\t{url}\t{st}\n")
