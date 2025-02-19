#!/bin/bash

# 添加别名
if ! grep -q "alias n=" ~/.bashrc; then
    echo "alias n='/root/next-server.sh'" >> ~/.bashrc
    source ~/.bashrc
    echo "别名 'n' 已添加，当前会立即生效。"
fi

# 检查系统架构
ARCH=$(uname -m)
if [[ "$ARCH" == "x86_64" ]]; then
    DOWNLOAD_URL="https://github.com/The-NeXT-Project/NeXT-Server/releases/latest/download/next-server-linux-amd64.zip"
elif [[ "$ARCH" == "aarch64" ]]; then
    DOWNLOAD_URL="https://github.com/The-NeXT-Project/NeXT-Server/releases/latest/download/next-server-linux-arm64.zip"
else
    echo -e "\033[1;33m警告：当前系统架构为 $ARCH，不支持安装 NeXT-Server。\033[0m"
    exit 1
fi

INSTALL_DIR="/etc/next-server"
SERVICE_FILE="/etc/systemd/system/next-server.service"

# 颜色设置
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

function show_menu() {
    echo -e "NeXT-Server 一键脚本"
    echo ""
    echo "请选择要执行的操作："
    echo -e "${GREEN}1${NC}. 安装 NeXT-Server"
    echo -e "${GREEN}2${NC}. 卸载 NeXT-Server"
    echo "----------------------------"
    echo -e "${GREEN}3${NC}. 启动 NeXT-Server"
    echo -e "${GREEN}4${NC}. 停止 NeXT-Server"
    echo -e "${GREEN}5${NC}. 重启 NeXT-Server"
    echo "----------------------------"
    echo -e "${GREEN}6${NC}. 查看 NeXT-Server 日志"
    echo -e "${GREEN}7${NC}. 查看 NeXT-Server 状态"
    echo "----------------------------"
    echo -e "${GREEN}8${NC}. 节点对接"
    echo -e "${GREEN}9${NC}. DNS解锁"
    echo "----------------------------"
    echo -e "${GREEN}0${NC}. 退出脚本"
}

function download_and_install() {
    echo -e "正在下载 NeXT-Server..."
    wget -q -O /tmp/next-server.zip "$DOWNLOAD_URL"
    if [[ $? -ne 0 ]]; then
        echo -e "${YELLOW}下载失败，请检查网络连接或下载链接。${NC}"
        exit 1
    fi

    echo -e "正在创建安装目录..."
    mkdir -p "$INSTALL_DIR"

    CONFIG_FILES=("config.yml" "custom_inbound.json" "custom_outbound.json" "dns.json" "geoip.dat" "geosite.dat" "next-server" "route.json" "rulelist")
    MISSING_FILES=()

    # 检查哪些配置文件缺失
    for file in "${CONFIG_FILES[@]}"; do
        if [ ! -e "$INSTALL_DIR/$file" ]; then
            MISSING_FILES+=("$file")
        fi
    done

    if [ "${#MISSING_FILES[@]}" -eq 0 ]; then
        echo -e "所有配置文件已存在，仅替换 next-server 文件..."
        unzip -o /tmp/next-server.zip next-server -d "$INSTALL_DIR"
    else
        echo -e "部分配置文件缺失，替换 next-server 并补充缺失的文件..."
        unzip -o /tmp/next-server.zip next-server "${MISSING_FILES[@]}" -d "$INSTALL_DIR"
    fi

    if [ -f "$SERVICE_FILE" ]; then
        echo -e "系统服务文件已存在，仅重启 NeXT-Server。"
        sudo systemctl restart next-server
    else
        echo -e "正在创建 systemd 服务文件..."
        cat <<EOF | sudo tee "$SERVICE_FILE" > /dev/null
[Unit]
Description=NeXT Server
After=network.target

[Service]
Type=simple
ExecStart=/etc/next-server/next-server
RestartSec=5s
Restart=on-failure
User=root
Group=root
WorkingDirectory=/etc/next-server

[Install]
WantedBy=multi-user.target
EOF

        echo -e "正在重新加载 systemd 守护进程..."
        sudo systemctl daemon-reload
        sudo systemctl enable next-server
    fi

    echo -e "NeXT-Server 安装与配置完成。"
}

function start_service() {
    echo -e "正在启动 NeXT-Server..."
    sudo systemctl start next-server
    echo -e "${YELLOW}NeXT-Server 已启动。${NC}"
}

function stop_service() {
    echo -e "正在停止 NeXT-Server..."
    sudo systemctl stop next-server
    echo -e "${YELLOW}NeXT-Server 已停止。${NC}"
}

function restart_service() {
    echo -e "正在重启 NeXT-Server..."
    sudo systemctl restart next-server
    echo -e "${YELLOW}NeXT-Server 已重启。${NC}"
}

function view_logs() {
    echo -e "${YELLOW}正在查看 NeXT-Server 日志...${NC}"
    sudo journalctl -u next-server -f
}

function check_status() {
    echo -e "${YELLOW}正在检查 NeXT-Server 状态...${NC}"
    sudo systemctl status next-server
}

function uninstall() {
    read -p "确定要卸载 NeXT-Server 吗？[y/N]: " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        echo -e "正在停止并禁用 NeXT-Server..."
        sudo systemctl stop next-server
        sudo systemctl disable next-server

        echo -e "正在删除 systemd 服务文件..."
        sudo rm -f "$SERVICE_FILE"

        echo -e "正在删除安装目录..."
        sudo rm -rf "$INSTALL_DIR"

        echo -e "正在重新加载 systemd 守护进程..."
        sudo systemctl daemon-reload

        echo -e "${YELLOW}NeXT-Server 已卸载。${NC}"
    else
        echo -e "${YELLOW}卸载已取消。${NC}"
    fi
}

function open_config() {
    echo -e "${YELLOW}正在打开节点对接配置文件...${NC}"
    sudo nano /etc/next-server/config.yml
}

function open_dns() {
    echo -e "${YELLOW}正在打开DNS解锁配置文件...${NC}"
    sudo nano /etc/next-server/dns.json
}

while true; do
    show_menu
    read -p "请输入你的选择 [0-9]: " choice
    case $choice in
        1)
            download_and_install
            ;;
        2)
            uninstall
            ;;
        3)
            start_service
            ;;
        4)
            stop_service
            ;;
        5)
            restart_service
            ;;
        6)
            view_logs
            ;;
        7)
            check_status
            ;;
        8)
            open_config
            ;;
        9)
            open_dns
            ;;
        0)
            echo -e "${GREEN}退出脚本...${NC}"
            exit 0
            ;;
        *)
            echo -e "${YELLOW}无效的选择，请输入 0 到 9 之间的数字。${NC}"
            ;;
    esac

    # 询问用户是否继续
    read -n 1 -s -r -p "按任意键继续..."
    echo ""
done
