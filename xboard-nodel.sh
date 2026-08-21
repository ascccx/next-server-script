#!/usr/bin/env bash
# Xboard-Node node-mode installer and manager.
# Supports only panel node bindings; machine mode is intentionally excluded.

set -Eeuo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

APP_NAME='xboard-node'
INSTALL_ROOT='/etc/xboard-node'
BACKUP_ROOT="${INSTALL_ROOT}/backups"
CONFIG_FILE="${INSTALL_ROOT}/config.yml"
CREDENTIALS_FILE="${INSTALL_ROOT}/credentials.env"
META_FILE="${INSTALL_ROOT}/install-meta.json"
CUSTOM_CONFIG_FILE="${INSTALL_ROOT}/custom.json"
CERT_STORAGE_DIR="${INSTALL_ROOT}/instances/certs"
BINARY_PATH='/usr/local/bin/xboard-node'
CLI_PATH='/usr/local/bin/xbctl'
SERVICE_NAME='xboard-node.service'
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}"
MANAGER_SCRIPT_PATH='/usr/local/lib/xboard-node/xboard-node-install.sh'
SHORTCUT_PATH='/usr/local/bin/x'
RELEASE_BASE='https://github.com/cedar2025/xboard-node/releases'
DEFAULT_HEALTH_PORT=65530

ARCH=''
HEALTH_PORT="$DEFAULT_HEALTH_PORT"
BACKUP_PATH=''
HAD_PREVIOUS_STATE=0
INSTALL_CERTIFICATE_BLOCK=''

info() { echo -e "${GREEN}[信息]${NC} $*"; }
warn() { echo -e "${YELLOW}[警告]${NC} $*"; }
error() { echo -e "${RED}[错误]${NC} $*" >&2; }

cleanup_crlf() {
    if [ -f "$0" ] && grep -q $'\r$' "$0"; then
        sed -i 's/\r$//' "$0"
        info '已修复 Windows 换行符，请重新运行脚本。'
        exit 0
    fi
}

install_shortcut() {
    local source_path shortcut_target

    source_path="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || true)"
    if [ ! -f "$source_path" ]; then
        warn '当前脚本通过管道运行，无法创建快捷命令。请先保存脚本文件后再运行一次。'
        return
    fi
    if [ -e "$SHORTCUT_PATH" ] && [ ! -L "$SHORTCUT_PATH" ]; then
        shortcut_target="$(readlink -f "$SHORTCUT_PATH")"
        if [ "$shortcut_target" != "$MANAGER_SCRIPT_PATH" ]; then
            warn "快捷命令 x 已被 ${shortcut_target} 占用，未覆盖。"
            return
        fi
    fi

    install -d -m 755 "$(dirname "$MANAGER_SCRIPT_PATH")"
    if [ "$source_path" != "$MANAGER_SCRIPT_PATH" ]; then
        install -m 700 "$source_path" "$MANAGER_SCRIPT_PATH"
    fi
    ln -sfn "$MANAGER_SCRIPT_PATH" "$SHORTCUT_PATH"
    info '快捷命令已安装：输入 x 可打开节点管理菜单。'
}

require_root() {
    if [ "$(id -u)" -ne 0 ]; then
        error '请使用 root 运行，例如：sudo bash xboard-node-install.sh'
        exit 1
    fi
}

require_systemd() {
    if ! command -v systemctl >/dev/null 2>&1 || [ ! -d /run/systemd/system ]; then
        error '此脚本需要在使用 systemd 的 Linux 服务器上运行。'
        exit 1
    fi
}

detect_arch() {
    case "$(uname -m)" in
        x86_64|amd64) ARCH='amd64' ;;
        aarch64|arm64) ARCH='arm64' ;;
        *)
            error "不支持当前架构：$(uname -m)。仅支持 amd64 和 arm64。"
            exit 1
            ;;
    esac
}

install_dependencies() {
    local missing=()
    command -v curl >/dev/null 2>&1 || missing+=('curl')
    command -v python3 >/dev/null 2>&1 || missing+=('python3')
    if [ "${#missing[@]}" -eq 0 ]; then
        return
    fi

    info "正在安装所需组件：${missing[*]}"
    if command -v apt-get >/dev/null 2>&1; then
        DEBIAN_FRONTEND=noninteractive apt-get update -qq
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq curl ca-certificates python3
    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y -q curl ca-certificates python3
    elif command -v yum >/dev/null 2>&1; then
        yum install -y -q curl ca-certificates python3
    else
        error '缺少 curl 或 python3，且未找到支持的包管理器。'
        exit 1
    fi
}

new_stage_dir() {
    mktemp -d
}

download_binaries() {
    local stage_dir="$1"
    local version="${2:-latest}"
    local base_url

    if [ "$version" = 'latest' ]; then
        base_url="${RELEASE_BASE}/latest/download"
    else
        base_url="${RELEASE_BASE}/download/${version}"
    fi

    info "正在下载 ${ARCH} 架构的 Xboard-Node ${version}"
    curl -fL --retry 3 --connect-timeout 15 \
        "${base_url}/xboard-node-linux-${ARCH}" -o "${stage_dir}/xboard-node"
    curl -fL --retry 3 --connect-timeout 15 \
        "${base_url}/xbctl-linux-${ARCH}" -o "${stage_dir}/xbctl"
    chmod 755 "${stage_dir}/xboard-node" "${stage_dir}/xbctl"

    "${stage_dir}/xboard-node" -v >/dev/null
    "${stage_dir}/xbctl" version >/dev/null
}

backup_current() {
    BACKUP_PATH="${BACKUP_ROOT}/$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$BACKUP_PATH"

    HAD_PREVIOUS_STATE=0
    if [ -f "$BINARY_PATH" ]; then cp -a "$BINARY_PATH" "${BACKUP_PATH}/xboard-node"; HAD_PREVIOUS_STATE=1; fi
    if [ -f "$CLI_PATH" ]; then cp -a "$CLI_PATH" "${BACKUP_PATH}/xbctl"; HAD_PREVIOUS_STATE=1; fi
    if [ -f "$CONFIG_FILE" ]; then cp -a "$CONFIG_FILE" "${BACKUP_PATH}/config.yml"; HAD_PREVIOUS_STATE=1; fi
    if [ -f "$CREDENTIALS_FILE" ]; then cp -a "$CREDENTIALS_FILE" "${BACKUP_PATH}/credentials.env"; HAD_PREVIOUS_STATE=1; fi
    if [ -f "$META_FILE" ]; then cp -a "$META_FILE" "${BACKUP_PATH}/install-meta.json"; HAD_PREVIOUS_STATE=1; fi
    if [ -f "$CUSTOM_CONFIG_FILE" ]; then cp -a "$CUSTOM_CONFIG_FILE" "${BACKUP_PATH}/custom.json"; HAD_PREVIOUS_STATE=1; fi
    if [ -f "$SERVICE_FILE" ]; then cp -a "$SERVICE_FILE" "${BACKUP_PATH}/${SERVICE_NAME}"; HAD_PREVIOUS_STATE=1; fi
}

restore_backup() {
    [ -n "$BACKUP_PATH" ] && [ -d "$BACKUP_PATH" ] || return 1
    if [ "$HAD_PREVIOUS_STATE" -eq 0 ]; then
        warn '正在清理未完成的首次安装。'
        systemctl stop "$SERVICE_NAME" >/dev/null 2>&1 || true
        systemctl disable "$SERVICE_NAME" >/dev/null 2>&1 || true
        rm -f "$SERVICE_FILE" "$BINARY_PATH" "$CLI_PATH" "$CONFIG_FILE" "$CREDENTIALS_FILE" "$META_FILE" "$CUSTOM_CONFIG_FILE"
        [ -L /usr/bin/xbctl ] && rm -f /usr/bin/xbctl
        systemctl daemon-reload
        return 0
    fi
    warn "正在从备份恢复：${BACKUP_PATH}"

    [ -f "${BACKUP_PATH}/xboard-node" ] && install -m 755 "${BACKUP_PATH}/xboard-node" "$BINARY_PATH"
    [ -f "${BACKUP_PATH}/xbctl" ] && install -m 755 "${BACKUP_PATH}/xbctl" "$CLI_PATH"
    [ -f "${BACKUP_PATH}/config.yml" ] && install -m 600 "${BACKUP_PATH}/config.yml" "$CONFIG_FILE"
    [ -f "${BACKUP_PATH}/credentials.env" ] && install -m 600 "${BACKUP_PATH}/credentials.env" "$CREDENTIALS_FILE"
    [ -f "${BACKUP_PATH}/install-meta.json" ] && install -m 644 "${BACKUP_PATH}/install-meta.json" "$META_FILE"
    [ -f "${BACKUP_PATH}/custom.json" ] && install -m 600 "${BACKUP_PATH}/custom.json" "$CUSTOM_CONFIG_FILE"
    [ -f "${BACKUP_PATH}/${SERVICE_NAME}" ] && install -m 644 "${BACKUP_PATH}/${SERVICE_NAME}" "$SERVICE_FILE"
    systemctl daemon-reload
    systemctl restart "$SERVICE_NAME" >/dev/null 2>&1 || true
}

write_service_file() {
    local output_path="$1"
    cat >"$output_path" <<EOF
[Unit]
Description=Xboard Node Backend
Documentation=https://github.com/cedar2025/xboard-node
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=${INSTALL_ROOT}
EnvironmentFile=-${CREDENTIALS_FILE}
ExecStart=${BINARY_PATH} -c ${CONFIG_FILE}
Restart=always
RestartSec=5
LimitNOFILE=1048576
NoNewPrivileges=true
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
}

write_route_template() {
    local output_path="$1"
    cat >"$output_path" <<'ROUTE_RULES'
{
  "outbounds": [
    {
      "type": "direct",
      "tag": "IPv4_out"
    },
    {
      "type": "direct",
      "tag": "IPv6_out",
      "domain_strategy": "prefer_ipv6"
    }
  ],
  "route": {
    "rules": [
      {
        "ip_cidr": [
          "127.0.0.1/32",
          "10.0.0.0/8",
          "172.16.0.0/12",
          "192.168.0.0/16",
          "fc00::/7",
          "fe80::/10"
        ],
        "ip_is_private": true,
        "action": "reject"
      },
      {
        "domain_regex": [
          "(api|ps|sv|offnavi|newvector|ulog\\.imap|newloc)(\\.map|)\\.(baidu|n\\.shifen)\\.com",
          "(^|\\.)((360|so)\\.(cn|com))",
          "(^|\\.)((guerrillamail|guerrillamailblock|sharklasers|grr|pokemail|spam4|bccto|chacuo|027168)\\.(info|biz|com|de|net|org|me|la))",
          "(^|\\.)((dafahao|mingjinglive|botanwang|minghui|dongtaiwang|falunaz|epochtimes|ntdtv|falundafa|falungong|wujieliulan|zhengjian)\\.(org|com|net))",
          "(ed2k|\\.torrent|peer_id=|announce|info_hash|get_peers|find_node|BitTorrent|announce_peer|announce\\.php\\?passkey=|magnet:|xunlei|sandai|Thunder|XLLiveUD|bt_key)",
          "(^|\\.)((guanjia\\.qq\\.com|qqpcmgr|QQPCMGR))",
          "(^|\\.)((rising|kingsoft|duba|xindubawukong|jinshanduba)\\.(com|net|org))",
          "(^|\\.)((netvigator|torproject)\\.(com|cn|net|org))",
          "(visa|mycard|mastercard|gov|gash|beanfun|bank)",
          "(^|\\.)((miaozhen|cnzz|talkingdata|umeng)\\.(cn|com))",
          "(^|\\.)pincong\\.rocks",
          "(^|\\.)taobao\\.com",
          "(^|\\.)falundafa",
          "(^|\\.)minghui",
          "(^|\\.)epochtimes",
          "(^|\\.)ntdtv",
          "(^|\\.)voachinese",
          "(^|\\.)appledaily",
          "(^|\\.)nextdigital",
          "(^|\\.)dalailama",
          "(^|\\.)nytimes\\.com",
          "(^|\\.)bloomberg\\.com",
          "(^|\\.)independent",
          "(^|\\.)freetibet",
          "(^|\\.)citizenpowerfor",
          "(^|\\.)rfa\\.org",
          "(^|\\.)bbc\\.(com|co\\.uk)",
          "(^|\\.)theinitium\\.com",
          "(^|\\.)tibet\\.net",
          "(^|\\.)jw\\.org",
          "(^|\\.)bannedbook\\.org",
          "(^|\\.)dw\\.com",
          "(^|\\.)storm\\.mg",
          "(^|\\.)yam\\.com",
          "(^|\\.)chinadigitaltimes\\.com",
          "(^|\\.)ltn\\.com\\.tw",
          "(^|\\.)mpweekly\\.com",
          "(^|\\.)cup\\.com\\.hk",
          "(^|\\.)thenewslens\\.com",
          "(^|\\.)inside\\.com\\.tw",
          "(^|\\.)everylittled\\.com",
          "(^|\\.)cool3c\\.com",
          "(^|\\.)taketla\\.zaiko\\.io",
          "(^|\\.)news\\.agentm\\.tw",
          "(^|\\.)sportsv\\.net",
          "(^|\\.)research\\.tnlmedia\\.com",
          "(^|\\.)ad2iction\\.com",
          "(^|\\.)viad\\.com\\.tw",
          "(^|\\.)tnlmedia\\.com",
          "(^|\\.)becomingaces\\.com",
          "(^|\\.)flipboard\\.com",
          "(^|\\.)soundofhope\\.org",
          "(^|\\.)wenxuecity\\.com",
          "(^|\\.)aboluowang\\.com",
          "(^|\\.)2047\\.name",
          "(^|\\.)shu\\.best",
          "(^|\\.)shenyunperformingarts\\.org",
          "(^|\\.)cirosantilli",
          "(^|\\.)wsj\\.com",
          "(^|\\.)rfi\\.fr",
          "(^|\\.)chinapress\\.com\\.my",
          "(^|\\.)hancel\\.org",
          "(^|\\.)miraheze\\.org",
          "(^|\\.)zhuichaguoji\\.org",
          "(^|\\.)fawanghuihui\\.org",
          "(^|\\.)hopto\\.org",
          "(^|\\.)amnesty\\.org",
          "(^|\\.)hrw\\.org",
          "(^|\\.)irmct\\.org",
          "(^|\\.)zhengjian\\.org",
          "(^|\\.)dongtaiwang\\.com",
          "(^|\\.)ultrasurf\\.us",
          "(^|\\.)yibaochina\\.com",
          "(^|\\.)roc-taiwan\\.org",
          "(^|\\.)creaders\\.net",
          "(^|\\.)upmedia\\.mg",
          "(^|\\.)ydn\\.com\\.tw",
          "(^|\\.)udn\\.com",
          "(^|\\.)theaustralian\\.com\\.au",
          "(^|\\.)voacantonese\\.com",
          "(^|\\.)voanews\\.com",
          "(^|\\.)bitterwinter\\.org",
          "(^|\\.)christianstudy\\.com",
          "(^|\\.)learnfalungong\\.com",
          "(^|\\.)usembassy-china\\.org\\.cn",
          "(^|\\.)master-li\\.qi-gong\\.me",
          "(^|\\.)zhengwunet\\.org",
          "(^|\\.)modernchinastudies\\.org",
          "(^|\\.)ninecommentaries\\.com",
          "(^|\\.)dafahao\\.com",
          "(^|\\.)shenyuncreations\\.com",
          "(^|\\.)tgcchinese\\.org",
          "(^|\\.)botanwang\\.com",
          "(^|\\.)freedomhouse\\.org",
          "(^|\\.)abc\\.net\\.au",
          "(^|\\.)funmart\\.beanfun\\.com",
          "(^|\\.)gashpoint\\.com",
          "(^|\\.)gov",
          "(^|\\.)edu",
          "(^|\\.)alipay\\.com",
          "(^|\\.)tenpay\\.com",
          "(^|\\.)unionpay\\.com",
          "(^|\\.)yunshanfu\\.cn",
          "(^|\\.)icbc\\.com\\.cn",
          "(^|\\.)ccb\\.com",
          "(^|\\.)boc\\.cn",
          "(^|\\.)bankcomm\\.com",
          "(^|\\.)abchina\\.com",
          "(^|\\.)cmbchina\\.com",
          "(^|\\.)psbc\\.com",
          "(^|\\.)cebbank\\.com",
          "(^|\\.)cmbc\\.com\\.cn",
          "(^|\\.)pingan\\.com",
          "(^|\\.)spdb\\.com\\.cn",
          "(^|\\.)bank\\.ecitic\\.com",
          "(^|\\.)cib\\.com\\.cn",
          "(^|\\.)hxb\\.com\\.cn",
          "(^|\\.)cgbchina\\.com\\.cn",
          "(^|\\.)jcbcard\\.cn",
          "(^|\\.)pbccrc\\.org\\.cn",
          "(^|\\.)adbc\\.com\\.cn",
          "(^|\\.)gamepay\\.com\\.tw",
          "(^|\\.)10099\\.com\\.cn",
          "(^|\\.)10010\\.com",
          "(^|\\.)189\\.cn",
          "(^|\\.)10086\\.cn",
          "(^|\\.)1688\\.com",
          "(^|\\.)jd\\.com",
          "(^|\\.)pinduoduo\\.com",
          "(^|\\.)cctv\\.com",
          "(^|\\.)cntv\\.cn",
          "(^|\\.)tianya\\.cn",
          "(^|\\.)tieba\\.baidu\\.com",
          "(^|\\.)xuexi\\.cn",
          "(^|\\.)rednet\\.cn",
          "(^|\\.)weibo\\.com",
          "(^|\\.)zhihu\\.com",
          "(^|\\.)douban\\.com",
          "(^|\\.)tmall\\.com",
          "(^|\\.)vip\\.com",
          "(^|\\.)toutiao\\.com",
          "(^|\\.)zijieapi\\.com",
          "(^|\\.)xiaomi\\.cn",
          "(^|\\.)oppo\\.cn",
          "(^|\\.)oneplusbbs\\.com",
          "(^|\\.)bbs\\.vivo\\.com\\.cn",
          "(^|\\.)club\\.lenovo\\.com\\.cn",
          "(^|\\.)bbs\\.iqoo\\.com",
          "(^|\\.)realmebbs\\.com",
          "(^|\\.)rogbbs\\.asus\\.com\\.cn",
          "(^|\\.)bbs\\.myzte\\.cn",
          "(^|\\.)club\\.huawei\\.com",
          "(^|\\.)bbs\\.meizu\\.cn",
          "(^|\\.)xiaohongshu\\.com",
          "(^|\\.)coolapk\\.com",
          "(^|\\.)bbsuc\\.cn",
          "(^|\\.)tangdou\\.com",
          "(^|\\.)oneniceapp\\.com",
          "(^|\\.)izuiyou\\.com",
          "(^|\\.)pipigx\\.com",
          "(^|\\.)ixiaochuan\\.cn",
          "(^|\\.)duitang\\.com",
          "(^|\\.)renren\\.com",
          "(^|\\.)meituan\\.net"
        ],
        "action": "reject"
      },
      {
        "protocol": "bittorrent",
        "action": "reject"
      },
      {
        "port": [21, 22, 110, 123, 143, 389, 465, 500, 587, 636, 993, 995, 1701, 1723, 2375, 2376, 27017, 3306, 5432, 6443],
        "action": "reject"
      },
      {
        "domain_suffix": [
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
        "outbound": "IPv4_out"
      }
    ]
  }
}
ROUTE_RULES
}

enable_custom_config() {
    local config_path="$1"
    local custom_path="$2"
    local temp_path

    temp_path="$(mktemp)"
    awk -v custom_path="$custom_path" '
        /^[[:space:]]*custom_config:[[:space:]]*/ { next }
        { print }
        /^[[:space:]]*config_dir:[[:space:]]*/ {
            match($0, /^[[:space:]]*/)
            print substr($0, 1, RLENGTH) "custom_config: \"" custom_path "\""
        }
    ' "$config_path" >"$temp_path"
    install -m 600 "$temp_path" "$config_path"
    rm -f "$temp_path"
}

require_singbox_config() {
    if grep -qE '^[[:space:]]*type:[[:space:]]*xray[[:space:]]*$' "$CONFIG_FILE"; then
        error '本脚本仅支持 sing-box，请先使用菜单 1 重新配置节点。'
        return 1
    fi
}

apply_custom_config() {
    local health_port
    if [ ! -f "$CONFIG_FILE" ]; then
        error '请先安装节点，再配置路由或 DNS。'
        return 1
    fi
    require_singbox_config
    enable_custom_config "$CONFIG_FILE" "$CUSTOM_CONFIG_FILE"
    health_port="$(current_health_port)"
    health_port="${health_port:-$DEFAULT_HEALTH_PORT}"
    if ! systemctl restart "$SERVICE_NAME" || ! wait_for_health "$health_port"; then
        error '自定义配置加载失败，服务健康检查未通过。'
        show_recent_logs
        restore_backup || true
        return 1
    fi
}

current_health_port() {
    if [ -x "$CLI_PATH" ] && [ -f "$CONFIG_FILE" ]; then
        "$CLI_PATH" config health-port --config "$CONFIG_FILE" 2>/dev/null || true
    fi
}

wait_for_health() {
    local health_port="$1"
    local attempt=0

    while [ "$attempt" -lt 30 ]; do
        if ! systemctl is-active --quiet "$SERVICE_NAME"; then
            return 1
        fi
        if [ "$health_port" = '0' ] || curl -fsS "http://127.0.0.1:${health_port}/healthz" >/dev/null 2>&1; then
            return 0
        fi
        sleep 1
        attempt=$((attempt + 1))
    done
    return 1
}

show_certificate_files() {
    local cert_file="${CERT_STORAGE_DIR}/cert.pem"
    local key_file="${CERT_STORAGE_DIR}/key.pem"

    if [ -f "$cert_file" ] && [ -f "$key_file" ]; then
        info "证书已生成：${cert_file}"
        info "私钥位置：${key_file}"
    else
        warn '未检测到已落盘的证书文件，请使用菜单 6 查看服务日志。'
    fi
}

show_recent_logs() {
    journalctl -u "$SERVICE_NAME" -n 40 --no-pager || true
}

read_node_details() {
    local existing_port certificate_answer certificate_domain

    read -r -p '面板地址（例如 https://panel.example.com）：' PANEL_URL
    while [ -z "$PANEL_URL" ]; do
        error '面板地址不能为空。'
        read -r -p '面板地址：' PANEL_URL
    done

    read -r -s -p '面板接口密钥（API Token）：' PANEL_TOKEN
    echo
    while [ -z "$PANEL_TOKEN" ]; do
        error '面板接口密钥不能为空。'
        read -r -s -p '面板接口密钥（API Token）：' PANEL_TOKEN
        echo
    done

    read -r -p '节点 ID：' NODE_ID
    while ! [[ "$NODE_ID" =~ ^[1-9][0-9]*$ ]]; do
        error '节点 ID 必须为正整数。'
        read -r -p '节点 ID：' NODE_ID
    done

    info '内核：sing-box'

    read -r -p '节点类型（可留空，由面板自动识别）：' NODE_TYPE

    existing_port="$(current_health_port)"
    if [[ "$existing_port" =~ ^[0-9]+$ ]]; then
        HEALTH_PORT="$existing_port"
        info "沿用现有健康检查端口：${HEALTH_PORT}"
    else
        read -r -p "本地健康检查端口 [${DEFAULT_HEALTH_PORT}；输入 0 禁用]：" HEALTH_PORT
        HEALTH_PORT="${HEALTH_PORT:-$DEFAULT_HEALTH_PORT}"
        while ! [[ "$HEALTH_PORT" =~ ^[0-9]+$ ]] || [ "$HEALTH_PORT" -gt 65535 ]; do
            error '健康检查端口必须介于 0 和 65535 之间。'
            read -r -p "本地健康检查端口 [${DEFAULT_HEALTH_PORT}；输入 0 禁用]：" HEALTH_PORT
            HEALTH_PORT="${HEALTH_PORT:-$DEFAULT_HEALTH_PORT}"
        done
    fi

    while true; do
        read -r -p '是否为节点生成自签名证书？[直接回车/输入 y/是：生成；输入 n/否：不生成]：' certificate_answer
        certificate_answer="${certificate_answer//[[:space:]]/}"
        if [[ "$certificate_answer" =~ ^([Nn]|否)$ ]]; then
            INSTALL_CERTIFICATE_BLOCK=''
            info '本次安装不配置证书，可在安装后使用菜单 13 配置。'
            break
        fi
        if [ -n "$certificate_answer" ] && [[ ! "$certificate_answer" =~ ^([Yy]|是)$ ]]; then
            error '无效选择，请直接回车生成自签名证书，或输入 n/否取消。'
            continue
        fi

        read -r -p '自签名证书域名 [localhost]：' certificate_domain
        certificate_domain="${certificate_domain:-localhost}"
        if [ "$certificate_domain" != 'localhost' ] && ! valid_certificate_domain "$certificate_domain"; then
            error '域名格式不正确。'
            continue
        fi
        INSTALL_CERTIFICATE_BLOCK="cert:
  cert_mode: \"self\"
  domain: $(yaml_quote "$certificate_domain")"
        break
    done
}

render_node_config() {
    local stage_dir="$1"
    local init_args=(
        config init
        --mode node
        --panel-url "$PANEL_URL"
        --token "$PANEL_TOKEN"
        --node-id "$NODE_ID"
        --kernel singbox
        --health-port "$HEALTH_PORT"
        --version latest
        --output "${stage_dir}/config.yml"
        --credentials-out "${stage_dir}/credentials.env"
        --meta "${stage_dir}/install-meta.json"
        --install-root "$INSTALL_ROOT"
    )

    if [ -n "$NODE_TYPE" ]; then
        init_args+=(--node-type "$NODE_TYPE")
    fi
    if [ -f "$CONFIG_FILE" ]; then
        init_args+=(--config "$CONFIG_FILE")
    fi
    if [ -f "$CREDENTIALS_FILE" ]; then
        init_args+=(--credentials-in "$CREDENTIALS_FILE")
    fi

    "${stage_dir}/xbctl" "${init_args[@]}"
    sed -i -E 's/^([[:space:]]*type:[[:space:]]*)xray[[:space:]]*$/\1singbox/' "${stage_dir}/config.yml"
    if [ -n "$INSTALL_CERTIFICATE_BLOCK" ]; then
        write_top_level_cert_config "$INSTALL_CERTIFICATE_BLOCK" "${stage_dir}/config.yml"
    fi
    if [ -f "$CUSTOM_CONFIG_FILE" ]; then
        enable_custom_config "${stage_dir}/config.yml" "$CUSTOM_CONFIG_FILE"
    fi
    chmod 600 "${stage_dir}/credentials.env"
}

install_node() {
    local stage_dir
    read_node_details
    stage_dir="$(new_stage_dir)"

    if ! download_binaries "$stage_dir"; then
        rm -rf "$stage_dir"
        return 1
    fi
    mkdir -p "$INSTALL_ROOT" "$BACKUP_ROOT"
    chmod 700 "$INSTALL_ROOT"
    if ! render_node_config "$stage_dir"; then
        error '节点配置生成失败。'
        rm -rf "$stage_dir"
        return 1
    fi
    write_service_file "${stage_dir}/${SERVICE_NAME}"
    backup_current

    systemctl stop "$SERVICE_NAME" >/dev/null 2>&1 || true
    install -m 755 "${stage_dir}/xboard-node" "$BINARY_PATH"
    install -m 755 "${stage_dir}/xbctl" "$CLI_PATH"
    ln -sfn "$CLI_PATH" /usr/bin/xbctl
    install -m 600 "${stage_dir}/config.yml" "$CONFIG_FILE"
    install -m 600 "${stage_dir}/credentials.env" "$CREDENTIALS_FILE"
    install -m 644 "${stage_dir}/install-meta.json" "$META_FILE"
    install -m 644 "${stage_dir}/${SERVICE_NAME}" "$SERVICE_FILE"
    systemctl daemon-reload
    systemctl enable "$SERVICE_NAME" >/dev/null

    if ! systemctl restart "$SERVICE_NAME" || ! wait_for_health "$HEALTH_PORT"; then
        error '节点健康检查未通过，正在显示最近日志。'
        show_recent_logs
        restore_backup || true
        error '已在存在备份时恢复原有安装。'
        rm -rf "$stage_dir"
        return 1
    fi

    rm -rf "$stage_dir"
    info '节点安装/配置完成。'
    info "服务：${SERVICE_NAME}"
    info "配置文件：${CONFIG_FILE}"
    info "健康检查： http://127.0.0.1:${HEALTH_PORT}/healthz"
    if [ -n "$INSTALL_CERTIFICATE_BLOCK" ]; then
        show_certificate_files
    fi
}

upgrade_node() {
    local stage_dir
    if [ ! -x "$BINARY_PATH" ]; then
        warn '未检测到已安装节点，转入节点安装。'
        install_node
        return
    fi

    HEALTH_PORT="$(current_health_port)"
    HEALTH_PORT="${HEALTH_PORT:-$DEFAULT_HEALTH_PORT}"
    stage_dir="$(new_stage_dir)"
    if ! download_binaries "$stage_dir"; then
        rm -rf "$stage_dir"
        return 1
    fi
    mkdir -p "$INSTALL_ROOT" "$BACKUP_ROOT"
    backup_current
    write_service_file "${stage_dir}/${SERVICE_NAME}"

    install -m 755 "${stage_dir}/xboard-node" "$BINARY_PATH"
    install -m 755 "${stage_dir}/xbctl" "$CLI_PATH"
    ln -sfn "$CLI_PATH" /usr/bin/xbctl
    install -m 644 "${stage_dir}/${SERVICE_NAME}" "$SERVICE_FILE"
    systemctl daemon-reload

    if ! systemctl restart "$SERVICE_NAME" || ! wait_for_health "$HEALTH_PORT"; then
        error '升级后的健康检查未通过，正在显示最近日志。'
        show_recent_logs
        restore_backup || true
        rm -rf "$stage_dir"
        return 1
    fi
    rm -rf "$stage_dir"
    info 'Xboard-Node 升级完成。'
}

start_node() {
    systemctl start "$SERVICE_NAME"
    info '服务已启动。'
}

stop_node() {
    systemctl stop "$SERVICE_NAME"
    info '服务已停止。'
}

restart_node() {
    systemctl restart "$SERVICE_NAME"
    info '服务已重启。'
}

show_status() {
    if [ -x "$CLI_PATH" ]; then
        "$CLI_PATH" list || true
    fi
    systemctl status "$SERVICE_NAME" --no-pager || true
}

show_config() {
    if [ -f "$CONFIG_FILE" ]; then
        sed -E 's/([A-Z0-9_]*API_KEY=).*/\1*** hidden ***/' "$CREDENTIALS_FILE" 2>/dev/null || true
        echo
        sed -E 's/(CLOUDFLARE_DNS_API_TOKEN:[[:space:]]*).*/\1"*** hidden ***"/' "$CONFIG_FILE"
    else
        warn '未找到配置文件。'
    fi
}

edit_config() {
    local editor
    if [ ! -f "$CONFIG_FILE" ]; then
        error '未找到配置文件。'
        return 1
    fi
    editor="${EDITOR:-}"
    if [ -z "$editor" ]; then
        if command -v nano >/dev/null 2>&1; then
            editor='nano'
        else
            editor='vi'
        fi
    fi
    "$editor" "$CONFIG_FILE"
    read -r -p '是否立即重启服务加载修改？[直接回车确认，输入 n/否取消]：' answer
    if [[ ! "$answer" =~ ^([Nn]|否)$ ]]; then
        restart_node
    fi
}

remove_node_binding() {
    local panel_url node_id answer
    if [ ! -x "$CLI_PATH" ]; then
        error '未安装 xbctl。'
        return 1
    fi
    read -r -p '要删除节点的面板地址：' panel_url
    read -r -p '要删除的节点 ID：' node_id
    if [ -z "$panel_url" ] || ! [[ "$node_id" =~ ^[1-9][0-9]*$ ]]; then
        error '必须填写面板地址和正整数节点 ID。'
        return 1
    fi
    read -r -p "确认删除 ${panel_url} 的节点 ${node_id}？[输入 y/是确认]：" answer
    if [[ ! "$answer" =~ ^([Yy]|是)$ ]]; then
        warn '已取消删除。'
        return
    fi
    backup_current
    "$CLI_PATH" bind remove-node --panel "$panel_url" --node-id "$node_id"
    info '节点绑定已删除。'
}

install_route_rules() {
    local stage_dir
    if [ ! -f "$CONFIG_FILE" ]; then
        error '请先安装节点，再安装路由规则。'
        return 1
    fi
    require_singbox_config

    stage_dir="$(new_stage_dir)"
    backup_current
    write_route_template "${stage_dir}/custom.json"

    # Keep the DNS section when refreshing the supplied route-rule template.
    if [ -f "$CUSTOM_CONFIG_FILE" ]; then
        if ! python3 - "$CUSTOM_CONFIG_FILE" "${stage_dir}/custom.json" <<'PY'
import json
import sys

old_path, new_path = sys.argv[1:]
with open(old_path, encoding="utf-8-sig") as stream:
    old_config = json.load(stream)
with open(new_path, encoding="utf-8") as stream:
    new_config = json.load(stream)
if isinstance(old_config.get("dns"), dict):
    new_config["dns"] = old_config["dns"]
with open(new_path, "w", encoding="utf-8") as stream:
    json.dump(new_config, stream, ensure_ascii=True, indent=2)
    stream.write("\n")
PY
        then
            error '现有自定义配置不是有效的 JSON。'
            rm -rf "$stage_dir"
            return 1
        fi
    fi

    install -m 600 "${stage_dir}/custom.json" "$CUSTOM_CONFIG_FILE"
    if ! apply_custom_config; then
        rm -rf "$stage_dir"
        return 1
    fi
    rm -rf "$stage_dir"
    info "路由规则已安装：${CUSTOM_CONFIG_FILE}"
}

generate_dns_unlock_config() {
    local stage_dir default_dns unlock_dns dns_port selected_services
    if [ ! -f "$CONFIG_FILE" ]; then
        error '请先安装节点，再生成 DNS 解锁配置。'
        return 1
    fi
    require_singbox_config

    default_dns='1.1.1.1'
    dns_port='53'
    read -r -p '解锁 DNS 服务器 [8.8.8.8]：' unlock_dns
    unlock_dns="${unlock_dns:-8.8.8.8}"
    if [ -z "$unlock_dns" ]; then
        error '解锁 DNS 服务器不能为空。'
        return 1
    fi

    echo '可解锁服务：1) Netflix  2) YouTube  3) Disney+  4) TikTok'
    echo '            5) ChatGPT  6) Claude   7) Gemini'
    read -r -p '选择服务（空格分隔，例如：1 5 6）：' selected_services
    if [ -z "$selected_services" ]; then
        error '请至少选择一个解锁服务。'
        return 1
    fi

    stage_dir="$(new_stage_dir)"
    backup_current
    if [ -f "$CUSTOM_CONFIG_FILE" ]; then
        cp "$CUSTOM_CONFIG_FILE" "${stage_dir}/custom.json"
    else
        write_route_template "${stage_dir}/custom.json"
    fi

    if ! python3 - "${stage_dir}/custom.json" "$default_dns" "$unlock_dns" "$dns_port" "$selected_services" <<'PY'
import json
import sys

config_path, default_dns, unlock_dns, port, selected = sys.argv[1:]
service_domains = {
    "1": ["netflix.com", "nflxvideo.net", "nflxso.net", "nflxext.com"],
    "2": ["youtube.com", "youtu.be", "googlevideo.com", "ytimg.com"],
    "3": ["disneyplus.com", "disney-plus.net", "disney.com"],
    "4": ["tiktok.com", "tiktokv.com", "ibytedtos.com", "byteoversea.com"],
    "5": ["openai.com", "chatgpt.com", "oaistatic.com", "oaiusercontent.com"],
    "6": ["anthropic.com", "claude.ai"],
    "7": ["gemini.google.com", "ai.google.dev", "generativelanguage.googleapis.com", "deepmind.google"],
}
selected_codes = selected.split()
unknown = [code for code in selected_codes if code not in service_domains]
if unknown:
    raise SystemExit("无效的服务编号：" + " ".join(unknown))
domains = []
for code in selected_codes:
    for domain in service_domains[code]:
        if domain not in domains:
            domains.append(domain)
with open(config_path, encoding="utf-8-sig") as stream:
    config = json.load(stream)
config["dns"] = {
    "servers": [
        {"type": "udp", "tag": "default_dns", "server": default_dns, "server_port": int(port)},
        {"type": "udp", "tag": "unlock_dns", "server": unlock_dns, "server_port": int(port)},
    ],
    "rules": [{"domain_suffix": domains, "server": "unlock_dns"}],
    "final": "default_dns",
    "strategy": "prefer_ipv4",
}
with open(config_path, "w", encoding="utf-8") as stream:
    json.dump(config, stream, ensure_ascii=True, indent=2)
    stream.write("\n")
PY
    then
        error 'DNS 解锁配置生成失败。'
        rm -rf "$stage_dir"
        return 1
    fi

    install -m 600 "${stage_dir}/custom.json" "$CUSTOM_CONFIG_FILE"
    if ! apply_custom_config; then
        rm -rf "$stage_dir"
        return 1
    fi
    rm -rf "$stage_dir"
    info "DNS 解锁配置已写入：${CUSTOM_CONFIG_FILE}"
}

yaml_quote() {
    local value="$1"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    value="${value//$'\r'/}"
    value="${value//$'\n'/}"
    printf '"%s"' "$value"
}

valid_certificate_domain() {
    local domain="$1"
    [[ "$domain" =~ ^(\*\.)?([A-Za-z0-9-]+\.)+[A-Za-z]{2,63}$ ]]
}

valid_email() {
    [[ "$1" =~ ^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$ ]]
}

write_top_level_cert_config() {
    local certificate_block="$1"
    local config_path="${2:-$CONFIG_FILE}"
    local temp_path

    temp_path="$(mktemp)"
    awk '
        /^cert:[[:space:]]*(#.*)?$/ { in_cert = 1; next }
        in_cert && /^[^[:space:]#][^:]*:[[:space:]]*(#.*)?$/ { in_cert = 0 }
        !in_cert { print }
    ' "$config_path" >"$temp_path"
    if grep -qE '^instances:[[:space:]]*(#.*)?$' "$config_path"; then
        printf '\n%s\n' "$certificate_block" >>"$temp_path"
    else
        printf '\n%s\n  cert_dir: %s\n' "$certificate_block" "$(yaml_quote "$CERT_STORAGE_DIR")" >>"$temp_path"
    fi
    install -m 600 "$temp_path" "$config_path"
    rm -f "$temp_path"
    set_instance_cert_dir "$config_path"
}

set_instance_cert_dir() {
    local config_path="${1:-$CONFIG_FILE}"
    local temp_path

    temp_path="$(mktemp)"
    awk -v cert_dir="$CERT_STORAGE_DIR" '
        function indent_of(line, prefix) {
            prefix = line
            sub(/[^ ].*$/, "", prefix)
            return length(prefix)
        }
        function write_missing_cert_dir() {
            if (in_instance && !has_cert_dir) {
                printf "%*s%s\n", instance_indent + 2, "", "cert:"
                printf "%*s%s\n", instance_indent + 4, "", "cert_dir: \"" cert_dir "\""
            }
        }
        /^instances:[[:space:]]*(#.*)?$/ {
            in_instances = 1
            instances_indent = indent_of($0)
            print
            next
        }
        in_instances && $0 !~ /^[[:space:]]*($|#)/ && indent_of($0) <= instances_indent {
            write_missing_cert_dir()
            in_instances = 0
            in_instance = 0
            in_cert = 0
            print
            next
        }
        in_instances && $0 ~ /^[[:space:]]*-[[:space:]]/ && indent_of($0) > instances_indent && (!in_instance || indent_of($0) == instance_indent) {
            write_missing_cert_dir()
            in_instance = 1
            instance_indent = indent_of($0)
            has_cert_dir = 0
            in_cert = 0
            print
            next
        }
        in_instance && indent_of($0) == instance_indent + 2 && $0 ~ /^[[:space:]]*cert:[[:space:]]*(#.*)?$/ {
            print
            printf "%*s%s\n", instance_indent + 4, "", "cert_dir: \"" cert_dir "\""
            has_cert_dir = 1
            in_cert = 1
            next
        }
        in_instance && in_cert && indent_of($0) == instance_indent + 4 && $0 ~ /^[[:space:]]*cert_dir:[[:space:]]*/ { next }
        in_instance && in_cert && indent_of($0) == instance_indent + 2 && $0 ~ /^[[:space:]]*[^[:space:]#][^:]*:[[:space:]]*/ { in_cert = 0 }
        { print }
        END { if (in_instances) write_missing_cert_dir() }
    ' "$config_path" >"$temp_path"
    install -m 600 "$temp_path" "$config_path"
    rm -f "$temp_path"
}

apply_certificate_config() {
    local certificate_block="$1"
    local health_port

    backup_current
    write_top_level_cert_config "$certificate_block"
    health_port="$(current_health_port)"
    health_port="${health_port:-$DEFAULT_HEALTH_PORT}"
    if ! systemctl restart "$SERVICE_NAME" || ! wait_for_health "$health_port"; then
        error '证书配置未能启动，正在恢复修改前的配置。'
        show_recent_logs
        restore_backup || true
        return 1
    fi
    show_certificate_files
}

configure_certificate() {
    local domain email cloudflare_token cert_file key_file certificate_block choice
    if [ ! -f "$CONFIG_FILE" ]; then
        error '请先安装节点，再生成或配置证书。'
        return 1
    fi

    echo
    echo '证书方式：'
    echo '1. 生成自签名证书（测试使用，客户端需允许不安全证书）'
    echo "2. 申请 Let's Encrypt 证书（HTTP 验证，需要域名解析到本机并放行 80 端口）"
    echo "3. 申请 Let's Encrypt 证书（Cloudflare DNS 验证，可申请通配符证书）"
    echo '4. 使用已有证书文件'
    echo '0. 取消'
    read -r -p '请选择 [0-4]：' choice

    case "$choice" in
        1)
            read -r -p '证书域名 [localhost]：' domain
            domain="${domain:-localhost}"
            if [ "$domain" != 'localhost' ] && ! valid_certificate_domain "$domain"; then
                error '域名格式不正确。'
                return 1
            fi
            certificate_block="cert:
  cert_mode: \"self\"
  domain: $(yaml_quote "$domain")"
            ;;
        2)
            read -r -p '证书域名：' domain
            read -r -p '通知邮箱：' email
            if ! valid_certificate_domain "$domain" || [[ "$domain" == \*.* ]]; then
                error '请输入有效的普通域名，HTTP 验证不支持通配符域名。'
                return 1
            fi
            if ! valid_email "$email"; then
                error '邮箱格式不正确。'
                return 1
            fi
            certificate_block="cert:
  cert_mode: \"http\"
  domain: $(yaml_quote "$domain")
  email: $(yaml_quote "$email")
  http_port: 80"
            ;;
        3)
            read -r -p '证书域名（可输入 *.example.com）：' domain
            read -r -p '通知邮箱：' email
            read -r -s -p 'Cloudflare API Token：' cloudflare_token
            echo
            if ! valid_certificate_domain "$domain"; then
                error '域名格式不正确。'
                return 1
            fi
            if ! valid_email "$email"; then
                error '邮箱格式不正确。'
                return 1
            fi
            if [ -z "$cloudflare_token" ]; then
                error 'Cloudflare API Token 不能为空。'
                return 1
            fi
            certificate_block="cert:
  cert_mode: \"dns\"
  domain: $(yaml_quote "$domain")
  email: $(yaml_quote "$email")
  dns_provider: \"cloudflare\"
  dns_env:
    CLOUDFLARE_DNS_API_TOKEN: $(yaml_quote "$cloudflare_token")"
            ;;
        4)
            read -r -p '证书文件路径（例如 /etc/letsencrypt/live/example.com/fullchain.pem）：' cert_file
            read -r -p '私钥文件路径（例如 /etc/letsencrypt/live/example.com/privkey.pem）：' key_file
            if [ ! -r "$cert_file" ] || [ ! -r "$key_file" ]; then
                error '证书文件或私钥文件不存在，或当前用户无读取权限。'
                return 1
            fi
            certificate_block="cert:
  cert_mode: \"file\"
  cert_file: $(yaml_quote "$cert_file")
  key_file: $(yaml_quote "$key_file")"
            ;;
        0)
            info '已取消证书配置。'
            return
            ;;
        *)
            error '无效选择。'
            return 1
            ;;
    esac

    if ! apply_certificate_config "$certificate_block"; then
        return 1
    fi
    case "$choice" in
        1)
            info '自签名证书配置完成，有效期为 10 年，不支持自动续期。'
            ;;
        2|3)
            info "Let's Encrypt 证书配置完成，Xboard-Node 会自动续期。"
            ;;
        4)
            info '已有证书文件配置完成。'
            ;;
    esac
}

uninstall_node() {
    local answer purge_answer
    read -r -p '确认卸载服务和程序文件？[输入 y/是确认]：' answer
    if [[ ! "$answer" =~ ^([Yy]|是)$ ]]; then
        warn '已取消卸载。'
        return
    fi

    systemctl stop "$SERVICE_NAME" >/dev/null 2>&1 || true
    systemctl disable "$SERVICE_NAME" >/dev/null 2>&1 || true
    rm -f "$SERVICE_FILE" "$BINARY_PATH" "$CLI_PATH"
    [ -L /usr/bin/xbctl ] && rm -f /usr/bin/xbctl
    systemctl daemon-reload

    read -r -p "同时删除 ${INSTALL_ROOT}（包含配置和备份）？[输入 y/是确认]：" purge_answer
    if [[ "$purge_answer" =~ ^([Yy]|是)$ ]]; then
        rm -rf "$INSTALL_ROOT"
        info '服务、程序、配置和备份均已删除。'
    else
        info "服务和程序已删除，配置保留在 ${INSTALL_ROOT}。"
    fi
}

show_menu() {
    echo
    echo -e "${CYAN}Xboard-Node Sing-box 节点管理${NC}"
    echo '1. 安装或重新配置节点'
    echo '2. 升级 Xboard-Node'
    echo '3. 启动服务'
    echo '4. 停止服务'
    echo '5. 重启服务'
    echo '6. 查看实时日志'
    echo '7. 查看服务状态和节点绑定'
    echo '8. 查看配置文件'
    echo '9. 编辑配置文件'
    echo '10. 删除节点绑定'
    echo '11. 安装指定路由规则'
    echo '12. 生成 DNS 解锁配置'
    echo '13. 生成或配置证书'
    echo '14. 卸载'
    echo '0. 退出'
}

main() {
    cleanup_crlf
    require_root
    require_systemd
    install_shortcut
    detect_arch
    install_dependencies

    while true; do
        show_menu
        read -r -p '请选择 [0-14]：' choice
        case "$choice" in
            1) install_node || error '安装或配置失败。' ;;
            2) upgrade_node || error '升级失败。' ;;
            3) start_node || error '服务启动失败。' ;;
            4) stop_node || error '服务停止失败。' ;;
            5) restart_node || error '服务重启失败。' ;;
            6) journalctl -u "$SERVICE_NAME" -f ;;
            7) show_status ;;
            8) show_config ;;
            9) edit_config || error '配置编辑失败。' ;;
            10) remove_node_binding || error '节点绑定删除失败。' ;;
            11) install_route_rules || error '路由规则安装失败。' ;;
            12) generate_dns_unlock_config || error 'DNS 解锁配置失败。' ;;
            13) configure_certificate || error '证书配置失败。' ;;
            14) uninstall_node || error '卸载失败。' ;;
            0) exit 0 ;;
            *) error '无效选择。' ;;
        esac
    done
}

main "$@"
