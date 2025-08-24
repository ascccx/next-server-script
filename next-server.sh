#!/bin/bash

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
    # ############### 已修改 부분 ###############
    echo -e "${GREEN}9${NC}. 生成路由规则"
    echo -e "${GREEN}10${NC}. 生成节点配置"
    echo -e "${GREEN}11${NC}. 生成DNS解锁配置"
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

function generate_self_signed_cert() {
    echo -e "${YELLOW}正在生成自签证书...${NC}"
    sudo apt install openssl -y
    sudo mkdir -p /etc/next-server/cert
    sudo openssl req -x509 -nodes -days 365 \
        -newkey rsa:2048 \
        -keyout /etc/next-server/cert/selfsigned.key \
        -out /etc/next-server/cert/selfsigned.crt
    echo -e "${GREEN}自签证书已生成：/etc/next-server/cert/selfsigned.crt${NC}"
}

function generate_node_config() {
    echo -e "${BLUE}=== 生成节点配置文件 ===${NC}"

    if [ ! -d "$INSTALL_DIR" ]; then
        echo -e "${RED}错误：NeXT-Server 尚未安装，请先安装。${NC}"
        return 1
    fi

    local first_api_host=""
    local first_api_key=""

    all_nodes=""

    while true; do
        echo -e "${YELLOW}请输入节点配置信息：${NC}"

        # 面板类型默认为 sspanel-old，不再需要用户选择
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
            first_api_host=$api_host
            first_api_key=$api_key
        else
            echo -e "${GREEN}使用第一个节点的 API 信息：${first_api_host}, ${first_api_key}${NC}"
            api_host=$first_api_host
            api_key=$first_api_key
        fi
        
        read -p "节点ID (NodeID): " node_id
        if [[ -z "$node_id" ]]; then
            echo -e "${RED}错误：节点ID不能为空${NC}"
            continue
        fi

        # 调整节点类型菜单和默认值
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
        Provider:
        Email: xxx@xxx.com
        DNSEnv:
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
  Level: warning # Log level: none, error, warning, info, debug 
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
    cat <<EOF > "$ROUTE_FILE"
{
  "domainStrategy": "IPOnDemand",
  "rules": [
    {
      "type": "field",
      "outboundTag": "block",
      "ip": [
        "geoip:private"
      ]
    },
    {
      "type": "field",
      "outboundTag": "block",
      "domain": [
        "regexp:(api|ps|sv|offnavi|newvector|ulog.imap|newloc)(.map|).(baidu|n.shifen).com",
        "regexp:(.+.|^)(360|so).(cn|com)",
        "regexp:(Subject|HELO|SMTP)",
        "regexp:(torrent|.torrent|peer_id=|info_hash|get_peers|find_node|BitTorrent|announce_peer|announce.php?passkey=)",
        "regexp:(^.@)(guerrillamail|guerrillamailblock|sharklasers|grr|pokemail|spam4|bccto|chacuo|027168).(info|biz|com|de|net|org|me|la)",
        "regexp:(.?)(xunlei|sandai|Thunder|XLLiveUD)(.)",
        "regexp:(..||)(dafahao|mingjinglive|botanwang|minghui|dongtaiwang|falunaz|epochtimes|ntdtv|falundafa|falungong|wujieliulan|zhengjian).(org|com|net)",
        "regexp:(ed2k|.torrent|peer_id=|announce|info_hash|get_peers|find_node|BitTorrent|announce_peer|announce.php?passkey=|magnet:|xunlei|sandai|Thunder|XLLiveUD|bt_key)",
        "regexp:(.*.||)(guanjia.qq.com|qqpcmgr|QQPCMGR)",
        "regexp:(.*.||)(rising|kingsoft|duba|xindubawukong|jinshanduba).(com|net|org)",
        "regexp:(.*.||)(netvigator|torproject).(com|cn|net|org)",
        "regexp:(..||)(visa|mycard|mastercard|gov|gash|beanfun|bank).",
        "regexp:(.*.||)(gov|12377|12315|talk.news.pts.org|creaders|zhuichaguoji|efcc.org|cyberpolice|aboluowang|tuidang|epochtimes|nytimes|zhengjian|110.qq|mingjingnews|inmediahk|xinsheng|breakgfw|chengmingmag|jinpianwang|qi-gong|mhradio|edoors|renminbao|soundofhope|xizang-zhiye|bannedbook|ntdtv|12321|secretchina|dajiyuan|boxun|chinadigitaltimes|dwnews|huaglad|oneplusnews|epochweekly|cn.rfi).(cn|com|org|net|club|net|fr|tw|hk|eu|info|me)",
        "regexp:(.*.||)(miaozhen|cnzz|talkingdata|umeng).(cn|com)",
        "regexp:(.*.||)(mycard).(com|tw)",
        "regexp:(.*.||)(gash).(com|tw)",
        "regexp:(.bank.)",
        "regexp:(.*.||)(pincong).(rocks)",
        "regexp:(.*.||)(taobao).(com)",
        "falundafa",
        "minghui",
        "epochtimes",
        "ntdtv",
        "voachinese",
        "appledaily",
        "nextdigital",
        "dalailama",
        "nytimes",
        "bloomberg",
        "independent",
        "freetibet",
        "citizenpowerfor",
        "rfa.org",
        "bbc.com",
        "theinitium.com",
        "tibet.net",
        "jw.org",
        "bannedbook.org",
        "dw.com",
        "storm.mg",
        "yam.com",
        "chinadigitaltimes",
        "ltn.com.tw",
        "mpweekly.com",
        "cup.com.hk",
        "thenewslens.com",
        "inside.com.tw",
        "everylittled.com",
        "cool3c.com",
        "taketla.zaiko.io",
        "news.agentm.tw",
        "sportsv.net",
        "research.tnlmedia.com",
        "ad2iction.com",
        "viad.com.tw",
        "tnlmedia.com",
        "becomingaces.com",
        "pincong.rocks",
        "flipboard.com",
        "soundofhope.org",
        "wenxuecity.com",
        "aboluowang.com",
        "2047.name",
        "shu.best",
        "shenyunperformingarts.org",
        "bbc.co.uk",
        "cirosantilli",
        "wsj.com",
        "rfi.fr",
        "chinapress.com.my",
        "hancel.org",
        "miraheze.org",
        "zhuichaguoji.org",
        "fawanghuihui.org",
        "hopto.org",
        "amnesty.org",
        "hrw.org",
        "irmct.org",
        "zhengjian.org",
        "wujieliulan.com",
        "dongtaiwang.com",
        "wujieliulan.com",
        "ultrasurf.us",
        "yibaochina.com",
        "roc-taiwan.org",
        "creaders.net",
        "upmedia.mg",
        "ydn.com.tw",
        "udn.com",
        "theaustralian.com.au",
        "rfa.org",
        "voacantonese.com",
        "voanews.com",
        "bitterwinter.org",
        "christianstudy.com",
        "learnfalungong.com",
        "usembassy-china.org.cn",
        "master-li.qi-gong.me",
        "zhengwunet.org",
        "modernchinastudies.org",
        "ninecommentaries.com",
        "dafahao.com",
        "shenyuncreations.com",
        "tgcchinese.org",
        "botanwang.com",
        "falungong",
        "freedomhouse.org",
        "abc.net.au",
        "funmart.beanfun.com",
        "gashpoint.com",
        "gov",
        "edu",
        "alipay.com",
        "tenpay.com",
        "unionpay.com",
        "yunshanfu.cn",
        "icbc.com.cn",
        "ccb.com",
        "boc.cn",
        "bankcomm.com",
        "abchina.com",
        "cmbchina.com",
        "psbc.com",
        "cebbank.com",
        "cmbc.com.cn",
        "pingan.com",
        "spdb.com.cn",
        "bank.ecitic.com",
        "cib.com.cn",
        "hxb.com",
        "cgbchina.com.cn",
        "jcbcard.cn",
        "pbccrc.org.cn",
        "adbc.com.cn",
        "gamepay.com.tw",
        "10099.com.cn",
        "10010.com",
        "189.cn",
        "10086.cn",
        "1688.com",
        "jd.com",
        "taobao.com",
        "pinduoduo.com",
        "cctv.com",
        "cntv.cn",
        "tianya.cn",
        "tieba.baidu.com",
        "xuexi.cn",
        "rednet.cn",
        "weibo.com",
        "zhihu.com",
        "douban.com",
        "tmall.com",
        "vip.com",
        "toutiao.com",
        "zijieapi.com",
        "xiaomi.cn",
        "oppo.cn",
        "oneplusbbs.com",
        "bbs.vivo.com.cn",
        "club.lenovo.com.cn",
        "bbs.iqoo.com",
        "realmebbs.com",
        "rogbbs.asus.com.cn",
        "bbs.myzte.cn",
        "club.huawei.com",
        "bbs.meizu.cn",
        "xiaohongshu.com",
        "coolapk.com",
        "bbsuc.cn",
        "tangdou.com",
        "oneniceapp.com",
        "izuiyou.com",
        "pipigx.com",
        "ixiaochuan.cn",
        "duitang.com",
        "renren.com",
        "acuityplatform.com",
        "ad-stir.com",
        "ad-survey.com",
        "ad4game.com",
        "adcloud.jp",
        "adcolony.com",
        "addthis.com",
        "adfurikun.jp",
        "adhigh.net",
        "adhood.com",
        "adinall.com",
        "adition.com",
        "adk2x.com",
        "admarket.mobi",
        "admarvel.com",
        "admedia.com",
        "adnxs.com",
        "adotmob.com",
        "adperium.com",
        "adriver.ru",
        "adroll.com",
        "adsco.re",
        "adservice.com",
        "adsrvr.org",
        "adsymptotic.com",
        "adtaily.com",
        "adtech.de",
        "adtechjp.com",
        "adtechus.com",
        "airpush.com",
        "am15.net",
        "amobee.com",
        "appier.net",
        "applift.com",
        "apsalar.com",
        "atas.io",
        "awempire.com",
        "axonix.com",
        "beintoo.com",
        "bepolite.eu",
        "bidtheatre.com",
        "bidvertiser.com",
        "blismedia.com",
        "brucelead.com",
        "bttrack.com",
        "casalemedia.com",
        "celtra.com",
        "channeladvisor.com",
        "connexity.net",
        "criteo.com",
        "criteo.net",
        "csbew.com",
        "directrev.com",
        "dumedia.ru",
        "effectivemeasure.com",
        "effectivemeasure.net",
        "eqads.com",
        "everesttech.net",
        "exoclick.com",
        "extend.tv",
        "eyereturn.com",
        "fastapi.net",
        "fastclick.com",
        "fastclick.net",
        "flurry.com",
        "gosquared.com",
        "gtags.net",
        "heyzap.com",
        "histats.com",
        "hitslink.com",
        "hot-mob.com",
        "hyperpromote.com",
        "i-mobile.co.jp",
        "imrworldwide.com",
        "inmobi.com",
        "inner-active.mobi",
        "intentiq.com",
        "inter1ads.com",
        "ipredictive.com",
        "ironsrc.com",
        "iskyworker.com",
        "jizzads.com",
        "juicyads.com",
        "kochava.com",
        "leadbolt.com",
        "leadbolt.net",
        "leadboltads.net",
        "leadboltapps.net",
        "leadboltmobile.net",
        "lenzmx.com",
        "liveadvert.com",
        "marketgid.com",
        "marketo.com",
        "mdotm.com",
        "medialytics.com",
        "medialytics.io",
        "meetrics.com",
        "meetrics.net",
        "mgid.com",
        "millennialmedia.com",
        "mobadme.jp",
        "mobfox.com",
        "mobileadtrading.com",
        "mobilityware.com",
        "mojiva.com",
        "mookie1.com",
        "msads.net",
        "mydas.mobi",
        "nend.net",
        "netshelter.net",
        "nexage.com",
        "owneriq.net",
        "pixels.asia",
        "plista.com",
        "popads.net",
        "powerlinks.com",
        "propellerads.com",
        "quantserve.com",
        "rayjump.com",
        "revdepo.com",
        "rubiconproject.com",
        "sape.ru",
        "scorecardresearch.com",
        "segment.com",
        "serving-sys.com",
        "sharethis.com",
        "smaato.com",
        "smaato.net",
        "smartadserver.com",
        "smartnews-ads.com",
        "startapp.com",
        "startappexchange.com",
        "statcounter.com",
        "steelhousemedia.com",
        "stickyadstv.com",
        "supersonic.com",
        "taboola.com",
        "tapjoy.com",
        "tapjoyads.com",
        "trafficjunky.com",
        "trafficjunky.net",
        "tribalfusion.com",
        "turn.com",
        "uberads.com",
        "vidoomy.com",
        "viglink.com",
        "voicefive.com",
        "wedolook.com",
        "yadro.ru",
        "yengo.com",
        "zedo.com",
        "zemanta.com"
      ]
    },
    {
      "type": "field",
      "outboundTag": "block",
      "ip": [
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
      "protocol": ["bittorrent"]
    },
    {
      "type": "field",
      "outboundTag": "block",
      "port": "21,22,110,123,143,465,587,993,995,389,,500,587,636,993,995,1701,1723,2375,2376,27017,3306,5432,6443"
    }
  ]
}

EOF
    echo -e "${GREEN}路由规则已生成：$ROUTE_FILE${NC}"
}

generate_dns_unlock_config() {
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

  # 写文件头部
  cat > "$output_file" <<EOF
{
  "servers": [
    "1.1.1.1",
    "8.8.8.8",
    "localhost",
EOF

  first_entry=true

  while true; do
    read -rp "请输入一个 DNS 解锁服务器地址（如 154.12.177.22），空回车结束: " address
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

    # 输出逗号处理，首条不加逗号，后续条目前加逗号
    if $first_entry; then
      first_entry=false
      comma=""
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
  echo '
  ],
  "tag": "dns_inbound"
}' >> "$output_file"

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
        # ############### 已修改 부분 ###############
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
