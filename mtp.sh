cat > /usr/local/bin/mtp <<'EOF'
#!/bin/bash

# ============================================
# MTP 代理管理面板
# Version: v1.3.0 (IPv6 支持版)
# ============================================

GREEN="\033[32m"
RED="\033[31m"
YELLOW="\033[33m"
CYAN="\033[36m"
BLUE="\033[34m"
RESET="\033[0m"

SCRIPT_VERSION="v1.3.0"
MTG_VERSION="2.1.7"

CONFIG_FILE="/etc/mtg.toml"
INFO_FILE="/etc/mtg_info.txt"
SERVICE_FILE="/etc/systemd/system/mtg.service"
LOG_FILE="/var/log/mtg.log"
GUARD_FILE="/usr/local/bin/mtg_guard.sh"
GUARD_LOG="/var/log/mtg_guard.log"

SCRIPT_URL="https://raw.githubusercontent.com/lijboys/SSHTools/main/mtp.sh"

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}请使用 root 用户运行！${RESET}"
    exit 1
fi

pause() {
    read -p "按回车键返回主菜单..."
}

check_dependencies() {
    local missing=()
    for cmd in curl tar grep awk sed pgrep ss; do
        command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
    done
    [ ${#missing[@]} -gt 0 ] && { echo -e "${RED}❌ 缺少依赖: ${missing[*]}${RESET}"; return 1; }
    return 0
}

detect_arch() {
    case "$(uname -m)" in
        x86_64|amd64) echo "amd64" ;;
        aarch64|arm64) echo "arm64" ;;
        armv7l|armv7) echo "armv7" ;;
        *) echo "unsupported" ;;
    esac
}

is_valid_port() { [[ "$1" =~ ^[0-9]+$ ]] && [ "$1" -ge 1 ] && [ "$1" -le 65535 ]; }

is_valid_ipv4() {
    local ip=$1
    [[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
    IFS='.' read -r o1 o2 o3 o4 <<< "$ip"
    for o in "$o1" "$o2" "$o3" "$o4"; do
        [[ "$o" =~ ^[0-9]+$ ]] && [ "$o" -ge 0 ] && [ "$o" -le 255 ] || return 1
    done
    return 0
}

is_valid_ipv6() {
    local ip=$1
    [[ "$ip" =~ : ]] || return 1
    [[ "$ip" =~ ^[0-9a-fA-F:]+$ ]] || return 1
    return 0
}

is_valid_domain() { [[ "$1" =~ ^[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; }
is_port_in_use() { ss -tln 2>/dev/null | awk '{print $4}' | grep -qE "[:.]$1$"; }

read_info_value() {
    local key=$1
    grep "^${key}=" "$INFO_FILE" 2>/dev/null | head -n1 | cut -d'"' -f2
}

get_status() {
    if command -v systemctl >/dev/null 2>&1; then
        systemctl is-active --quiet mtg && echo -e "${GREEN}运行中 (systemd)${RESET}" || echo -e "${RED}已停止${RESET}"
    else
        pgrep -f "/usr/local/bin/mtg_guard.sh" >/dev/null 2>&1 && echo -e "${GREEN}运行中 (guard)${RESET}" || echo -e "${RED}已停止${RESET}"
    fi
}

get_public_ip() {
    local ip_type="${1:-4}"
    local temp_ip=""
    if [ "$ip_type" = "6" ]; then
        temp_ip=$(curl -s6m3 --connect-timeout 3 ipv6.icanhazip.com 2>/dev/null)
        [ -z "$temp_ip" ] && temp_ip=$(curl -s6m3 --connect-timeout 3 api6.ipify.org 2>/dev/null)
        [ -z "$temp_ip" ] && temp_ip=$(curl -s6m3 --connect-timeout 3 ifconfig.co 2>/dev/null)
        is_valid_ipv6 "$temp_ip" && echo "$temp_ip" || echo ""
    else
        temp_ip=$(curl -s4m3 --connect-timeout 3 ipv4.icanhazip.com 2>/dev/null)
        [ -z "$temp_ip" ] && temp_ip=$(curl -s4m3 --connect-timeout 3 api.ipify.org 2>/dev/null)
        [ -z "$temp_ip" ] && temp_ip=$(curl -s4m3 --connect-timeout 3 ifconfig.me 2>/dev/null)
        is_valid_ipv4 "$temp_ip" && echo "$temp_ip" || echo ""
    fi
}

format_tg_server() {
    local ip="$1"
    local ip_type="$2"
    if [ "$ip_type" = "6" ]; then
        echo "[${ip}]"
    else
        echo "$ip"
    fi
}

write_info_file() {
    local in_port="$1"
    local public_ip="$2"
    local out_port="$3"
    local fake_domain="$4"
    local secret="$5"
    local tg_link="$6"
    local ip_type="$7"
    local bind_addr="$8"

    cat > "$INFO_FILE" <<EOT
IN_PORT="${in_port}"
PUBLIC_IP="${public_ip}"
OUT_PORT="${out_port}"
FAKE_DOMAIN="${fake_domain}"
SECRET="${secret}"
TG_LINK="${tg_link}"
IP_TYPE="${ip_type}"
BIND_ADDR="${bind_addr}"
EOT
}

write_config_file() {
    local in_port="$1"
    local secret="$2"
    local bind_addr="$3"

    cat > "$CONFIG_FILE" <<EOT
secret = "${secret}"
bind-to = "${bind_addr}"
EOT
}

create_guard_script() {
    cat > "$GUARD_FILE" <<'EOG'
#!/bin/sh
while true; do
    /usr/local/bin/mtg run /etc/mtg.toml >> /var/log/mtg.log 2>&1
    echo "$(date '+%F %T') mtg exited, restarting in 2s..." >> /var/log/mtg_guard.log
    sleep 2
done
EOG
    chmod +x "$GUARD_FILE"
}

extract_bind_port() {
    grep '^bind-to = ' "$CONFIG_FILE" 2>/dev/null | sed -E 's/.*:([0-9]+)".*/\1/' | head -n1
}

stop_mtg_service() {
    if command -v systemctl >/dev/null 2>&1; then
        systemctl stop mtg >/dev/null 2>&1
    else
        pkill -9 -f "/usr/local/bin/mtg_guard.sh" 2>/dev/null || true
        pkill -9 -f "mtg run" 2>/dev/null || true
        sleep 2
        if [ -f "$CONFIG_FILE" ]; then
            local port
            port=$(extract_bind_port)
            for i in {1..8}; do
                if ! is_port_in_use "$port"; then
                    break
                fi
                sleep 1
            done
        fi
    fi
}

start_mtg_service() {
    if command -v systemctl >/dev/null 2>&1; then
        mkdir -p /etc/systemd/system/
        cat > "$SERVICE_FILE" <<EOT
[Unit]
Description=MTG v2 Proxy
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/mtg run ${CONFIG_FILE}
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOT
        systemctl daemon-reload
        systemctl enable mtg >/dev/null 2>&1
        systemctl restart mtg
        sleep 1
        systemctl is-active --quiet mtg && return 0 || return 1
    else
        pkill -9 -f "/usr/local/bin/mtg_guard.sh" 2>/dev/null || true
        pkill -9 -f "mtg run" 2>/dev/null || true
        [ ! -f "$GUARD_FILE" ] && create_guard_script
        nohup setsid "$GUARD_FILE" >/dev/null 2>&1 </dev/null &
        sleep 2
        if pgrep -f "/usr/local/bin/mtg_guard.sh" >/dev/null 2>&1; then
            (
                crontab -l 2>/dev/null | grep -v -E "mtg_guard.sh|mtg run ${CONFIG_FILE}"
                echo "@reboot nohup setsid /usr/local/bin/mtg_guard.sh >/dev/null 2>&1 </dev/null &"
                echo "*/1 * * * * pgrep -f '/usr/local/bin/mtg_guard.sh' >/dev/null || nohup setsid /usr/local/bin/mtg_guard.sh >/dev/null 2>&1 </dev/null &"
            ) | crontab -
            return 0
        fi
        return 1
    fi
}

download_mtg() {
    local arch download_url tmp_dir mtg_bin
    arch=$(detect_arch)
    [ "$arch" = "unsupported" ] && { echo -e "${RED}❌ 不支持架构: $(uname -m)${RESET}"; return 1; }
    download_url="https://github.com/9seconds/mtg/releases/download/v${MTG_VERSION}/mtg-${MTG_VERSION}-linux-${arch}.tar.gz"
    tmp_dir=$(mktemp -d)
    echo -e "${YELLOW}正在下载 mtg v${MTG_VERSION} (${arch}) ...${RESET}"
    curl -fL --connect-timeout 10 -o "${tmp_dir}/mtg.tar.gz" "$download_url" || { rm -rf "$tmp_dir"; return 1; }
    tar -zxf "${tmp_dir}/mtg.tar.gz" -C "$tmp_dir" || { rm -rf "$tmp_dir"; return 1; }
    mtg_bin=$(find "$tmp_dir" -type f -name mtg | head -n 1)
    [ -z "$mtg_bin" ] && { rm -rf "$tmp_dir"; return 1; }
    install -m 755 "$mtg_bin" /usr/local/bin/mtg
    rm -rf "$tmp_dir"
    /usr/local/bin/mtg --help >/dev/null 2>&1 || return 1
    return 0
}

choose_and_generate_secret() {
    echo ""
    echo -e "${CYAN}================ FakeTLS 伪装域名选择 ================${RESET}"
    echo -e "${YELLOW}提示：若你有自己的真实域名，强烈建议优先使用自定义域名。${RESET}"
    echo -e "${CYAN}------------------------------------------------------${RESET}"
    printf "  ${GREEN}%-4s${RESET} %-22s ${YELLOW}%-18s${RESET}  ${GREEN}%-4s${RESET} %-22s ${YELLOW}%s${RESET}\n" "1." "www.cloudflare.com" "(通用稳妥/推荐)" "2." "www.microsoft.com" "(国际通用/推荐)"
    printf "  ${GREEN}%-4s${RESET} %-22s ${YELLOW}%-18s${RESET}  ${GREEN}%-4s${RESET} %-22s ${YELLOW}%s${RESET}\n" "3." "www.apple.com" "(苹果生态/推荐)" "4." "www.bing.com" "(中文常见/推荐)"
    printf "  ${GREEN}%-4s${RESET} %-22s ${YELLOW}%-18s${RESET}  ${GREEN}%-4s${RESET} %-22s ${YELLOW}%s${RESET}\n" "5." "gateway.icloud.com" "(服务风格)" "6." "cdn.jsdelivr.net" "(CDN风格)"
    printf "  ${GREEN}%-4s${RESET} %-22s ${YELLOW}%-18s${RESET}  ${GREEN}%-4s${RESET} %-22s ${YELLOW}%s${RESET}\n" "7." "www.wechat.com" "(国内常见)" "8." "www.dropbox.com" "(网盘风格)"
    printf "  ${GREEN}%-4s${RESET} %-22s ${YELLOW}%-18s${RESET}  ${YELLOW}%-4s${RESET} %-22s ${RED}%s${RESET}\n" "9." "onedrive.live.com" "(微软网盘)" "10." "自定义伪装域名" "(强烈推荐)"
    echo -e "${CYAN}------------------------------------------------------${RESET}"
    read -p "请输入序号选择 (回车默认选 1): " domain_choice

    case "$domain_choice" in
        2) FAKE_DOMAIN="www.microsoft.com" ;;
        3) FAKE_DOMAIN="www.apple.com" ;;
        4) FAKE_DOMAIN="www.bing.com" ;;
        5) FAKE_DOMAIN="gateway.icloud.com" ;;
        6) FAKE_DOMAIN="cdn.jsdelivr.net" ;;
        7) FAKE_DOMAIN="www.wechat.com" ;;
        8) FAKE_DOMAIN="www.dropbox.com" ;;
        9) FAKE_DOMAIN="onedrive.live.com" ;;
        10)
            read -p "👉 请输入自定义【FakeTLS 伪装域名】: " FAKE_DOMAIN
            FAKE_DOMAIN=${FAKE_DOMAIN:-www.cloudflare.com}
            is_valid_domain "$FAKE_DOMAIN" || { echo -e "${RED}❌ 域名格式不正确！${RESET}"; return 1; }
            ;;
        *) FAKE_DOMAIN="www.cloudflare.com" ;;
    esac

    [ ! -x "/usr/local/bin/mtg" ] && { echo -e "${RED}❌ mtg 核心不存在！${RESET}"; return 1; }
    echo -e "${YELLOW}正在动态生成专属伪装密钥...${RESET}"
    SECRET=$(/usr/local/bin/mtg generate-secret "${FAKE_DOMAIN}" 2>/dev/null)
    [ -z "$SECRET" ] && { echo -e "${RED}❌ 密钥生成失败！${RESET}"; return 1; }
    echo -e "✅ 已设置伪装域名: ${GREEN}${FAKE_DOMAIN}${RESET}"
    return 0
}

choose_ip_mode() {
    echo ""
    echo -e "${CYAN}--- 请选择对外使用的 IP 类型 ---${RESET}"
    echo -e "  ${GREEN}1.${RESET} IPv4 ${YELLOW}(默认)${RESET}"
    echo -e "  ${GREEN}2.${RESET} IPv6"
    read -p "请输入序号 (回车默认 1): " ip_choice

    if [ -z "$ip_choice" ] || [ "$ip_choice" = "1" ]; then
        IP_TYPE="4"
        AUTO_IP=$(get_public_ip 4)
        DISPLAY_IP=${AUTO_IP:-"获取失败，请手动输入"}
        BIND_ADDR="0.0.0.0:${IN_PORT}"
        read -p "👉 请输入公网 IPv4 地址 (识别出: $DISPLAY_IP): " PUBLIC_IP
        PUBLIC_IP=${PUBLIC_IP:-$AUTO_IP}
        is_valid_ipv4 "$PUBLIC_IP" || { echo -e "${RED}❌ 公网 IPv4 地址无效！${RESET}"; return 1; }
    elif [ "$ip_choice" = "2" ]; then
        IP_TYPE="6"
        AUTO_IP=$(get_public_ip 6)
        DISPLAY_IP=${AUTO_IP:-"获取失败，请手动输入"}
        BIND_ADDR="[::]:${IN_PORT}"
        read -p "👉 请输入公网 IPv6 地址 (识别出: $DISPLAY_IP): " PUBLIC_IP
        PUBLIC_IP=${PUBLIC_IP:-$AUTO_IP}
        is_valid_ipv6 "$PUBLIC_IP" || { echo -e "${RED}❌ 公网 IPv6 地址无效！${RESET}"; return 1; }
    else
        echo -e "${RED}❌ 输入错误！${RESET}"
        return 1
    fi
    return 0
}

install_mtp() {
    clear
    echo -e "${CYAN}=========================================${RESET}"
    echo -e "${CYAN}  🚀 开始部署 mtg v2 伪装代理${RESET}"
    echo -e "${CYAN}=========================================${RESET}"

    check_dependencies || { pause; return; }

    if [ -f "/usr/local/bin/mtg" ] && [ -f "$INFO_FILE" ]; then
        echo -e "${YELLOW}⚠️ 检测到当前机器已经安装了 MTP 代理服务！${RESET}"
        read -p "👉 是否要继续【覆盖重装】并清除原有配置？[y/N]: " confirm_reinstall
        [[ "$confirm_reinstall" != "y" && "$confirm_reinstall" != "Y" ]] && { echo -e "${GREEN}✅ 已取消安装。${RESET}"; sleep 1; return; }
    fi

    stop_mtg_service
    download_mtg || { pause; return; }

    echo ""
    echo -e "${CYAN}--- 请选择你的机器网络环境 ---${RESET}"
    echo -e "  ${GREEN}1.${RESET} NAT 小鸡 (仅开放部分映射端口) [默认]"
    echo -e "  ${YELLOW}2.${RESET} 独立 VPS (拥有独立公网 IP，全端口开放)"
    read -p "请输入序号 (回车默认选 1): " net_choice
    echo ""

    if [ -z "$net_choice" ] || [ "$net_choice" = "1" ]; then
        echo -e "${YELLOW}💡 提示: NAT 机器请确认商家后台映射端口。${RESET}"
        read -p "👉 1. 请输入【公网/外网可用端口】(回车默认 10086): " OUT_PORT
        OUT_PORT=${OUT_PORT:-10086}
        is_valid_port "$OUT_PORT" || { echo -e "${RED}❌ 公网端口无效！${RESET}"; pause; return; }

        read -p "👉 2. 请输入【内网监听端口】(回车默认与外网一致: $OUT_PORT): " IN_PORT
        IN_PORT=${IN_PORT:-$OUT_PORT}
        is_valid_port "$IN_PORT" || { echo -e "${RED}❌ 内网监听端口无效！${RESET}"; pause; return; }
        is_port_in_use "$IN_PORT" && { echo -e "${RED}❌ 监听端口 ${IN_PORT} 已被占用！${RESET}"; pause; return; }

        choose_ip_mode || { pause; return; }

        echo -e "   ${GREEN}✅ NAT 节点配置完成 -> IP: ${PUBLIC_IP} | 内网端口: ${IN_PORT} | 外网端口: ${OUT_PORT}${RESET}"
    elif [ "$net_choice" = "2" ]; then
        echo -e "${YELLOW}💡 提示: 独立 VPS 推荐使用 443 端口。${RESET}"
        read -p "👉 请输入你想使用的端口 (回车默认 443): " IN_PORT
        IN_PORT=${IN_PORT:-443}
        is_valid_port "$IN_PORT" || { echo -e "${RED}❌ 端口无效！${RESET}"; pause; return; }
        is_port_in_use "$IN_PORT" && { echo -e "${RED}❌ 端口 ${IN_PORT} 已被占用！${RESET}"; pause; return; }

        OUT_PORT=$IN_PORT
        choose_ip_mode || { pause; return; }

        echo -e "   ${GREEN}✅ VPS 节点配置完成 -> IP: ${PUBLIC_IP} | 端口: ${IN_PORT}${RESET}"
    else
        echo -e "${RED}❌ 输入错误！${RESET}"
        pause
        return
    fi

    choose_and_generate_secret || { pause; return; }

    write_config_file "$IN_PORT" "$SECRET" "$BIND_ADDR"

    if start_mtg_service; then
        TG_SERVER=$(format_tg_server "$PUBLIC_IP" "$IP_TYPE")
        TG_LINK="tg://proxy?server=${TG_SERVER}&port=${OUT_PORT}&secret=${SECRET}"
        write_info_file "$IN_PORT" "$PUBLIC_IP" "$OUT_PORT" "$FAKE_DOMAIN" "$SECRET" "$TG_LINK" "$IP_TYPE" "$BIND_ADDR"
        echo -e "\n${GREEN}✅ 部署成功！程序已在后台监听端口 ${IN_PORT}${RESET}"
        echo -e "当前服务状态: $(get_status)"
        echo -e "你的专属 TG 链接是：\n${YELLOW}${TG_LINK}${RESET}\n"
    else
        echo -e "${RED}❌ 服务启动失败！${RESET}"
        echo -e "${YELLOW}可执行以下命令查看原因：${RESET}"
        echo "journalctl -u mtg -n 50 --no-pager"
        echo "cat /etc/mtg.toml"
    fi
    pause
}

view_link() {
    clear
    echo -e "${CYAN}=========================================${RESET}"
    if [ -f "$INFO_FILE" ]; then
        IN_PORT=$(read_info_value IN_PORT)
        PUBLIC_IP=$(read_info_value PUBLIC_IP)
        OUT_PORT=$(read_info_value OUT_PORT)
        FAKE_DOMAIN=$(read_info_value FAKE_DOMAIN)
        TG_LINK=$(read_info_value TG_LINK)
        IP_TYPE=$(read_info_value IP_TYPE)
        [ -z "$IP_TYPE" ] && IP_TYPE="4"

        echo -e "当前服务状态:     $(get_status)"
        echo -e "当前内网监听端口: ${GREEN}${IN_PORT}${RESET}"
        echo -e "当前对外公网地址: ${GREEN}${PUBLIC_IP}:${OUT_PORT}${RESET}"
        echo -e "当前 IP 类型:     ${GREEN}IPv${IP_TYPE}${RESET}"
        echo -e "当前伪装域名:     ${GREEN}${FAKE_DOMAIN}${RESET}\n"
        echo -e "${YELLOW}👉 TG 一键直连链接：${RESET}"
        echo -e "${GREEN}${TG_LINK}${RESET}"
    else
        echo -e "${RED}未找到配置，请先安装！${RESET}"
    fi
    echo -e "${CYAN}=========================================${RESET}"
    pause
}

modify_config() {
    clear
    [ ! -f "$INFO_FILE" ] && { echo -e "${RED}请先安装！${RESET}"; pause; return; }

    IN_PORT=$(read_info_value IN_PORT)
    PUBLIC_IP=$(read_info_value PUBLIC_IP)
    OUT_PORT=$(read_info_value OUT_PORT)
    FAKE_DOMAIN=$(read_info_value FAKE_DOMAIN)
    SECRET=$(read_info_value SECRET)
    IP_TYPE=$(read_info_value IP_TYPE)
    [ -z "$IP_TYPE" ] && IP_TYPE="4"

    echo -e "${CYAN}--- 修改映射与配置信息 ---${RESET}"

    read -p "输入新【内网监听端口】 (回车保持 ${IN_PORT}): " NEW_IN
    NEW_IN=${NEW_IN:-$IN_PORT}
    is_valid_port "$NEW_IN" || { echo -e "${RED}❌ 内网监听端口无效！${RESET}"; pause; return; }
    [ "$NEW_IN" != "$IN_PORT" ] && is_port_in_use "$NEW_IN" && { echo -e "${RED}❌ 端口已被占用！${RESET}"; pause; return; }

    read -p "输入新【公网端口】 (回车保持 ${OUT_PORT}): " NEW_OUT
    NEW_OUT=${NEW_OUT:-$OUT_PORT}
    is_valid_port "$NEW_OUT" || { echo -e "${RED}❌ 公网端口无效！${RESET}"; pause; return; }

    echo -e "${CYAN}当前 IP 类型: IPv${IP_TYPE}${RESET}"
    echo -e "  ${GREEN}1.${RESET} IPv4"
    echo -e "  ${GREEN}2.${RESET} IPv6"
    read -p "请选择新的 IP 类型 (回车保持当前): " new_ip_choice

    case "$new_ip_choice" in
        1) NEW_IP_TYPE="4" ;;
        2) NEW_IP_TYPE="6" ;;
        *) NEW_IP_TYPE="$IP_TYPE" ;;
    esac

    if [ "$NEW_IP_TYPE" = "6" ]; then
        AUTO_IP=$(get_public_ip 6)
        DISPLAY_IP=${AUTO_IP:-"获取失败"}
        echo -e "${YELLOW}当前机器识别到的 IPv6 为: ${DISPLAY_IP}${RESET}"
        read -p "输入新【公网 IPv6】 (回车保持 ${PUBLIC_IP}): " NEW_IP
        NEW_IP=${NEW_IP:-$PUBLIC_IP}
        is_valid_ipv6 "$NEW_IP" || { echo -e "${RED}❌ 公网 IPv6 格式无效！${RESET}"; pause; return; }
        NEW_BIND_ADDR="[::]:${NEW_IN}"
    else
        AUTO_IP=$(get_public_ip 4)
        DISPLAY_IP=${AUTO_IP:-"获取失败"}
        echo -e "${YELLOW}当前机器识别到的 IPv4 为: ${DISPLAY_IP}${RESET}"
        read -p "输入新【公网 IPv4】 (回车保持 ${PUBLIC_IP}): " NEW_IP
        NEW_IP=${NEW_IP:-$PUBLIC_IP}
        is_valid_ipv4 "$NEW_IP" || { echo -e "${RED}❌ 公网 IPv4 格式无效！${RESET}"; pause; return; }
        NEW_BIND_ADDR="0.0.0.0:${NEW_IN}"
    fi

    echo -e "当前伪装域名为: ${GREEN}${FAKE_DOMAIN}${RESET}"
    read -p "按 1 重新设置伪装域名，按回车保持不变: " change_domain
    [ "$change_domain" = "1" ] && choose_and_generate_secret

    write_config_file "$NEW_IN" "$SECRET" "$NEW_BIND_ADDR"

    if start_mtg_service; then
        TG_SERVER=$(format_tg_server "$NEW_IP" "$NEW_IP_TYPE")
        TG_LINK="tg://proxy?server=${TG_SERVER}&port=${NEW_OUT}&secret=${SECRET}"
        write_info_file "$NEW_IN" "$NEW_IP" "$NEW_OUT" "$FAKE_DOMAIN" "$SECRET" "$TG_LINK" "$NEW_IP_TYPE" "$NEW_BIND_ADDR"
        echo -e "${GREEN}✅ 配置已更新并重启成功！${RESET}"
    else
        echo -e "${RED}❌ 配置已写入，但服务启动失败！${RESET}"
    fi
    pause
}

start_service_manual() {
    clear
    [ ! -x "/usr/local/bin/mtg" ] || [ ! -f "$CONFIG_FILE" ] && { echo -e "${RED}❌ 未检测到已安装的 mtg！${RESET}"; pause; return; }
    start_mtg_service && echo -e "${GREEN}✅ 服务启动成功！${RESET}" || echo -e "${RED}❌ 服务启动失败！${RESET}"
    pause
}

stop_service_manual() {
    clear
    stop_mtg_service
    echo -e "${YELLOW}已尝试停止 MTP 服务。${RESET}"
    pause
}

restart_service_manual() {
    clear
    [ ! -x "/usr/local/bin/mtg" ] || [ ! -f "$CONFIG_FILE" ] && { echo -e "${RED}❌ 未检测到已安装的 mtg！${RESET}"; pause; return; }
    start_mtg_service && echo -e "${GREEN}✅ 服务重启成功！${RESET}" || echo -e "${RED}❌ 服务重启失败！${RESET}"
    pause
}

view_logs() {
    clear
    echo -e "${CYAN}=========================================${RESET}"
    echo -e "               📜 MTP 运行日志"
    echo -e "${CYAN}=========================================${RESET}"
    if command -v systemctl >/dev/null 2>&1; then
        journalctl -u mtg --no-pager -n 50 2>/dev/null || echo "暂无日志"
    else
        tail -n 50 "$LOG_FILE" 2>/dev/null || echo "暂无日志"
        [ -f "$GUARD_LOG" ] && echo -e "\n${YELLOW}守护日志：${RESET}" && tail -n 15 "$GUARD_LOG"
    fi
    echo -e "${CYAN}=========================================${RESET}"
    pause
}

uninstall_mtp() {
    clear
    echo -e "${RED}你正在执行 MTP 卸载操作！${RESET}"
    read -p "确认彻底卸载 mtg + 面板吗？[y/N]: " confirm_uninstall
    [[ "$confirm_uninstall" != "y" && "$confirm_uninstall" != "Y" ]] && { echo -e "${YELLOW}已取消卸载。${RESET}"; sleep 1; return; }

    echo -e "${RED}正在卸载...${RESET}"
    if command -v systemctl >/dev/null 2>&1; then
        systemctl stop mtg >/dev/null 2>&1
        systemctl disable mtg >/dev/null 2>&1
        rm -f "$SERVICE_FILE"
        systemctl daemon-reload
    else
        pkill -9 -f "/usr/local/bin/mtg_guard.sh" 2>/dev/null
        pkill -9 -f "mtg run" 2>/dev/null
        crontab -l 2>/dev/null | grep -v -E "mtg_guard.sh|mtg run ${CONFIG_FILE}" | crontab -
    fi

    rm -f /usr/local/bin/mtg "$CONFIG_FILE" "$INFO_FILE" /usr/local/bin/mtp "$LOG_FILE" "$GUARD_FILE" "$GUARD_LOG"
    echo -e "${GREEN}✅ 卸载完成！${RESET}"
    sleep 2
    exit 0
}

update_script() {
    clear
    echo -e "${YELLOW}正在从 GitHub 拉取最新面板代码...${RESET}"
    local tmp_file
    tmp_file=$(mktemp)

    if curl -fsSL --connect-timeout 10 "${SCRIPT_URL}" -o "$tmp_file" 2>/dev/null; then
        sed -i 's/\r$//' "$tmp_file"
        if bash -n "$tmp_file" 2>/dev/null; then
            mv "$tmp_file" /usr/local/bin/mtp
            chmod +x /usr/local/bin/mtp
            echo -e "${GREEN}✅ 面板更新完成！请重新输入 mtp 启动最新版。${RESET}"
            sleep 2
            exit 0
        else
            rm -f "$tmp_file"
            echo -e "${RED}❌ 新脚本语法校验失败，已取消更新！${RESET}"
            sleep 2
        fi
    else
        rm -f "$tmp_file"
        echo -e "${RED}❌ 下载失败，请检查网络！${RESET}"
        sleep 2
    fi
    pause
}

if [ ! -f "/usr/local/bin/mtp" ]; then
    curl -fsSL --connect-timeout 10 "${SCRIPT_URL}" -o /usr/local/bin/mtp 2>/dev/null && chmod +x /usr/local/bin/mtp
fi

while true; do
    clear
    if [ -f "$INFO_FILE" ]; then
        CURRENT_PUBLIC_IP=$(read_info_value PUBLIC_IP)
        CURRENT_OUT_PORT=$(read_info_value OUT_PORT)
        CURRENT_IP_TYPE=$(read_info_value IP_TYPE)
        [ -z "$CURRENT_IP_TYPE" ] && CURRENT_IP_TYPE="4"
    else
        CURRENT_PUBLIC_IP="-"
        CURRENT_OUT_PORT="-"
        CURRENT_IP_TYPE="-"
    fi

    echo -e "${CYAN}=========================================${RESET}"
    echo -e "   🦇 MTP 代理管理面板 ${GREEN}${SCRIPT_VERSION}${RESET}"
    echo -e "${CYAN}=========================================${RESET}"
    echo -e "当前状态: ${RESET}$(get_status)"
    echo -e "当前地址: ${YELLOW}${CURRENT_PUBLIC_IP}:${CURRENT_OUT_PORT}${RESET}"
    echo -e "IP 类型:  ${GREEN}IPv${CURRENT_IP_TYPE}${RESET}"
    echo -e "快捷指令: ${GREEN}mtp${RESET}"
    echo -e "MTG版本:  ${YELLOW}v${MTG_VERSION}${RESET}"
    echo -e "${CYAN}-----------------------------------------${RESET}"
    echo -e "  ${GREEN}1.${RESET} 安装 / 重装 MTP (支持 IPv4 / IPv6)"
    echo -e "  ${GREEN}2.${RESET} 查看当前 TG 链接与信息"
    echo -e "  ${GREEN}3.${RESET} 修改端口、IP 与伪装域名"
    echo -e "  ${YELLOW}4.${RESET} 启动 MTP 服务"
    echo -e "  ${YELLOW}5.${RESET} 停止 MTP 服务"
    echo -e "  ${CYAN}6.${RESET} 重启 MTP 服务"
    echo -e "  ${CYAN}7.${RESET} 查看运行日志"
    echo -e "  ${RED}8.${RESET} 彻底卸载 MTP"
    echo -e "  ${BLUE}9.${RESET} 更新面板代码 (从 GitHub 同步)"
    echo -e "  ${GREEN}0.${RESET} 退出面板"
    echo -e "  ${YELLOW}00.${RESET} 返回主菜单 (NooMili)"
    echo -e "${CYAN}=========================================${RESET}"
    read -p "请输入序号选择功能: " choice

    case "$choice" in
        1) install_mtp ;;
        2) view_link ;;
        3) modify_config ;;
        4) start_service_manual ;;
        5) stop_service_manual ;;
        6) restart_service_manual ;;
        7) view_logs ;;
        8) uninstall_mtp ;;
        9) update_script ;;
        0) clear; exit 0 ;;
        00) [ -f "/usr/local/bin/n" ] && exec /usr/local/bin/n || { echo -e "${RED}未安装主控！${RESET}"; sleep 2; } ;;
        *) echo -e "${RED}输入错误！${RESET}"; sleep 1 ;;
    esac
done
EOF

chmod +x /usr/local/bin/mtp
echo -e "\033[32m✅ IPv6 版 MTP 已安装完成！\033[0m"
