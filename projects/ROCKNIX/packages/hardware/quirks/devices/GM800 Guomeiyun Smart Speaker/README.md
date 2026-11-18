# GM800 Guomeiyun Smart Speaker — ROCKNIX quirk

对应设备：**GM800 国美云触屏音箱**（GM260200482，RK3566 / 4GB / 800×1280 MIPI-DSI）

## 目录名必须与设备树 /model 一致

ROCKNIX 运行时这样确定 quirk 目录（`packages/sysutils/autostart/profile.d/002-autostart`）：

```sh
export QUIRK_DEVICE="$(strings /sys/firmware/devicetree/base/model)"
export QUIRK_DEVICE="$(echo ${QUIRK_DEVICE} | sed -e "s#[/]#-#g")"
```

所以本目录名 `GM800 Guomeiyun Smart Speaker` 对应设备树里的：

```dts
model = "GM800 Guomeiyun Smart Speaker";
```

> 原厂 BSP DTB 的 model 是通用 EVB 名 `Rockchip RK3566 EVB2 LP4X V10 Board`，
> 在 BSP 内核上匹配不到任何 quirk 目录。用主线 DTB（见
> `Devices/GM800/rk3566-guomeiyun-armbian/mainline/rk3566-guomeiyun.dts`）才有本目录生效。

## 文件

| 文件 | 作用 |
|---|---|
| `001-device_config` | 写入 `/storage/.config/profile.d/001-device_config`：设备型号、触摸、宽高比、LED 策略 |
| `001-detect-device` | 确保 `/flash/extlinux/extlinux.conf` 的 FDT 指向 `rk3566-guomeiyun.dtb` |
| `050-audio_path` | 写入 `/storage/.config/profile.d/002-audio_path`：ALSA 播放/录音路径 |
| `070-touch` | udev 规则，给触摸加 `LIBINPUT_CALIBRATION_MATRIX` 校准矩阵 |

## 硬件对应关系

| 功能 | 引脚 | 说明 |
|---|---|---|
| 红灯（常亮） | gpio0 RK_PB2（gpio-10） | 内核 `gpio-leds` 驱动，默认 `default-on` |
| 蓝灯（心跳） | gpio0 RK_PC3（gpio-19） | 内核 `gpio-leds` 驱动，默认 `heartbeat` |
| 功放使能 | gpio1 RK_PA6（gpio-38） | 设备树里的 `regulator-fixed`（spk-amp） |
| 触摸 IRQ | gpio3 RK_PC1 | I2C5 (0xfe5e0000) 上的 GS MXC6655XA |
| 面板复位 | gpio0 RK_PD5 | 低有效 |
| 面板供电 | gpio0 RK_PD7 | vcc3v3_lcd0_n |
| 背光 | pwm5 | `pwm-backlight` |
| USB5V 总开关 | gpio3 RK_PA1 | 补上了原厂 DTB 缺失的 gpio |
| USB3 HOST 使能 | gpio3 RK_PA2 | 串在 USB5V 总开关之后 |
| USB2.0 A 口 VBUS | gpio0 RK_PC6 | |

## 为什么关掉 DEVICE_LED_CONTROL

LED 由**内核的 gpio-leds 驱动**管理（设备树里已配好 default-on / heartbeat）。
ROCKNIX 的 `DEVICE_LED_CONTROL="true"` 会启用用户态 `ledcontrol` 脚本去抢同一批 GPIO，
两者会打架，所以这里设为 `false`。

## 首次装机需要确认

1. `050-audio_path` 里的 mixer 路径名 —— 首启动后用 `alsamixer` 看实际名称再改
2. `070-touch` 的校准矩阵 —— 触摸方向/坐标不对就改这里
3. 面板旋转 —— 若实机确认物理横置，在设备树面板节点加 `rotation = <270>`
