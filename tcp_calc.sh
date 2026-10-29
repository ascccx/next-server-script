#!/usr/bin/env bash
# sysctl_bdp_tune.sh — 代理/中转机 TCP 调优（按 BDP 带宽时延积计算，非玄学 64M）
# 用法: sudo bash sysctl_bdp_tune.sh
# 原理: BDP = 带宽(Mbit/s)×1000÷8×RTT(ms)；缓冲区上限 = BDP×4
set -uo pipefail

echo "================ 代理机 TCP 调优（BDP 计算）================"
echo ""

# ① 端口带宽
while :; do
  read -rp "① 端口带宽 (Mbit/s，如 100 / 500 / 1000): " BANDWIDTH
  if [[ "$BANDWIDTH" =~ ^[0-9]+$ ]] && [ "$BANDWIDTH" -ge 1 ] && [ "$BANDWIDTH" -le 10000 ]; then
    break
  fi
  echo "   ❌ 请输入 1-10000 之间的整数"
done

# ② 最差 RTT
while :; do
  read -rp "② 最差 RTT (ms，晚高峰偏高值；跨洋 150-250，国内 30-80): " WORST_RTT
  if [[ "$WORST_RTT" =~ ^[0-9]+$ ]] && [ "$WORST_RTT" -ge 1 ] && [ "$WORST_RTT" -le 2000 ]; then
    break
  fi
  echo "   ❌ 请输入 1-2000 之间的整数"
done

# 内存档位
MEM_TOTAL=$(free -m | awk '/^Mem:/{print $2}')
HAS_FEW_RAM=false
[ "$MEM_TOTAL" -lt 2048 ] && HAS_FEW_RAM=true
echo ""
echo "内存 ${MEM_TOTAL}M → $($HAS_FEW_RAM && echo "保守档(<2G)" || echo "常规档")"

# 计算
BDP=$(( BANDWIDTH * 1000 / 8 * WORST_RTT ))
BUFFER=$(( BDP * 4 ))
echo "BDP = $((BDP/1024/1024))MB，缓冲区上限 = $((BUFFER/1024/1024))MB (${BUFFER} 字节)"
echo ""

read -rp "确认应用以上数值？(y/N): " OK
[[ "$OK" == "y" || "$OK" == "Y" ]] || { echo "已取消。"; exit 0; }

# 清理冲突源（所有已存在的缓冲/优化配置，备份后移除）
echo ""
echo "== 清理旧配置 =="
for f in /etc/sysctl.d/99-optimize.conf /etc/sysctl.d/99-bbr-buffer.conf \
         /etc/sysctl.d/98-bbr.conf /etc/sysctl.d/98-network.conf; do
  if [ -f "$f" ]; then
    mv "$f" "$f.bak.$(date +%Y%m%d%H%M)" && echo "  已备份移除: $f"
  fi
done
if grep -qE "rmem_max|wmem_max|tcp_rmem|tcp_wmem" /etc/sysctl.conf 2>/dev/null; then
  cp /etc/sysctl.conf "/etc/sysctl.conf.bak.$(date +%Y%m%d%H%M)"
  sed -i "/rmem_max\|wmem_max\|tcp_rmem\|tcp_wmem/d" /etc/sysctl.conf
  echo "  已清理 /etc/sysctl.conf 缓冲区行（备份保留）"
fi

# 写入 BDP 配置
SWAP=5; DIRTY=15; MKB=65536
$HAS_FEW_RAM && { SWAP=20; DIRTY=20; MKB=32768; }

cat > /etc/sysctl.d/99-optimize.conf << EOF
# ===== 网络优化（代理/中转机） =====
net.ipv4.tcp_tw_reuse = 1
net.ipv4.ip_local_port_range = 1024 65535
net.core.somaxconn = 4096
net.ipv4.tcp_max_syn_backlog = 8192
net.core.netdev_max_backlog = 5000
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_notsent_lowat = 16384
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_max_tw_buckets = 5000
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 5
net.ipv4.udp_rmem_min = 8192
net.ipv4.udp_wmem_min = 8192
net.ipv4.tcp_syncookies = 1
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# ===== TCP 缓冲区（BDP×4 = ${BUFFER} 字节，带宽${BANDWIDTH}M/RTT ${WORST_RTT}ms） =====
net.core.rmem_max = ${BUFFER}
net.core.wmem_max = ${BUFFER}
net.ipv4.tcp_rmem = 4096 87380 ${BUFFER}
net.ipv4.tcp_wmem = 4096 87380 ${BUFFER}

# ===== 虚拟内存（内存 ${MEM_TOTAL}M 档） =====
vm.swappiness = ${SWAP}
vm.dirty_ratio = ${DIRTY}
vm.dirty_background_ratio = 5
vm.min_free_kbytes = ${MKB}
vm.vfs_cache_pressure = 50

# ===== CPU 调度 =====
kernel.sched_autogroup_enabled = 0
kernel.numa_balancing = 0
EOF
echo "已写入 /etc/sysctl.d/99-optimize.conf"

# BBR 模块
if ! lsmod 2>/dev/null | grep -q tcp_bbr; then
  modprobe tcp_bbr 2>/dev/null && echo "tcp_bbr 模块已加载" \
    || echo "⚠️ tcp_bbr 模块不可用（内核可能不含，跳过）"
fi

echo "== 应用 =="
sysctl --system > /dev/null 2>&1
echo ""

echo "== 验证 =="
sysctl net.ipv4.tcp_congestion_control net.core.default_qdisc 2>/dev/null
sysctl net.core.rmem_max net.core.wmem_max net.ipv4.tcp_rmem net.ipv4.tcp_wmem 2>/dev/null

echo ""
echo "✅ 完成。实际连接状态: ss -tin | grep -E 'bbr|rtt' | head"
echo "恢复: 把 /etc/sysctl.d/ 下 *.bak.* 移回并 sysctl --system"
