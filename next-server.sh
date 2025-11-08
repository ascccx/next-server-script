#!/bin/bash

# ===============================================
# ⭐️ 自修复逻辑：移除Windows换行符 (CRLF)
# 修复由 DOS/Windows 格式文件在 Linux/Unix 上执行引起的语法错误。
# ===============================================
if [ -f "$0" ]; then
    # 检查是否有 DOS 换行符（\r$）
    if grep -q $'\r$' "$0"; then
        echo -e "\n${YELLOW}检测到 Windows 换行符 (CRLF)，正在自动修正...${NC}"
        # 使用 sed 替换 \r 字符
        sed -i 's/\r//' "$0"
        echo -e "${GREEN}修正完成。请重新运行此脚本。${NC}\n"
        exit 0
    fi
fi
# ===============================================

# 颜色设置
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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
    echo "----------------------------"
    echo -e "${GREEN}8${NC}. 生成自签证书"
    echo "----------------------------"
    echo -e "${GREEN}9${NC}. 生成路由规则"
    echo -e "${GREEN}10${NC}. 生成节点配置"
    echo "----------------------------"
    echo -e "${GREEN}11${NC}. 生成DNS解锁配置"
    echo "----------------------------"
    echo -e "${GREEN}0${NC}. 退出脚本"
}

function download_and_install() {
    echo -e "正在下载 NeXT-Server..."
    if ! wget -q -O /tmp/next-server.zip "$DOWNLOAD_URL"; then
        echo -e "${RED}错误：下载失败，请检查网络连接或下载链接。${NC}"
        return 1
    fi

    echo -e "正在创建安装目录..."
    mkdir -p "$INSTALL_DIR"

    CONFIG_FILES=("config.yml" "custom_inbound.json" "custom_outbound.json" "dns.json" "geoip.dat" "geosite.dat" "next-server" "route.json" "rulelist")
    MISSING_FILES=()

    for file in "${CONFIG_FILES[@]}"; do
        if [ ! -e "$INSTALL_DIR/$file" ]; then
            MISSING_FILES+=("$file")
        fi
    done

    if [ "${#MISSING_FILES[@]}" -eq 0 ]; then
        echo -e "所有配置文件已存在，仅替换 next-server 文件..."
        if ! unzip -o /tmp/next-server.zip next-server -d "$INSTALL_DIR"; then
            echo -e "${RED}错误：解压失败${NC}"
            return 1
        fi
    else
        echo -e "部分配置文件缺失，首次安装或补全缺失文件..."
        if ! unzip -o /tmp/next-server.zip -d "$INSTALL_DIR"; then
            echo -e "${RED}错误：解压失败${NC}"
            return 1
        fi
    fi

    chmod +x "$INSTALL_DIR/next-server"

    if [ -f "$SERVICE_FILE" ]; then
        echo -e "系统服务文件已存在，仅重启 NeXT-Server。"
        sudo systemctl restart next-server
    else
        echo -e "正在创建 systemd 服务文件..."
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

[Install]
WantedBy=multi-user.target
EOF

        echo -e "正在重新加载 systemd 守护进程..."
        sudo systemctl daemon-reload
        sudo systemctl enable next-server
        sudo systemctl start next-server
    fi

    echo -e "NeXT-Server 安装与配置完成。"
}


function start_service() {
    echo -e "正在启动 NeXT-Server..."
    if sudo systemctl start next-server; then
        echo -e "${GREEN}NeXT-Server 已启动。${NC}"
    else
        echo -e "${RED}启动失败，请检查日志。${NC}"
        return 1
    fi
}

function stop_service() {
    echo -e "正在停止 NeXT-Server..."
    if sudo systemctl stop next-server; then
        echo -e "${YELLOW}NeXT-Server 已停止。${NC}"
    else
        echo -e "${RED}停止失败。${NC}"
        return 1
    fi
}

function restart_service() {
    echo -e "正在重启 NeXT-Server..."
    if sudo systemctl restart next-server; then
        echo -e "${GREEN}NeXT-Server 已重启。${NC}"
    else
        echo -e "${RED}重启失败，请检查日志。${NC}"
        return 1
    fi
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
        sudo systemctl stop next-server 2>/dev/null
        sudo systemctl disable next-server 2>/dev/null

        echo -e "正在删除 systemd 服务文件..."
        sudo rm -f "$SERVICE_FILE"

        echo -e "正在删除安装目录..."
        sudo rm -rf "$INSTALL_DIR"

        echo -e "正在重新加载 systemd 守护进程..."
        sudo systemctl daemon-reload

        echo -e "${GREEN}NeXT-Server 已卸载。${NC}"
    else
        echo -e "${YELLOW}卸载已取消。${NC}"
    fi
}

function generate_self_signed_cert() {
    echo -e "${YELLOW}正在生成自签证书...${NC}"
    
    if ! command -v openssl &> /dev/null; then
        echo -e "正在安装 openssl..."
        sudo apt update && sudo apt install openssl -y
    fi
    
    sudo mkdir -p /etc/next-server/cert
    
    if sudo openssl req -x509 -nodes -days 365 \
        -newkey rsa:2048 \
        -keyout /etc/next-server/cert/selfsigned.key \
        -out /etc/next-server/cert/selfsigned.crt; then
        echo -e "${GREEN}自签证书已生成：/etc/next-server/cert/selfsigned.crt${NC}"
    else
        echo -e "${RED}证书生成失败${NC}"
        return 1
    fi
}

function generate_node_config() {
    echo -e "${BLUE}=== 生成节点配置文件 ===${NC}"

    if [ ! -d "$INSTALL_DIR" ]; then
        echo -e "${RED}错误：NeXT-Server 尚未安装，请先安装。${NC}"
        return 1
    fi

    local first_api_host=""
    local first_api_key=""
    local all_nodes=""

    while true; do
        echo -e "${YELLOW}请输入节点配置信息：${NC}"

        # 面板类型默认为 sspanel-old
        local panel_type="sspanel-old"

        if [ -z "$first_api_host" ]; then
            read -p "面板地址 (ApiHost): " api_host
            if [[ -z "$api_host" ]]; then
                echo -e "${RED}错误：面板地址不能为空${NC}"
                continue
            fi

            read -p "API密钥 (ApiKey): " api_key
            if [[ -z "$api_key" ]]; then
                echo -e "${RED}错误：API密钥不能为空${NC}"
                continue
            fi

            # 保存第一个节点的公共配置
            first_api_host="$api_host"
            first_api_key="$api_key"
        else
            echo -e "${GREEN}使用第一个节点的 API 信息：${first_api_host}, ${first_api_key}${NC}"
            api_host="$first_api_host"
            api_key="$first_api_key"
        fi
        
        read -p "节点ID (NodeID): " node_id
        if [[ -z "$node_id" ]]; then
            echo -e "${RED}错误：节点ID不能为空${NC}"
            continue
        fi

        # 节点类型选择
        echo "支持的节点类型："
        echo "  1. shadowsocks2022"
        echo "  2. trojan"
        echo "  3. vmess"
        read -p "选择节点类型 [1-3，默认1]: " node_choice
        case $node_choice in
            2) node_type="trojan" ;;
            3) node_type="vmess" ;;
            *) node_type="shadowsocks2022" ;;
        esac

        node_yaml=$(cat <<EOF
  - PanelType: "$panel_type"
    ApiConfig:
      ApiHost: "$api_host"
      ApiKey: "$api_key"
      NodeID: $node_id
      NodeType: $node_type
      Timeout: 30
      SpeedLimit: 0
      DeviceLimit: 0
      RuleListPath:
    ControllerConfig:
      ListenIP: 0.0.0.0
      SendIP: 0.0.0.0
      UpdatePeriodic: 60
      CertConfig:
        CertMode: file
        CertDomain: "node1.test.com"
        CertFile: /etc/next-server/cert/selfsigned.crt
        KeyFile: /etc/next-server/cert/selfsigned.key
        Provider: cloudflare
        Email: cloudflare@gmail.com
        DNSEnv: 
          CLOUDFLARE_EMAIL: cloudflare@gmail.com
          CLOUDFLARE_API_KEY: 111111111111111111111111111111111111
      EnableDNS: true
      DNSType: UseIP
      DisableUploadTraffic: false
      DisableGetRule: false
      EnableProxyProtocol: false
      DisableIVCheck: false
      DisableSniffing: false
      AutoSpeedLimitConfig:
        Limit: 0
        WarnTimes: 0
        LimitSpeed: 0
        LimitDuration: 0
EOF
)

        all_nodes+="$node_yaml"$'\n'

        read -p "是否继续添加节点？[Y/n]: " more
        [[ "$more" =~ ^[Nn]$ ]] && break
    done

    if [[ -z "$all_nodes" ]]; then
        echo -e "${RED}没有输入任何节点配置，取消生成。${NC}"
        return 1
    fi

    [[ -f "$CONFIG_FILE" ]] && cp "$CONFIG_FILE" "$CONFIG_FILE.bak.$(date +%s)"

    cat <<EOF > "$CONFIG_FILE"
Log:
  Level: debug # Log level: none, error, warning, info, debug 
  AccessPath: # /etc/next-server/access.Log
  ErrorPath: # /etc/next-server/error.log
DnsConfigPath: /etc/next-server/dns.json
RouteConfigPath: /etc/next-server/route.json
InboundConfigPath: # /etc/next-server/custom_inbound.json
OutboundConfigPath: /etc/next-server/custom_outbound.json
ConnectionConfig:
  Handshake: 4 # Handshake time limit, Second
  ConnIdle: 30 # Connection idle time limit, Second
  UplinkOnly: 2 # Time limit when the connection downstream is closed, Second
  DownlinkOnly: 4 # Time limit when the connection is closed after the uplink is closed, Second
  BufferSize: 64 # The internal cache size of each connection, kB
Nodes:
$all_nodes
EOF

    echo -e "${GREEN}配置已生成：$CONFIG_FILE${NC}"
    read -p "是否立即重启以应用配置？[y/N]: " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] && restart_service
}

function generate_route_rules() {
    echo -e "${BLUE}=== 生成路由规则 ===${NC}"
    mkdir -p "$INSTALL_DIR"
    
    # 修复：端口字段添加引号，符合 JSON 标准
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
        "regexp:(^|\\.)renren\\.com"
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
      "outboundTag": "tw"
    }
  ]
}
EOF
    
    echo -e "${GREEN}路由规则已生成：$ROUTE_FILE${NC}"
}

function generate_dns_unlock_config() {
    echo "📥 正在生成 DNS 解锁配置..."

    output_file="/etc/next-server/dns.json"
    mkdir -p /etc/next-server

    declare -A domain_map=(
        [1]="geosite:category-ai-chat-!cn"
        [2]="geosite:netflix"
        [3]="geosite:disney"
        [4]="geosite:tiktok"
        [5]="geosite:youtube"
        [6]="geosite:spotify"
    )

    # 写入文件头部
    cat > "$output_file" <<'EOF'
{
  "servers": [
    "1.1.1.1",
    "8.8.8.8",
    "localhost"
EOF

    first_entry=true

    while true; do
        read -rp "请输入一个 DNS 解锁服务器地址（如 54.40.61.210），空回车结束: " address
        [[ -z "$address" ]] && break

        echo "📑 可选 geosite 域（空格分隔编号，支持多选）："
        for i in $(seq 1 ${#domain_map[@]}); do
            printf "  %d) %s\n" "$i" "${domain_map[$i]}"
        done

        read -rp "请输入要匹配的域编号: " selected_indices_raw
        selected_domains=()
        for idx in $selected_indices_raw; do
            domain="${domain_map[$idx]}"
            if [[ -n "$domain" ]]; then
                selected_domains+=("\"$domain\"")
            fi
        done

        if [[ ${#selected_domains[@]} -eq 0 ]]; then
            echo "⚠️ 没有选择任何有效的域名，跳过该服务器地址"
            continue
        fi

        domain_json=$(IFS=,; echo "${selected_domains[*]}")

        # 处理 JSON 逗号：如果是第一个自定义服务器，前面需要逗号
        if $first_entry; then
            first_entry=false
            comma=","
        else
            comma=","
        fi

        cat >> "$output_file" <<EOF
${comma}
    {
      "address": "$address",
      "port": 53,
      "domains": [
        $domain_json
      ]
    }
EOF

        read -rp "是否继续添加下一个 DNS 解锁服务器地址？(y/n): " confirm
        [[ "$confirm" != [yY] ]] && break
    done

    # 文件尾部
    cat >> "$output_file" <<'EOF'
  ],
  "tag": "dns_inbound"
}
EOF

    echo "✅ DNS 解锁配置已生成：$output_file"
}

# 主菜单循环
while true; do
    show_menu
    read -p "请输入操作编号: " choice
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
            generate_self_signed_cert
            ;;
        9)
            generate_route_rules
            ;;
        10)
            generate_node_config
            ;; 
        11)
            generate_dns_unlock_config
            ;;      
        0)
            echo -e "${GREEN}退出脚本...${NC}"
            exit 0
            ;;
        *)
            echo -e "${YELLOW}无效的选择，请输入 0 到 11 之间的数字。${NC}"
            ;;
    esac

    read -n 1 -s -r -p "按任意键继续..."
    echo ""
done
