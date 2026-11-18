#!/bin/bash
# 续跑 ROCKNIX RK3566 aarch64 趟（arm 趟 253/253 已完成，产物完整）
export http_proxy=http://192.168.6.121:7890
export https_proxy=http://192.168.6.121:7890
export HTTP_PROXY=$http_proxy
export HTTPS_PROXY=$https_proxy

cd /root/CheckPoint/RKSOC/rk3566/workspace/Platform/rocknix/distribution || exit 1

echo "### RESUME START $(date -Is) ###"
echo "### free disk before: $(df -h /root | tail -1 | awk '{print $4}') ###"

DEVICE_ROOT=RK3566 PROJECT=ROCKNIX DEVICE=RK3566 ARCH=aarch64 ./scripts/build_distro
rc=$?

echo "### RESUME END $(date -Is) rc=$rc ###"
echo "### free disk after: $(df -h /root | tail -1 | awk '{print $4}') ###"
exit $rc
