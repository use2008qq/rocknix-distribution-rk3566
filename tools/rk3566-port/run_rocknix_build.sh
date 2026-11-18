#!/bin/bash
# 以 builder 用户执行 ROCKNIX RK3566 完整构建
export http_proxy=http://192.168.6.121:7890
export https_proxy=http://192.168.6.121:7890
export HTTP_PROXY=$http_proxy
export HTTPS_PROXY=$https_proxy

cd /root/CheckPoint/RKSOC/rk3566/workspace/Platform/rocknix/distribution || exit 1

echo "### BUILD START $(date -Is) ###"
echo "### free disk before: $(df -h /root | tail -1 | awk '{print $4}') ###"

make RK3566
rc=$?

echo "### BUILD END $(date -Is) rc=$rc ###"
echo "### free disk after: $(df -h /root | tail -1 | awk '{print $4}') ###"
exit $rc
