#!/usr/bin/env python3
"""生成给主线 panel-simple.c 增加 GM800 面板的补丁（程序化改+diff，保证可 apply）。"""
import re, shutil, subprocess, sys, os

SRC = "/tmp/kpanel/linux-7.2.11/drivers/gpu/drm/panel/panel-simple.c"
WORK = "/tmp/patchwork/drivers/gpu/drm/panel/panel-simple.c"
OUT = "/root/CheckPoint/RKSOC/rk3566/workspace/Devices/GM800/rk3566-guomeiyun-armbian/mainline/panel-guomeiyun.patch"

MODE = """static const struct drm_display_mode guomeiyun_gm800_mode = {
\t.clock = 78000,
\t.hdisplay = 800,
\t.hsync_start = 800 + 40,
\t.hsync_end = 800 + 40 + 8,
\t.htotal = 800 + 40 + 8 + 28,
\t.vdisplay = 1280,
\t.vsync_start = 1280 + 180,
\t.vsync_end = 1280 + 180 + 8,
\t.vtotal = 1280 + 180 + 8 + 38,
};

static const struct panel_desc_dsi guomeiyun_gm800 = {
\t.desc = {
\t\t.modes = &guomeiyun_gm800_mode,
\t\t.num_modes = 1,
\t\t.bpc = 8,
\t\t.size = {
\t\t\t.width = 68,
\t\t\t.height = 121,
\t\t},
\t\t.delay = {
\t\t\t.prepare = 60,
\t\t\t.enable = 120,
\t\t},
\t\t.connector_type = DRM_MODE_CONNECTOR_DSI,
\t},
\t.flags = MIPI_DSI_MODE_VIDEO | MIPI_DSI_MODE_VIDEO_BURST |
\t\t MIPI_DSI_MODE_VIDEO_SYNC_PULSE,
\t.format = MIPI_DSI_FMT_RGB888,
\t.lanes = 4,
};

"""

MATCH = """\t}, {
\t\t.compatible = "guomeiyun,gm800-panel",
\t\t.data = &guomeiyun_gm800
"""

def main():
    os.makedirs(os.path.dirname(WORK), exist_ok=True)
    shutil.copy2(SRC, WORK)
    t = open(WORK, encoding="utf-8").read()

    # 1) 在 dsi_of_match[] 表之前插入 mode + desc
    anchor = "static const struct of_device_id dsi_of_match[] = {"
    assert anchor in t, "找不到 dsi_of_match[] 表"
    t = t.replace(anchor, MODE + anchor, 1)

    # 2) 在匹配表末尾（sentinel 前）插入条目
    sentinel = "\t}, {\n\t\t/* sentinel */\n\t}\n};"
    assert sentinel in t, "找不到 sentinel"
    t = t.replace(sentinel, "\t}, {\n" + MATCH + "\t}, {\n\t\t/* sentinel */\n\t}\n};", 1)

    open(WORK, "w", encoding="utf-8").write(t)

    # 3) 生成 diff
    rel = "drivers/gpu/drm/panel/panel-simple.c"
    r = subprocess.run(["diff", "-u", SRC, WORK], capture_output=True, text=True)
    if r.returncode not in (0, 1):
        print(r.stderr, file=sys.stderr); sys.exit(1)

    body = r.stdout
    # 换成 a/ b/ 路径形式，便于 git apply / patch -p1
    lines = body.split("\n")
    lines[0] = "--- a/" + rel
    lines[1] = "+++ b/" + rel
    header = (
        "Subject: [PATCH] drm/panel: panel-simple: add Guomeiyun GM800 800x1280 DSI panel\n"
        "\n"
        "GM800 国美云触屏音箱用一块 800x1280 的 4-lane MIPI DSI 面板，\n"
        "时序来自原厂 DTB（78MHz，876x1506 空白期）。主线 panel-simple 的\n"
        "DSI 匹配表里没有通用条目，无法直接用 compatible = \"panel-simple\"，\n"
        "因此按现有面板的写法补一条。\n"
        "\n"
        "Signed-off-by: guomeiyun <gm800@local>\n"
        "---\n"
    )
    with open(OUT, "w", encoding="utf-8") as f:
        f.write(header + "\n".join(lines))
    print(f"补丁已生成: {OUT}")
    print(f"改动行数: {sum(1 for l in lines if l.startswith('+') and not l.startswith('+++'))} 新增 / "
          f"{sum(1 for l in lines if l.startswith('-') and not l.startswith('---'))} 删除")

if __name__ == "__main__":
    main()
