#!/usr/bin/env bash

total_mem_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
total_mem_mb=$((total_mem_kb / 1024))

echo "================================================="
echo " 检测到系统总物理内存: ${total_mem_mb} MB"
echo "================================================="

if [ "$total_mem_mb" -le 384 ]; then
    buf_mb=4
elif [ "$total_mem_mb" -le 768 ]; then
    buf_mb=8
elif [ "$total_mem_mb" -le 1536 ]; then
    buf_mb=16
elif [ "$total_mem_mb" -le 3072 ]; then
    buf_mb=32
elif [ "$total_mem_mb" -le 6144 ]; then
    buf_mb=48
else
    buf_mb=64
fi

buf_bytes=$((buf_mb * 1024 * 1024))

speed_150ms=$((buf_mb * 8 * 1000 / 150))
speed_50ms=$((buf_mb * 8 * 1000 / 50))

echo " 推荐最大缓冲区: ${buf_mb} MB (${buf_bytes} 字节)"
echo " 理论单连接吞吐能力预估:"
echo "   - 跨境/长延迟链路 (150ms RTT): 约 ${speed_150ms} Mbps"
echo "   - 近距离/亚太链路 ( 50ms RTT): 约 ${speed_50ms} Mbps"
echo "================================================="

read -p "是否将此配置直接覆盖写入 /etc/sysctl.conf 并生效? (y/N): " choice

case "$choice" in 
  y|Y )
    cat > /etc/sysctl.conf <<SYSCTL_EOF
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.core.rmem_max = ${buf_bytes}
net.core.wmem_max = ${buf_bytes}
net.ipv4.tcp_rmem = 4096 87380 ${buf_bytes}
net.ipv4.tcp_wmem = 4096 65536 ${buf_bytes}
net.ipv4.udp_rmem_min = 8192
net.ipv4.udp_wmem_min = 8192
SYSCTL_EOF

    sysctl -p
    echo ""
    echo ">> 配置已成功应用并生效！"
    ;;
  * )
    echo ">> 已取消应用，配置未更改。"
    ;;
esac
