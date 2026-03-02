#!/bin/bash

# ===============================================
# ⭐️ 自修复逻辑：移除Windows换行符 (CRLF)
# ===============================================
if [ -f "$0" ]; then
    if grep -q $'\r$' "$0"; then
        echo -e "\n${YELLOW}检测到 Windows 换行符 (CRLF)，正在自动修正...${NC}"
        sed -i 's/\r//' "$0"
        echo -e "${GREEN}修正完成。请重新运行此脚本。${NC}\n"
        exit 0
    fi
fi

# 颜色设置
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 添加别名
if ! grep -q "alias n=" ~/.bashrc; then
    echo "alias n='/root/next-server.sh'" >> ~/.bashrc
    echo "别名 'n' 已添加，请重新登录或执行 'source ~/.bashrc' 以生效。"
fi

# 检查系统架构
ARCH=$(uname -m)
if [[ "$ARCH" == "x86_64" ]]; then
    DOWNLOAD_URL="https://github.com/The-NeXT-Project/NeXT-Server/releases/latest/download/next-server-linux-amd64.zip"
elif [[ "$ARCH" == "aarch64" ]]; then
    DOWNLOAD_URL="https://github.com/The-NeXT-Project/NeXT-Server/releases/latest/download/next-server-linux-arm64.zip"
else
    echo -e "${YELLOW}警告：当前系统架构为 $ARCH，不支持安装 NeXT-Server。${NC}"
    exit 1
fi

INSTALL_DIR="/etc/next-server"
SERVICE_FILE="/etc/systemd/system/next-server.service"
CONFIG_FILE="$INSTALL_DIR/config.yml"
ROUTE_FILE="$INSTALL_DIR/route.json"

function show_menu() {
    echo ""
    echo -e "${GREEN}NeXT-Server 一键脚本${NC}"
    echo ""
    echo "请选择要执行的操作："
    echo -e "${GREEN}1${NC}. 安装 NeXT-Server"
    echo -e "${GREEN}2${NC}. 卸载 NeXT-Server"
    echo "----------------------------"
    echo -e "${GREEN}3${NC}. 启动 NeXT-Server"
    echo -e "${GREEN}4${NC}. 停止 NeXT-Server"
    echo -e "${GREEN}5${NC}. 重启 NeXT-Server"
    echo "----------------------------"
    echo -e "${GREEN}6${NC}. 查看日志"
    echo -e "${GREEN}7${NC}. 查看状态"
    echo -e "${GREEN}8${NC}. 查看配置"
    echo -e "${GREEN}9${NC}. 诊断连接"
    echo "----------------------------"
    echo -e "${GREEN}10${NC}. 生成证书"
    echo "----------------------------"
    echo -e "${GREEN}11${NC}. 生成路由规则"
    echo -e "${GREEN}12${NC}. 生成节点配置"
    echo "----------------------------"
    echo -e "${GREEN}13${NC}. 生成DNS解锁配置"
    echo "----------------------------"
    echo -e "${GREEN}0${NC}. 退出脚本"
}

function download_and_install() {
    echo -e "${BLUE}正在下载 NeXT-Server...${NC}"
    if ! wget -q --show-progress -O /tmp/next-server.zip "$DOWNLOAD_URL"; then
        echo -e "${RED}❌ 下载失败，请检查网络连接${NC}"
        return 1
    fi

    echo -e "${BLUE}正在创建安装目录...${NC}"
    mkdir -p "$INSTALL_DIR"

    CONFIG_FILES=("config.yml" "custom_inbound.json" "custom_outbound.json" "dns.json" "geoip.dat" "geosite.dat" "next-server" "route.json" "rulelist")
    MISSING_FILES=()

    for file in "${CONFIG_FILES[@]}"; do
        if [ ! -e "$INSTALL_DIR/$file" ]; then
            MISSING_FILES+=("$file")
        fi
    done

    if [ "${#MISSING_FILES[@]}" -eq 0 ]; then
        echo -e "${YELLOW}配置文件已存在，仅更新主程序...${NC}"
        if ! unzip -o /tmp/next-server.zip next-server -d "$INSTALL_DIR"; then
            echo -e "${RED}❌ 解压失败${NC}"
            return 1
        fi
    else
        echo -e "${BLUE}正在解压文件...${NC}"
        if ! unzip -o /tmp/next-server.zip -d "$INSTALL_DIR"; then
            echo -e "${RED}❌ 解压失败${NC}"
            return 1
        fi
    fi

    chmod +x "$INSTALL_DIR/next-server"

    if [ -f "$SERVICE_FILE" ]; then
        echo -e "${YELLOW}服务已存在，正在重启...${NC}"
        sudo systemctl restart next-server
    else
        echo -e "${BLUE}正在创建系统服务...${NC}"
        cat <<EOF | sudo tee "$SERVICE_FILE" > /dev/null
[Unit]
Description=NeXT Server Service
After=network.target nss-lookup.target
Wants=network.target

[Service]
User=root
Group=root
Type=simple
LimitAS=infinity
LimitRSS=infinity
LimitCORE=infinity
LimitNOFILE=999999
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/next-server --config $INSTALL_DIR/config.yml
Restart=on-failure
RestartSec=10
TimeoutStopSec=30
KillMode=mixed
KillSignal=SIGTERM

[Install]
WantedBy=multi-user.target
EOF

        sudo systemctl daemon-reload
        sudo systemctl enable next-server
        sudo systemctl start next-server
    fi

    echo -e "${GREEN}✅ NeXT-Server 安装完成${NC}"
}

function start_service() {
    echo -e "${BLUE}正在启动服务...${NC}"
    if sudo systemctl start next-server; then
        echo -e "${GREEN}✅ 服务已启动${NC}"
    else
        echo -e "${RED}❌ 启动失败${NC}"
        return 1
    fi
}

function stop_service() {
    echo -e "${BLUE}正在停止服务...${NC}"
    if sudo systemctl stop next-server; then
        echo -e "${YELLOW}⏹️  服务已停止${NC}"
    else
        echo -e "${RED}❌ 停止失败${NC}"
        return 1
    fi
}

function restart_service() {
    echo -e "${BLUE}正在重启服务...${NC}"
    if sudo systemctl restart next-server; then
        echo -e "${GREEN}✅ 服务已重启${NC}"
    else
        echo -e "${RED}❌ 重启失败${NC}"
        return 1
    fi
}

function view_logs() {
    echo -e "${YELLOW}📋 实时日志 (Ctrl+C 退出)${NC}"
    echo ""
    sudo journalctl -u next-server -f
}

function check_status() {
    echo -e "${YELLOW}📊 服务状态${NC}"
    echo ""
    sudo systemctl status next-server
}

function view_config() {
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}            查看配置文件${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "  ${CYAN}1${NC}. 主配置文件 (config.yml)"
    echo -e "  ${CYAN}2${NC}. 路由配置 (route.json)"
    echo -e "  ${CYAN}3${NC}. DNS配置 (dns.json)"
    echo -e "  ${CYAN}4${NC}. 证书配置 (cert_config.yml)"
    echo -e "  ${CYAN}5${NC}. 查看所有配置"
    echo ""
    read -p "请选择 [1-5]: " config_choice
    
    case $config_choice in
        1)
            if [ -f "$CONFIG_FILE" ]; then
                echo -e "${GREEN}━━━ config.yml ━━━${NC}"
                cat "$CONFIG_FILE"
            else
                echo -e "${RED}❌ 配置文件不存在${NC}"
            fi
            ;;
        2)
            if [ -f "$ROUTE_FILE" ]; then
                echo -e "${GREEN}━━━ route.json (前50行) ━━━${NC}"
                cat "$ROUTE_FILE" | head -50
            else
                echo -e "${RED}❌ 路由文件不存在${NC}"
            fi
            ;;
        3)
            if [ -f "$INSTALL_DIR/dns.json" ]; then
                echo -e "${GREEN}━━━ dns.json ━━━${NC}"
                cat "$INSTALL_DIR/dns.json"
            else
                echo -e "${RED}❌ DNS配置不存在${NC}"
            fi
            ;;
        4)
            if [ -f "$INSTALL_DIR/cert/cert_config.yml" ]; then
                echo -e "${GREEN}━━━ cert_config.yml ━━━${NC}"
                cat "$INSTALL_DIR/cert/cert_config.yml"
            else
                echo -e "${YELLOW}⚠️  证书配置不存在${NC}"
            fi
            ;;
        5)
            echo -e "${GREEN}━━━ 配置文件概览 ━━━${NC}"
            [ -f "$CONFIG_FILE" ] && echo "✅ config.yml" || echo "❌ config.yml"
            [ -f "$ROUTE_FILE" ] && echo "✅ route.json" || echo "❌ route.json"
            [ -f "$INSTALL_DIR/dns.json" ] && echo "✅ dns.json" || echo "❌ dns.json"
            [ -f "$INSTALL_DIR/cert/selfsigned.crt" ] && echo "✅ 证书文件" || echo "❌ 证书文件"
            ;;
        *)
            echo -e "${RED}❌ 无效选择${NC}"
            ;;
    esac
}

function diagnose_connection() {
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}            连接诊断${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    # 1. 服务状态
    echo -e "${YELLOW}【1】服务状态${NC}"
    if systemctl is-active --quiet next-server; then
        echo -e "${GREEN}✅ 服务运行中${NC}"
    else
        echo -e "${RED}❌ 服务未运行${NC}"
        return 1
    fi
    echo ""
    
    # 2. 监听端口
    echo -e "${YELLOW}【2】监听端口${NC}"
    if command -v ss &> /dev/null; then
        listening_ports=$(ss -tuln | grep LISTEN | grep -E ':(443|80|[0-9]{4,5})\s')
        if [ -n "$listening_ports" ]; then
            echo -e "${GREEN}发现端口：${NC}"
            echo "$listening_ports"
        else
            echo -e "${RED}❌ 无监听端口${NC}"
        fi
    fi
    echo ""
    
    # 3. 配置检查
    echo -e "${YELLOW}【3】配置文件${NC}"
    if [ -f "$CONFIG_FILE" ]; then
        echo -e "${GREEN}✅ config.yml 存在${NC}"
        grep -A 5 "NodeID:" "$CONFIG_FILE" | head -20
    fi
    echo ""
    
    # 4. 证书检查
    echo -e "${YELLOW}【4】证书状态${NC}"
    
    # 优先检查 DNS 自动申请的证书目录
    if [ -d "$INSTALL_DIR/cert/certificates" ]; then
        cert_files=$(find "$INSTALL_DIR/cert/certificates" -name "*.crt" 2>/dev/null)
        if [ -n "$cert_files" ]; then
            echo -e "${GREEN}✅ 发现自动申请的证书：${NC}"
            while IFS= read -r cert_file; do
                echo -e "${BLUE}证书文件: $cert_file${NC}"
                openssl x509 -in "$cert_file" -noout -subject -dates 2>/dev/null | sed 's/^/  /'
                echo ""
            done <<< "$cert_files"
        fi
    fi
    
    # 检查自签证书
    if [ -f "$INSTALL_DIR/cert/selfsigned.crt" ]; then
        echo -e "${GREEN}✅ 发现自签证书：${NC}"
        echo -e "${BLUE}证书文件: $INSTALL_DIR/cert/selfsigned.crt${NC}"
        openssl x509 -in "$INSTALL_DIR/cert/selfsigned.crt" -noout -subject -dates 2>/dev/null | sed 's/^/  /'
    fi
    
    # 如果都没有
    if [ ! -d "$INSTALL_DIR/cert/certificates" ] && [ ! -f "$INSTALL_DIR/cert/selfsigned.crt" ]; then
        echo -e "${YELLOW}⚠️  未找到任何证书${NC}"
    fi
    echo ""
    
    # 5. 最近日志
    echo -e "${YELLOW}【5】最近日志${NC}"
    journalctl -u next-server -n 15 --no-pager
    echo ""
}

function uninstall() {
    read -p "⚠️  确定要卸载吗? [y/N]: " confirm
    # 空格、y、Y 都视为确认
    if [[ "$confirm" =~ ^[Yy[:space:]]$ || "$confirm" == " " ]]; then
        echo -e "${BLUE}正在卸载...${NC}"
        sudo systemctl stop next-server 2>/dev/null
        sudo systemctl disable next-server 2>/dev/null
        sudo rm -f "$SERVICE_FILE"
        sudo rm -rf "$INSTALL_DIR"
        sudo systemctl daemon-reload
        echo -e "${GREEN}✅ 卸载完成${NC}"
    else
        echo -e "${YELLOW}已取消${NC}"
    fi
}

function generate_self_signed_cert() {
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}            证书生成${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "  ${CYAN}1${NC}. 自签证书 (测试用)"
    echo -e "  ${CYAN}2${NC}. Let's Encrypt (Cloudflare DNS)"
    echo ""
    read -p "请选择 [1/2, 默认1]: " cert_type_choice
    cert_type_choice=${cert_type_choice:-1}   # 默认选择1

    if [[ "$cert_type_choice" == "2" ]]; then
        echo -e "${GREEN}━━━ Let's Encrypt 自动申请 ━━━${NC}"
        
        read -p "📌 域名 (如 node1.example.com): " cert_domain
        cert_domain=${cert_domain:-node1.test.com}
        
        read -p "📧 邮箱: " acme_email
        acme_email=${acme_email:-acme@example.com}
        
        read -p "🔑 Cloudflare API Key: " cf_api_key
        cf_api_key=${cf_api_key:-your_api_key}

        # 设置环境变量供 acme.sh 使用
        export CF_Email="$acme_email"
        export CF_Key="$cf_api_key"

        # 安装 acme.sh（如果没有）
        if ! command -v acme.sh &>/dev/null; then
            echo -e "${YELLOW}acme.sh 未安装，正在安装...${NC}"
            curl https://get.acme.sh | sh
            source ~/.bashrc
        fi

        # 证书路径
        cert_dir="/etc/letsencrypt/live/$cert_domain"
        sudo mkdir -p "$cert_dir"

        echo -e "${GREEN}开始申请证书...${NC}"
        ~/.acme.sh/acme.sh --issue --dns dns_cf -d "$cert_domain" --server letsencrypt --force

        if [[ $? -eq 0 ]]; then
            echo -e "${GREEN}✅ 证书申请成功，正在保存...${NC}"
            ~/.acme.sh/acme.sh --install-cert -d "$cert_domain" \
                --key-file       "$cert_dir/privkey.pem" \
                --fullchain-file "$cert_dir/fullchain.pem"

            echo -e "${GREEN}✅ 证书已保存到 $cert_dir/${NC}"
            echo -e "  📄 $cert_dir/fullchain.pem"
            echo -e "  🔑 $cert_dir/privkey.pem"

        else
            echo -e "${RED}❌ 证书申请失败，请检查域名解析和 Cloudflare API Key${NC}"
        fi

    else
        echo -e "${GREEN}━━━ 生成自签证书 ━━━${NC}"
        
        cert_cn="node1.test.com"
        cert_dir="/etc/next-server/cert"
        sudo mkdir -p "$cert_dir"
        cert_crt="$cert_dir/selfsigned.crt"
        cert_key="$cert_dir/selfsigned.key"
        
        if sudo openssl req -x509 -nodes -days 365 \
            -newkey rsa:2048 \
            -keyout "$cert_key" \
            -out "$cert_crt" \
            -subj "/C=CN/ST=Shanghai/L=Shanghai/O=Test/OU=IT/CN=$cert_cn"; then
            echo -e "${GREEN}✅ 证书已生成${NC}"
            echo -e "  📄 $cert_crt"
            echo -e "  🔑 $cert_key"
        else
            echo -e "${RED}❌ 生成失败${NC}"
        fi
    fi
}

function generate_node_config() {
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}            生成节点配置${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    if [ ! -d "$INSTALL_DIR" ]; then
        echo -e "${RED}❌ 请先安装 NeXT-Server${NC}"
        return 1
    fi

    local first_api_host=""
    local first_api_key=""
    local all_nodes=""
    
    # 证书配置缓存
    local last_cert_mode=""
    local last_cert_domain=""
    local last_acme_email=""
    local last_cf_api_key=""

    while true; do
        echo -e "${YELLOW}━━━ 节点基本信息 ━━━${NC}"
        
        # 1. API信息（首次输入后可复用）
        if [ -z "$first_api_host" ]; then
            read -p "📡 面板地址 (ApiHost): " api_host
            [[ -z "$api_host" ]] && { echo -e "${RED}❌ 不能为空${NC}"; continue; }
            
            read -p "🔑 API密钥 (ApiKey): " api_key
            [[ -z "$api_key" ]] && { echo -e "${RED}❌ 不能为空${NC}"; continue; }
            
            first_api_host="$api_host"
            first_api_key="$api_key"
        else
            echo -e "${GREEN}✓ 使用已输入的 API 信息${NC}"
            api_host="$first_api_host"
            api_key="$first_api_key"
        fi
        
        # 2. 节点ID
        read -p "🆔 节点ID (NodeID): " node_id
        [[ -z "$node_id" ]] && { echo -e "${RED}❌ 不能为空${NC}"; continue; }

        # 3. 节点类型
        echo ""
        echo "节点类型："
        echo -e "  ${CYAN}1${NC}. shadowsocks2022 (无需证书)"
        echo -e "  ${CYAN}2${NC}. trojan (需要证书)"
        echo -e "  ${CYAN}3${NC}. vmess (需要证书)"
        read -p "选择 [1-3, 默认1]: " node_choice
        
        case $node_choice in
            2) node_type="trojan" ;;
            3) node_type="vmess" ;;
            *) node_type="shadowsocks2022" ;;
        esac
        
        # 4. 证书配置（仅 trojan/vmess 需要）
        local cert_config=""
        
        if [[ "$node_type" == "trojan" || "$node_type" == "vmess" ]]; then
            echo ""
            echo -e "${YELLOW}━━━ TLS 证书配置 ━━━${NC}"
            
            # 如果有缓存，询问是否复用
            if [[ -n "$last_cert_mode" ]]; then
                echo -e "${GREEN}检测到上次的证书配置：${NC}"
                echo "  模式: $last_cert_mode"
                echo "  域名: $last_cert_domain"
                [[ "$last_cert_mode" == "dns" ]] && echo "  邮箱: $last_acme_email"
                echo ""
                read -p "是否复用上次的证书配置? [Y/n]: " reuse_cert
                
                if [[ "$reuse_cert" =~ ^[Nn]$ ]]; then
                    # 选择不复用，重新输入
                    last_cert_mode=""
                else
                    # 复用配置（默认或输入 Y/y）
                    cert_mode="$last_cert_mode"
                    cert_domain="$last_cert_domain"
                    acme_email="$last_acme_email"
                    cf_api_key="$last_cf_api_key"
                    
                    echo -e "${GREEN}✓ 已复用证书配置${NC}"
                fi
            fi
            
            # 如果没有缓存或选择不复用，则重新输入
            if [[ -z "$last_cert_mode" ]]; then
                echo -e "  ${CYAN}1${NC}. file (使用已有证书)"
                echo -e "  ${CYAN}2${NC}. dns (自动申请 Let's Encrypt)"
                read -p "证书模式 [1/2, 默认1]: " cert_mode_choice
                
                local cert_mode="file"
                local cert_domain="node1.test.com"
                local cert_file="/etc/next-server/cert/selfsigned.crt"
                local key_file="/etc/next-server/cert/selfsigned.key"
                local cert_provider="cloudflare"
                local acme_email="acme@example.com"
                local cf_api_key="your_api_key"
                local dnsenv_config=""
                
                if [[ "$cert_mode_choice" == "2" ]]; then
                    cert_mode="dns"
                    
                    read -p "📌 证书域名: " cert_domain
                    [[ -z "$cert_domain" ]] && cert_domain="node1.test.com"
                    
                    read -p "📧 邮箱: " acme_email
                    [[ -z "$acme_email" ]] && acme_email="acme@example.com"
                    
                    read -p "🔑 Cloudflare API Key: " cf_api_key
                    [[ -z "$cf_api_key" ]] && cf_api_key="your_api_key"
                    
                    dnsenv_config="        DNSEnv:
          CLOUDFLARE_EMAIL: \"$acme_email\"
          CLOUDFLARE_API_KEY: \"$cf_api_key\""
                fi
                
                # 保存到缓存
                last_cert_mode="$cert_mode"
                last_cert_domain="$cert_domain"
                last_acme_email="$acme_email"
                last_cf_api_key="$cf_api_key"
            else
                # 使用缓存的配置生成 dnsenv_config
                local cert_file="/etc/next-server/cert/selfsigned.crt"
                local key_file="/etc/next-server/cert/selfsigned.key"
                local cert_provider="cloudflare"
                local dnsenv_config=""
                
                if [[ "$cert_mode" == "dns" ]]; then
                    dnsenv_config="        DNSEnv:
          CLOUDFLARE_EMAIL: \"$acme_email\"
          CLOUDFLARE_API_KEY: \"$cf_api_key\""
                fi
            fi
            
            cert_config="      CertConfig:
        CertMode: $cert_mode
        CertDomain: \"$cert_domain\"
        CertFile: $cert_file
        KeyFile: $key_file
        Provider: $cert_provider
        Email: $acme_email
$dnsenv_config"
        else
            echo -e "${GREEN}✓ shadowsocks2022 节点，无需证书配置${NC}"
            cert_config="      # shadowsocks2022 无需证书配置"
        fi

        # 5. 生成节点配置块
        node_yaml=$(cat <<EOF
  - PanelType: "sspanel-old"
    ApiConfig:
      ApiHost: "$api_host"
      ApiKey: "$api_key"
      NodeID: $node_id
      NodeType: $node_type
      Timeout: 30
      SpeedLimit: 0
      DeviceLimit: 0
    ControllerConfig:
      ListenIP: 0.0.0.0
      SendIP: 0.0.0.0
      UpdatePeriodic: 60
$cert_config
      EnableDNS: true
      DNSType: UseIP
      DisableUploadTraffic: false
      DisableGetRule: false
      EnableProxyProtocol: false
      DisableIVCheck: false
      DisableSniffing: false
EOF
)

        all_nodes+="$node_yaml"$'\n'

        echo ""
        read -p "继续添加节点? [Y/n]: " more
        # 回车（空输入）、y、Y 都视为继续
        [[ "$more" =~ ^[Nn]$ ]] && break
    done

    # 6. 生成完整配置文件
    [[ -f "$CONFIG_FILE" ]] && cp "$CONFIG_FILE" "$CONFIG_FILE.bak.$(date +%s)"

    cat <<EOF > "$CONFIG_FILE"
Log:
  Level: warning # Log level: none, error, warning, info, debug 
  AccessPath: # /etc/next-server/access.Log
  ErrorPath: # /etc/next-server/error.log
DnsConfigPath: /etc/next-server/dns.json
RouteConfigPath: /etc/next-server/route.json
InboundConfigPath: # /etc/next-server/custom_inbound.json
OutboundConfigPath: /etc/next-server/custom_outbound.json
ConnectionConfig:
  Handshake: 4
  ConnIdle: 300
  UplinkOnly: 2
  DownlinkOnly: 4
  BufferSize: 64
Nodes:
$all_nodes
EOF

    echo ""
    echo -e "${GREEN}✅ 配置已生成: $CONFIG_FILE${NC}"
    read -p "立即重启服务? [Y/n]: " confirm
    # 回车（空输入）、y、Y 都视为确认
    [[ ! "$confirm" =~ ^[Nn]$ ]] && restart_service
}

function generate_route_rules() {
    echo -e "${BLUE}正在生成路由规则...${NC}"
    mkdir -p "$INSTALL_DIR"
    
    cat <<'EOF' > "$ROUTE_FILE"
{
  "domainStrategy": "IPOnDemand",
  "rules": [
    {
      "type": "field",
      "outboundTag": "block",
      "ip": [
        "geoip:private",
        "127.0.0.1/32",
        "10.0.0.0/8",
        "fc00::/7",
        "fe80::/10",
        "172.16.0.0/12"
      ]
    },
    {
      "type": "field",
      "outboundTag": "block",
      "domain": [
        "regexp:(api|ps|sv|offnavi|newvector|ulog\\.imap|newloc)(\\.map|)\\.(baidu|n\\.shifen)\\.com",
        "regexp:(^|\\.)((360|so)\\.(cn|com))",
        "regexp:(Subject|HELO|SMTP)",
        "regexp:(^|\\.)((guerrillamail|guerrillamailblock|sharklasers|grr|pokemail|spam4|bccto|chacuo|027168)\\.(info|biz|com|de|net|org|me|la))",
        "regexp:(^|\\.)((dafahao|mingjinglive|botanwang|minghui|dongtaiwang|falunaz|epochtimes|ntdtv|falundafa|falungong|wujieliulan|zhengjian)\\.(org|com|net))",
        "regexp:(ed2k|\\.torrent|peer_id=|announce|info_hash|get_peers|find_node|BitTorrent|announce_peer|announce\\.php\\?passkey=|magnet:|xunlei|sandai|Thunder|XLLiveUD|bt_key)",
        "regexp:(^|\\.)((guanjia\\.qq\\.com|qqpcmgr|QQPCMGR))",
        "regexp:(^|\\.)((rising|kingsoft|duba|xindubawukong|jinshanduba)\\.(com|net|org))",
        "regexp:(^|\\.)((netvigator|torproject)\\.(com|cn|net|org))",
        "regexp:(visa|mycard|mastercard|gov|gash|beanfun|bank)",
        "regexp:(^|\\.)((miaozhen|cnzz|talkingdata|umeng)\\.(cn|com))",
        "regexp:(^|\\.)pincong\\.rocks",
        "regexp:(^|\\.)taobao\\.com",
        "regexp:(^|\\.)falundafa",
        "regexp:(^|\\.)minghui",
        "regexp:(^|\\.)epochtimes",
        "regexp:(^|\\.)ntdtv",
        "regexp:(^|\\.)voachinese",
        "regexp:(^|\\.)appledaily",
        "regexp:(^|\\.)nextdigital",
        "regexp:(^|\\.)dalailama",
        "regexp:(^|\\.)nytimes\\.com",
        "regexp:(^|\\.)bloomberg\\.com",
        "regexp:(^|\\.)independent",
        "regexp:(^|\\.)freetibet",
        "regexp:(^|\\.)citizenpowerfor",
        "regexp:(^|\\.)rfa\\.org",
        "regexp:(^|\\.)bbc\\.(com|co\\.uk)",
        "regexp:(^|\\.)theinitium\\.com",
        "regexp:(^|\\.)tibet\\.net",
        "regexp:(^|\\.)jw\\.org",
        "regexp:(^|\\.)bannedbook\\.org",
        "regexp:(^|\\.)dw\\.com",
        "regexp:(^|\\.)storm\\.mg",
        "regexp:(^|\\.)yam\\.com",
        "regexp:(^|\\.)chinadigitaltimes\\.com",
        "regexp:(^|\\.)ltn\\.com\\.tw",
        "regexp:(^|\\.)mpweekly\\.com",
        "regexp:(^|\\.)cup\\.com\\.hk",
        "regexp:(^|\\.)thenewslens\\.com",
        "regexp:(^|\\.)inside\\.com\\.tw",
        "regexp:(^|\\.)everylittled\\.com",
        "regexp:(^|\\.)cool3c\\.com",
        "regexp:(^|\\.)taketla\\.zaiko\\.io",
        "regexp:(^|\\.)news\\.agentm\\.tw",
        "regexp:(^|\\.)sportsv\\.net",
        "regexp:(^|\\.)research\\.tnlmedia\\.com",
        "regexp:(^|\\.)ad2iction\\.com",
        "regexp:(^|\\.)viad\\.com\\.tw",
        "regexp:(^|\\.)tnlmedia\\.com",
        "regexp:(^|\\.)becomingaces\\.com",
        "regexp:(^|\\.)flipboard\\.com",
        "regexp:(^|\\.)soundofhope\\.org",
        "regexp:(^|\\.)wenxuecity\\.com",
        "regexp:(^|\\.)aboluowang\\.com",
        "regexp:(^|\\.)2047\\.name",
        "regexp:(^|\\.)shu\\.best",
        "regexp:(^|\\.)shenyunperformingarts\\.org",
        "regexp:(^|\\.)cirosantilli",
        "regexp:(^|\\.)wsj\\.com",
        "regexp:(^|\\.)rfi\\.fr",
        "regexp:(^|\\.)chinapress\\.com\\.my",
        "regexp:(^|\\.)hancel\\.org",
        "regexp:(^|\\.)miraheze\\.org",
        "regexp:(^|\\.)zhuichaguoji\\.org",
        "regexp:(^|\\.)fawanghuihui\\.org",
        "regexp:(^|\\.)hopto\\.org",
        "regexp:(^|\\.)amnesty\\.org",
        "regexp:(^|\\.)hrw\\.org",
        "regexp:(^|\\.)irmct\\.org",
        "regexp:(^|\\.)zhengjian\\.org",
        "regexp:(^|\\.)dongtaiwang\\.com",
        "regexp:(^|\\.)ultrasurf\\.us",
        "regexp:(^|\\.)yibaochina\\.com",
        "regexp:(^|\\.)roc-taiwan\\.org",
        "regexp:(^|\\.)creaders\\.net",
        "regexp:(^|\\.)upmedia\\.mg",
        "regexp:(^|\\.)ydn\\.com\\.tw",
        "regexp:(^|\\.)udn\\.com",
        "regexp:(^|\\.)theaustralian\\.com\\.au",
        "regexp:(^|\\.)voacantonese\\.com",
        "regexp:(^|\\.)voanews\\.com",
        "regexp:(^|\\.)bitterwinter\\.org",
        "regexp:(^|\\.)christianstudy\\.com",
        "regexp:(^|\\.)learnfalungong\\.com",
        "regexp:(^|\\.)usembassy-china\\.org\\.cn",
        "regexp:(^|\\.)master-li\\.qi-gong\\.me",
        "regexp:(^|\\.)zhengwunet\\.org",
        "regexp:(^|\\.)modernchinastudies\\.org",
        "regexp:(^|\\.)ninecommentaries\\.com",
        "regexp:(^|\\.)dafahao\\.com",
        "regexp:(^|\\.)shenyuncreations\\.com",
        "regexp:(^|\\.)tgcchinese\\.org",
        "regexp:(^|\\.)botanwang\\.com",
        "regexp:(^|\\.)freedomhouse\\.org",
        "regexp:(^|\\.)abc\\.net\\.au",
        "regexp:(^|\\.)funmart\\.beanfun\\.com",
        "regexp:(^|\\.)gashpoint\\.com",
        "regexp:(^|\\.)gov",
        "regexp:(^|\\.)edu",
        "regexp:(^|\\.)alipay\\.com",
        "regexp:(^|\\.)tenpay\\.com",
        "regexp:(^|\\.)unionpay\\.com",
        "regexp:(^|\\.)yunshanfu\\.cn",
        "regexp:(^|\\.)icbc\\.com\\.cn",
        "regexp:(^|\\.)ccb\\.com",
        "regexp:(^|\\.)boc\\.cn",
        "regexp:(^|\\.)bankcomm\\.com",
        "regexp:(^|\\.)abchina\\.com",
        "regexp:(^|\\.)cmbchina\\.com",
        "regexp:(^|\\.)psbc\\.com",
        "regexp:(^|\\.)cebbank\\.com",
        "regexp:(^|\\.)cmbc\\.com\\.cn",
        "regexp:(^|\\.)pingan\\.com",
        "regexp:(^|\\.)spdb\\.com\\.cn",
        "regexp:(^|\\.)bank\\.ecitic\\.com",
        "regexp:(^|\\.)cib\\.com\\.cn",
        "regexp:(^|\\.)hxb\\.com\\.cn",
        "regexp:(^|\\.)cgbchina\\.com\\.cn",
        "regexp:(^|\\.)jcbcard\\.cn",
        "regexp:(^|\\.)pbccrc\\.org\\.cn",
        "regexp:(^|\\.)adbc\\.com\\.cn",
        "regexp:(^|\\.)gamepay\\.com\\.tw",
        "regexp:(^|\\.)10099\\.com\\.cn",
        "regexp:(^|\\.)10010\\.com",
        "regexp:(^|\\.)189\\.cn",
        "regexp:(^|\\.)10086\\.cn",
        "regexp:(^|\\.)1688\\.com",
        "regexp:(^|\\.)jd\\.com",
        "regexp:(^|\\.)pinduoduo\\.com",
        "regexp:(^|\\.)cctv\\.com",
        "regexp:(^|\\.)cntv\\.cn",
        "regexp:(^|\\.)tianya\\.cn",
        "regexp:(^|\\.)tieba\\.baidu\\.com",
        "regexp:(^|\\.)xuexi\\.cn",
        "regexp:(^|\\.)rednet\\.cn",
        "regexp:(^|\\.)weibo\\.com",
        "regexp:(^|\\.)zhihu\\.com",
        "regexp:(^|\\.)douban\\.com",
        "regexp:(^|\\.)tmall\\.com",
        "regexp:(^|\\.)vip\\.com",
        "regexp:(^|\\.)toutiao\\.com",
        "regexp:(^|\\.)zijieapi\\.com",
        "regexp:(^|\\.)xiaomi\\.cn",
        "regexp:(^|\\.)oppo\\.cn",
        "regexp:(^|\\.)oneplusbbs\\.com",
        "regexp:(^|\\.)bbs\\.vivo\\.com\\.cn",
        "regexp:(^|\\.)club\\.lenovo\\.com\\.cn",
        "regexp:(^|\\.)bbs\\.iqoo\\.com",
        "regexp:(^|\\.)realmebbs\\.com",
        "regexp:(^|\\.)rogbbs\\.asus\\.com\\.cn",
        "regexp:(^|\\.)bbs\\.myzte\\.cn",
        "regexp:(^|\\.)club\\.huawei\\.com",
        "regexp:(^|\\.)bbs\\.meizu\\.cn",
        "regexp:(^|\\.)xiaohongshu\\.com",
        "regexp:(^|\\.)coolapk\\.com",
        "regexp:(^|\\.)bbsuc\\.cn",
        "regexp:(^|\\.)tangdou\\.com",
        "regexp:(^|\\.)oneniceapp\\.com",
        "regexp:(^|\\.)izuiyou\\.com",
        "regexp:(^|\\.)pipigx\\.com",
        "regexp:(^|\\.)ixiaochuan\\.cn",
        "regexp:(^|\\.)duitang\\.com",
        "regexp:(^|\\.)renren\\.com",
        "regexp:(^|\\.)meituan\\.net"
      ]
    },
    {
      "type": "field",
      "outboundTag": "block",
      "protocol": ["bittorrent"]
    },
    {
      "type": "field",
      "outboundTag": "block",
      "port": "21,22,110,123,143,389,465,500,587,636,993,995,1701,1723,2375,2376,27017,3306,5432,6443"
    },
    {
      "type": "field",
      "domain": [
        "geosite:speedtest",
        "speed.cloudflare.com",
        "cp.cloudflare.com",
        "fast.com",
        "speedtest.net",
        "api.fast.com",
        "gstatic.com",
        "apple.com",
        "msftconnecttest.com",
        "connectivitycheck.gstatic.com",
        "google.com",
        "fiber.google.com",
        "openspeedtest.com",
        "librespeed.org",
        "dl.google.com"
      ],
      "outboundTag": "direct"
    },    
    {
      "type": "field",
      "inboundTag": ["shadowsocks2022_0.0.0.0_12345"],
      "outboundTag": "aq"
    }
  ]
}
EOF
    
    echo -e "${GREEN}✅ 路由规则已生成: $ROUTE_FILE${NC}"
}

function generate_dns_unlock_config() {
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}            DNS 解锁配置 ${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    output_file="/etc/next-server/dns.json"
    mkdir -p /etc/next-server

    # 菜单显示顺序
    local service_names=(
        "Netflix"
        "YouTube"
        "Disney+"
        "TikTok"
        "ChatGPT"
        "Claude"
        "Gemini"
    )

    # 初始化 JSON 文件头部
    cat > "$output_file" <<'EOF'
{
  "servers": [
    "1.1.1.1",
    "8.8.8.8",
    "localhost"
EOF

    local first_entry=true

    while true; do
        read -p "🌐 DNS 服务器地址 (空回车结束): " address
        [[ -z "$address" ]] && break

        echo ""
        echo "可选解锁服务（空格分隔编号）："
        for i in "${!service_names[@]}"; do
            printf "  ${CYAN}%d${NC}) %s\n" "$((i+1))" "${service_names[$i]}"
        done
        echo ""

        read -p "选择服务 [如: 1 5 7]: " selected_indices
        
        # 临时数组用于存放这一组 DNS 对应的所有域名
        local temp_domains=()

        for idx in $selected_indices; do
            case $idx in
                1) # Netflix
                    temp_domains+=("geosite:netflix")
                    ;;
                2) # YouTube
                    temp_domains+=("geosite:youtube")
                    ;;
                3) # Disney+
                    temp_domains+=("geosite:disney")
                    ;;
                4) # TikTok
                    temp_domains+=("geosite:tiktok")
                    ;;
                5) # ChatGPT
                    temp_domains+=("geosite:openai")
                    ;;
                6) # Claude
                    temp_domains+=("geosite:anthropic")
                    ;;
                7) # Gemini
                    temp_domains+=("geosite:google-deepmind")
                    ;;
            esac
        done

        if [[ ${#temp_domains[@]} -eq 0 ]]; then
            echo -e "${YELLOW}⚠️  未选择有效服务，跳过此 DNS${NC}"
            continue
        fi

        # 数据去重 (防止重复选择)
        IFS=" " read -r -a unique_domains <<< "$(echo "${temp_domains[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' ')"

        # 格式化 JSON 域名列表: "domain1", "domain2"
        local formatted_domains=""
        for ((d=0; d<${#unique_domains[@]}; d++)); do
            formatted_domains+="\"${unique_domains[$d]}\""
            if [[ $d -lt $((${#unique_domains[@]} - 1)) ]]; then
                formatted_domains+=", "
            fi
        done

        # 逗号处理
        if $first_entry; then
            first_entry=false
            echo "," >> "$output_file"
        else
            echo "," >> "$output_file"
        fi

        # 写入配置块
        cat >> "$output_file" <<EOF
    {
      "address": "$address",
      "port": 53,
      "domains": [
        $formatted_domains
      ]
    }
EOF

        read -p "继续添加其他 DNS? [Y/n]: " confirm
        [[ "$confirm" =~ ^[Nn]$ ]] && break
    done

    # 写入 JSON 结尾
    cat >> "$output_file" <<'EOF'
  ],
  "tag": "dns_inbound"
}
EOF

    echo ""
    echo -e "${GREEN}✅ DNS 解锁配置已生成: $output_file${NC}"
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 主菜单循环
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
while true; do
    show_menu
    read -p "请选择操作 [0-13]: " choice
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
            view_config
            ;;
        9)
            diagnose_connection
            ;;
        10)
            generate_self_signed_cert
            ;;
        11)
            generate_route_rules
            ;;
        12)
            generate_node_config
            ;; 
        13)
            generate_dns_unlock_config
            ;;      
        0)
            echo -e "${GREEN}👋 再见！${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}❌ 无效选择，请输入 0-13${NC}"
            ;;
    esac

    echo ""
    read -n 1 -s -r -p "按任意键继续..."
    echo ""
done
