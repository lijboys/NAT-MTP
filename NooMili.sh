cat > /usr/local/bin/n <<'EOF'
#!/bin/bash

# ============================================
# SSHTools 工具箱 - NAT/VPS 多功能管理面板
# Version: v2.2.6
# ============================================

GREEN="\033[32m"
RED="\033[31m"
YELLOW="\033[33m"
CYAN="\033[36m"
BLUE="\033[34m"
RESET="\033[0m"

SCRIPT_VERSION="v2.2.6"

# GitHub Raw 链接
NAT_URL="https://raw.githubusercontent.com/lijboys/SSHTools/refs/heads/main/NooMili.sh"
MTP_URL="https://raw.githubusercontent.com/lijboys/SSHTools/refs/heads/main/mtp.sh"
KOMARI_URL="https://raw.githubusercontent.com/lijboys/SSHTools/refs/heads/main/komari.sh"
SOCKS5_URL="https://raw.githubusercontent.com/lijboys/SSHTools/refs/heads/main/s5.sh"

# 数据文件
IP_FILE="/etc/.noomili_ip"
PORTS_FILE="/etc/.noomili_ports"

# Root 检查
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}请使用 root 用户运行！${RESET}"
    exit 1
fi

# ================= 通用函数 =================

pause() {
    read -p "按回车键返回主菜单..."
}

# 通用公网IP获取（带超时和多源）
get_public_ip() {
    local ip_type=$1  # 4 或 6
    local sources=()
    if [ "$ip_type" = "4" ]; then
        sources=("ipv4.icanhazip.com" "api.ipify.org" "ifconfig.me")
    else
        sources=("ipv6.icanhazip.com" "api6.ipify.org" "ifconfig.co")
    fi
    
    for src in "${sources[@]}"; do
        local result
        result=$(curl -s${ip_type}m3 --connect-timeout 3 "$src" 2>/dev/null)
        if [ -n "$result" ]; then
            echo "$result"
            return 0
        fi
    done
    return 1
}

# 安装主控快捷键 n
install_shortcut() {
    if [ ! -f "/usr/local/bin/n" ]; then
        if curl -fsSL --connect-timeout 10 "${NAT_URL}" -o /usr/local/bin/n 2>/dev/null; then
            chmod +x /usr/local/bin/n
        elif [ -f "$0" ] && [ "$0" != "bash" ] && [ "$0" != "-bash" ]; then
            cp -f "$0" /usr/local/bin/n && chmod +x /usr/local/bin/n
        fi
    fi
}
install_shortcut

# ================= 系统基础功能 =================

show_sys_info() {
    clear
    echo -e "${CYAN}====================================================${RESET}"
    echo -e "                 🖥️  系统核心信息看板"
    echo -e "${CYAN}====================================================${RESET}"
    echo -e "${YELLOW}正在探测各项硬件与网络指标，请稍候...${RESET}"
    
    OS_NAME=$(grep -w "PRETTY_NAME" /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"')
    [ -z "$OS_NAME" ] && OS_NAME="Unknown OS"
    KERNEL_VER=$(uname -r)
    ARCH=$(uname -m)
    UPTIME=$(uptime -p 2>/dev/null | sed 's/up //')
    [ -z "$UPTIME" ] && UPTIME=$(uptime | awk -F'( |,|:)+' '{print $6,$7",",$8,"hours,",$9,"minutes"}')
    LOAD_AVG=$(awk '{print $1, $2, $3}' /proc/loadavg)
    
    if command -v systemd-detect-virt >/dev/null 2>&1; then
        VIRT_TYPE=$(systemd-detect-virt 2>/dev/null)
        [ -z "$VIRT_TYPE" ] && VIRT_TYPE="none"
    else
        VIRT_TYPE="未知"
    fi
    
    CPU_MODEL=$(awk -F': ' '/model name/ {print $2; exit}' /proc/cpuinfo)
    CPU_CORES=$(nproc)
    [ -z "$CPU_MODEL" ] && CPU_MODEL="Virtual CPU (未识别)"
    
    MEM_INFO=$(free -m | grep Mem)
    MEM_TOTAL=$(echo "$MEM_INFO" | awk '{print $2}')
    MEM_USED=$(echo "$MEM_INFO" | awk '{print $3}')
    if [ "$MEM_TOTAL" -gt 0 ] 2>/dev/null; then
        MEM_PERCENT=$(awk "BEGIN {printf \"%.1f\", $MEM_USED/$MEM_TOTAL*100}")
    else
        MEM_PERCENT="0.0"
    fi
    
    SWAP_INFO=$(free -m | grep Swap)
    SWAP_TOTAL=$(echo "$SWAP_INFO" | awk '{print $2}')
    SWAP_USED=$(echo "$SWAP_INFO" | awk '{print $3}')
    
    DISK_INFO=$(df -h / | tail -n 1)
    DISK_TOTAL=$(echo "$DISK_INFO" | awk '{print $2}')
    DISK_USED=$(echo "$DISK_INFO" | awk '{print $3}')
    DISK_PERCENT=$(echo "$DISK_INFO" | awk '{print $5}')
    
    LOCAL_IP=$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}' | head -1)
    [ -z "$LOCAL_IP" ] && LOCAL_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
    [ -z "$LOCAL_IP" ] && LOCAL_IP="未分配"
    
    if [ -f "$IP_FILE" ]; then
        IPV4="${GREEN}$(cat "$IP_FILE")${RESET} ${YELLOW}(已手动校准)${RESET}"
    else
        IPV4_RAW=$(get_public_ip 4)
        if [[ "$IPV4_RAW" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            IPV4="$IPV4_RAW ${RED}(出网IP)${RESET}"
        else
            IPV4="${RED}获取失败${RESET}"
        fi
    fi
    
    IPV6_RAW=$(get_public_ip 6)
    if [[ "$IPV6_RAW" =~ ^[0-9a-fA-F:]+:[0-9a-fA-F:]+ ]]; then
        IPV6="$IPV6_RAW"
    else
        IPV6="未分配或无 IPv6"
    fi
    
    if [ -f "$PORTS_FILE" ]; then
        NAT_PORTS=$(cat "$PORTS_FILE")
    else
        NAT_PORTS="${YELLOW}未设置 (按 p 设置)${RESET}"
    fi
    
    NET_IFACE=$(ip route | grep default | awk '{print $5}' | head -1)
    TRAFFIC_INFO=""
    if [ -n "$NET_IFACE" ] && [ -d "/sys/class/net/$NET_IFACE" ]; then
        RX_BYTES=$(cat /sys/class/net/$NET_IFACE/statistics/rx_bytes 2>/dev/null)
        TX_BYTES=$(cat /sys/class/net/$NET_IFACE/statistics/tx_bytes 2>/dev/null)
        if [ -n "$RX_BYTES" ] && [ -n "$TX_BYTES" ]; then
            RX_GB=$(awk "BEGIN {printf \"%.2f\", $RX_BYTES/1024/1024/1024}")
            TX_GB=$(awk "BEGIN {printf \"%.2f\", $TX_BYTES/1024/1024/1024}")
            TRAFFIC_INFO="↓${RX_GB}GB ↑${TX_GB}GB"
        fi
    fi
    
    clear
    echo -e "${CYAN}====================================================${RESET}"
    echo -e " 💻 ${GREEN}系统 OS:${RESET}    $OS_NAME ($ARCH)"
    echo -e " ⚙️  ${GREEN}系统内核:${RESET}  $KERNEL_VER"
    echo -e " 🎭 ${GREEN}虚拟类型:${RESET}  $VIRT_TYPE"
    echo -e " ⏱️  ${GREEN}在线时间:${RESET}  $UPTIME"
    echo -e " 📈 ${GREEN}系统负载:${RESET}  $LOAD_AVG ${YELLOW}(1/5/15分)${RESET}"
    echo -e "${CYAN}----------------------------------------------------${RESET}"
    echo -e " 🧠 ${GREEN}CPU 核心:${RESET}  $CPU_CORES Core(s)"
    echo -e " 🧠 ${GREEN}CPU 型号:${RESET}  $CPU_MODEL"
    echo -e " 📦 ${GREEN}内存占用:${RESET}  ${YELLOW}${MEM_USED}MB${RESET} / ${MEM_TOTAL}MB (${MEM_PERCENT}%)"
    echo -e " 💾 ${GREEN}Swap:${RESET}      ${SWAP_USED}MB / ${SWAP_TOTAL}MB"
    echo -e " 💽 ${GREEN}硬盘空间:${RESET}  ${YELLOW}${DISK_USED}${RESET} / ${DISK_TOTAL} (${DISK_PERCENT})"
    echo -e "${CYAN}----------------------------------------------------${RESET}"
    echo -e " 🌐 ${GREEN}内网 IPv4:${RESET} ${LOCAL_IP}"
    echo -e " 🌍 ${GREEN}公网 IPv4:${RESET} $IPV4"
    echo -e " 🌍 ${GREEN}公网 IPv6:${RESET} ${YELLOW}${IPV6}${RESET}"
    echo -e " 🔌 ${GREEN}NAT 端口:${RESET}  ${NAT_PORTS}"
    if [ -n "$TRAFFIC_INFO" ]; then
        echo -e " 📊 ${GREEN}流量统计:${RESET}  $TRAFFIC_INFO ${YELLOW}(自开机)${RESET}"
    fi
    echo -e "${CYAN}====================================================${RESET}"
    echo -e "${YELLOW}操作: [回车]返回 [c]校准IP [p]设置端口 [d]恢复自动${RESET}"
    read -p "请输入选择: " sub_choice
    
    case "$sub_choice" in
        c|C)
            echo ""
            read -p "👉 请输入控制面板看到的真实 IPv4: " user_ip
            if [[ "$user_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                echo "$user_ip" > "$IP_FILE"
                echo -e "${GREEN}✅ IP 校准成功！已永久保存。${RESET}"
                sleep 1
                show_sys_info
            else
                echo -e "${RED}❌ 格式错误！${RESET}"
                sleep 2
                show_sys_info
            fi
            ;;
        p|P)
            echo ""
            read -p "👉 请输入NAT端口范围 (如 10001-10020): " user_ports
            if [ -n "$user_ports" ]; then
                echo "$user_ports" > "$PORTS_FILE"
                echo -e "${GREEN}✅ 端口范围已保存！${RESET}"
                sleep 1
                show_sys_info
            else
                echo -e "${RED}❌ 输入为空！${RESET}"
                sleep 2
                show_sys_info
            fi
            ;;
        d|D)
            rm -f "$IP_FILE"
            echo -e "${YELLOW}已恢复自动获取 IP。${RESET}"
            sleep 1
            show_sys_info
            ;;
    esac
}

update_system() {
    clear
    echo -e "${CYAN}=========================================${RESET}"
    echo -e "          🔄 正在执行全自动系统更新"
    echo -e "${CYAN}=========================================${RESET}"
    
    if command -v apt-get >/dev/null 2>&1; then
        echo -e "${YELLOW}检测到 Debian/Ubuntu，使用 APT 更新...${RESET}"
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -y
        apt-get upgrade -y
    elif command -v dnf >/dev/null 2>&1; then
        echo -e "${YELLOW}检测到新版 RHEL 系统，使用 DNF 更新...${RESET}"
        dnf makecache
        dnf update -y
    elif command -v yum >/dev/null 2>&1; then
        echo -e "${YELLOW}检测到 CentOS/RHEL，使用 YUM 更新...${RESET}"
        yum makecache
        yum update -y
    elif command -v apk >/dev/null 2>&1; then
        echo -e "${YELLOW}检测到 Alpine，使用 APK 更新...${RESET}"
        apk update && apk upgrade
    else
        echo -e "${RED}未知的包管理器！请手动执行更新。${RESET}"
    fi
    
    echo -e "${CYAN}=========================================${RESET}"
    echo -e "${GREEN}✅ 系统更新完毕！${RESET}"
    pause
}

clean_system() {
    clear
    echo -e "${CYAN}=========================================${RESET}"
    echo -e "          🧹 开始深度系统瘦身清理"
    echo -e "${CYAN}=========================================${RESET}"
    
    SPACE_BEFORE=$(df / | tail -n 1 | awk '{print $3}')
    
    echo -e "${YELLOW}[1/3] 清理 systemd 冗余日志...${RESET}"
    if command -v journalctl >/dev/null 2>&1; then
        journalctl --vacuum-size=50M >/dev/null 2>&1
    fi
    
    echo -e "${YELLOW}[2/3] 清理软件包缓存与孤儿依赖...${RESET}"
    if command -v apt-get >/dev/null 2>&1; then
        export DEBIAN_FRONTEND=noninteractive
        apt-get autoremove -y >/dev/null 2>&1
        apt-get clean >/dev/null 2>&1
    elif command -v dnf >/dev/null 2>&1; then
        dnf autoremove -y >/dev/null 2>&1
        dnf clean all >/dev/null 2>&1
    elif command -v yum >/dev/null 2>&1; then
        yum autoremove -y >/dev/null 2>&1
        yum clean all >/dev/null 2>&1
    fi
    
    echo -e "${YELLOW}[3/3] 清空临时文件残余...${RESET}"
    rm -rf /tmp/* /var/tmp/* >/dev/null 2>&1
    
    SPACE_AFTER=$(df / | tail -n 1 | awk '{print $3}')
    FREED_KB=$((SPACE_BEFORE - SPACE_AFTER))
    
    echo -e "${CYAN}=========================================${RESET}"
    if [ "$FREED_KB" -le 0 ]; then
        echo -e "${GREEN}✅ 清理完成！系统已经很干净了~${RESET}"
    else
        FREED_MB=$(awk "BEGIN {printf \"%.2f\", $FREED_KB/1024}")
        echo -e "${GREEN}✅ 清理完成！释放了 ${YELLOW}${FREED_MB} MB${GREEN} 空间！${RESET}"
    fi
    pause
}

# ================= NAT 信息卡 =================

nat_info_card() {
    clear
    echo -e "${CYAN}====================================================${RESET}"
    echo -e "              📇 NAT 小鸡信息卡"
    echo -e "${CYAN}====================================================${RESET}"
    
    if [ -f "$IP_FILE" ]; then
        CARD_IPV4=$(cat "$IP_FILE")
    else
        CARD_IPV4=$(get_public_ip 4)
        [ -z "$CARD_IPV4" ] && CARD_IPV4="N/A"
    fi
    
    CARD_IPV6=$(get_public_ip 6)
    [ -z "$CARD_IPV6" ] && CARD_IPV6="N/A"
    
    if [ -f "$PORTS_FILE" ]; then
        CARD_PORTS=$(cat "$PORTS_FILE")
    else
        CARD_PORTS="未设置"
    fi
    
    HOSTNAME_INFO=$(hostname)
    
    echo -e " 📛 ${GREEN}主机名:${RESET}    $HOSTNAME_INFO"
    echo -e " 🌍 ${GREEN}IPv4:${RESET}      $CARD_IPV4"
    echo -e " 🌍 ${GREEN}IPv6:${RESET}      $CARD_IPV6"
    echo -e " 🔌 ${GREEN}端口范围:${RESET}  $CARD_PORTS"
    echo -e "${CYAN}----------------------------------------------------${RESET}"
    echo -e "${YELLOW} 常用端口占用检测:${RESET}"
    
    for port in 22 80 443 8080; do
        if ss -tlnp 2>/dev/null | grep -q ":$port "; then
            PROC=$(ss -tlnp 2>/dev/null | grep ":$port " | head -1 | grep -oP 'users:\(\("\K[^"]+' | head -1)
            echo -e "  端口 ${YELLOW}$port${RESET}: ${RED}已占用${RESET} ${CYAN}($PROC)${RESET}"
        else
            echo -e "  端口 ${YELLOW}$port${RESET}: ${GREEN}空闲${RESET}"
        fi
    done
    
    echo -e "${CYAN}====================================================${RESET}"
    echo -e "${YELLOW} 一键复制格式（可粘贴到笔记）:${RESET}"
    echo ""
    echo "  主机: $HOSTNAME_INFO"
    echo "  IPv4: $CARD_IPV4"
    echo "  IPv6: $CARD_IPV6"
    echo "  端口: $CARD_PORTS"
    echo ""
    echo -e "${CYAN}====================================================${RESET}"
    pause
}

# ================= 业务与外部脚本 =================

launch_mtp() {
    if [ ! -f "/usr/local/bin/mtp" ]; then
        echo -e "${YELLOW}首次进入，正在拉取 MTP 代理面板...${RESET}"
        if ! curl -fsSL --connect-timeout 10 "${MTP_URL}" -o /usr/local/bin/mtp; then
            echo -e "${RED}❌ 下载失败！${RESET}"
            pause
            return
        fi
        chmod +x /usr/local/bin/mtp
        sleep 1
    fi
    exec /usr/local/bin/mtp
}

launch_komari() {
    if [ ! -f "/usr/local/bin/komari" ]; then
        echo -e "${YELLOW}首次进入，正在拉取 Komari 探针面板...${RESET}"
        if ! curl -fsSL --connect-timeout 10 "${KOMARI_URL}" -o /usr/local/bin/komari; then
            echo -e "${RED}❌ 下载失败！${RESET}"
            pause
            return
        fi
        chmod +x /usr/local/bin/komari
        sleep 1
    fi
    exec /usr/local/bin/komari
}

launch_s5() {
    if [ ! -f "/usr/local/bin/s5" ]; then
        echo -e "${YELLOW}首次进入，正在拉取 SOCKS5 管理面板...${RESET}"
        if ! curl -fsSL --connect-timeout 10 "${SOCKS5_URL}" -o /usr/local/bin/s5; then
            echo -e "${RED}❌ 下载失败！${RESET}"
            pause
            return
        fi
        chmod +x /usr/local/bin/s5
        sleep 1
    fi
    exec /usr/local/bin/s5
}

launch_lucky() {
    clear
    echo -e "${CYAN}=========================================${RESET}"
    echo -e "        🛡️ Lucky (Web SSL/反代管理)部署"
    echo -e "${CYAN}=========================================${RESET}"
    echo -e "Lucky 是一款极低内存占用的 Web 面板工具。"
    echo -e "支持自动申请 SSL 证书 + 反向代理。"
    echo -e "非常适合 NAT 小鸡使用！"
    echo -e "${CYAN}-----------------------------------------${RESET}"

    if command -v lucky >/dev/null 2>&1 || [ -d "/etc/lucky" ] || [ -d "/opt/lucky" ]; then
        echo -e "${YELLOW}⚠️ 检测到 Lucky 可能已经安装。${RESET}"
        read -p "是否仍然继续执行官方安装脚本？[Y/n]: " install_choice
    else
        read -p "确认安装 Lucky 面板吗？[Y/n]: " install_choice
    fi

    if [[ -z "$install_choice" || "$install_choice" == "Y" || "$install_choice" == "y" ]]; then
        echo -e "${YELLOW}正在调用 Lucky 官方一键安装脚本...${RESET}"
        curl -fsSL https://gitee.com/gdy666/lucky/raw/main/install.sh | bash
        echo -e "${GREEN}✅ Lucky 部署完毕！${RESET}"
    else
        echo -e "${YELLOW}已取消安装。${RESET}"
    fi
    pause
}

# 第三方外部脚本 → 默认 Y（直接回车就执行）
run_external() {
    local name=$1
    local cmd=$2
    clear
    echo -e "${YELLOW}即将执行外部脚本: ${CYAN}$name${RESET}"
    echo -e "${RED}⚠️ 来自第三方，请确认你信任该来源！${RESET}"
    read -p "确认继续吗？[Y/n]: " confirm
    if [[ -z "$confirm" || "$confirm" == "y" || "$confirm" == "Y" ]]; then
        eval "$cmd"
    else
        echo -e "${YELLOW}已取消。${RESET}"
        sleep 1
    fi
}

update_nat() {
    clear
    echo -e "${YELLOW}正在从 GitHub 拉取最新主控代码...${RESET}"
    local tmp_file
    tmp_file=$(mktemp)
    if curl -fsSL --connect-timeout 10 "${NAT_URL}" -o "$tmp_file"; then
        if bash -n "$tmp_file" 2>/dev/null; then
            mv "$tmp_file" /usr/local/bin/n
            chmod +x /usr/local/bin/n
            echo -e "${GREEN}✅ 更新成功！即将重启...${RESET}"
            sleep 2
            exec /usr/local/bin/n
        else
            rm -f "$tmp_file"
            echo -e "${RED}❌ 下载的脚本有语法错误，已取消更新！${RESET}"
            pause
        fi
    else
        rm -f "$tmp_file"
        echo -e "${RED}❌ 下载失败，请检查网络！${RESET}"
        pause
    fi
}

uninstall_nat() {
    clear
    echo -e "${CYAN}--- 卸载选项 ---${RESET}"
    echo -e "  ${RED}1.${RESET} 彻底卸载全部 (主控 + MTP + Komari + SOCKS5)"
    echo -e "  ${YELLOW}2.${RESET} 仅卸载主控面板 (保留子模块独立运行)"
    echo -e "  ${GREEN}0.${RESET} 取消并返回"
    read -p "请输入选择: " un_choice
    case "$un_choice" in
        1)
            echo -e "${RED}正在清理所有组件...${RESET}"
            if [ -f "/usr/local/bin/mtp" ]; then
                if command -v rc-service >/dev/null 2>&1; then
                    rc-service mtg stop >/dev/null 2>&1
                    rc-update del mtg >/dev/null 2>&1
                else
                    systemctl stop mtg >/dev/null 2>&1
                    systemctl disable mtg >/dev/null 2>&1
                fi
                rm -f /etc/init.d/mtg /etc/systemd/system/mtg.service
                systemctl daemon-reload 2>/dev/null
                pkill -f "mtg run" 2>/dev/null
                crontab -l 2>/dev/null | grep -v "mtg run" | crontab - 2>/dev/null
                rm -f /usr/local/bin/mtg /etc/mtg.toml /etc/mtg_info.txt /usr/local/bin/mtp
            fi
            if [ -f "/usr/local/bin/komari" ]; then
                if command -v rc-service >/dev/null 2>&1; then
                    rc-service komari stop >/dev/null 2>&1
                    rc-update del komari >/dev/null 2>&1
                else
                    systemctl stop komari >/dev/null 2>&1
                    systemctl disable komari >/dev/null 2>&1
                fi
                rm -f /etc/init.d/komari /etc/systemd/system/komari.service
                systemctl daemon-reload 2>/dev/null
                pkill -f "komari" 2>/dev/null
                rm -rf /opt/komari /usr/local/bin/komari
            fi
            if [ -f "/usr/local/bin/s5" ]; then
                if command -v rc-service >/dev/null 2>&1; then
                    rc-service danted stop >/dev/null 2>&1
                    rc-update del danted >/dev/null 2>&1
                else
                    systemctl stop danted >/dev/null 2>&1
                    systemctl disable danted >/dev/null 2>&1
                fi
                rm -f /etc/init.d/danted /etc/danted.conf /etc/s5_info.txt /usr/local/bin/s5 /var/log/danted.log
            fi
            echo -e "${YELLOW}提示: 如果安装了 Lucky，请输入 lucky_uninstall 卸载。${RESET}"
            rm -f /usr/local/bin/n "$IP_FILE" "$PORTS_FILE"
            echo -e "${GREEN}✅ 全部组件已卸载！再见！${RESET}"
            exit 0
            ;;
        2)
            rm -f /usr/local/bin/n "$IP_FILE" "$PORTS_FILE"
            echo -e "${GREEN}✅ 主控面板已卸载！${RESET}"
            exit 0
            ;;
        *) return ;;
    esac
}

# ================= 主菜单 =================
while true; do
    clear
    echo -e "${CYAN} _    _             __  __ _ _ _ ${RESET}"
    echo -e "${CYAN}| \ | |           |  \/  (_) (_) ${RESET}"
    echo -e "${CYAN}|  \| | ___   ___ | \  / |_| |_  ${RESET}"
    echo -e "${CYAN}| . \` |/ _ \ / _ \| |\/| | | | | ${RESET}"
    echo -e "${CYAN}| |\  | (_) | (_) | |  | | | | | ${RESET}"
    echo -e "${CYAN}\_| \_/\___/ \___/\_|  |_/_|_|_| ${RESET}"
    echo -e "${CYAN}=========================================${RESET}"
    echo -e " SSHTools工具箱 ${GREEN}${SCRIPT_VERSION}${RESET}"
    echo -e " 命令行输入 ${YELLOW}n${RESET} 可快速启动脚本"
    echo -e "${CYAN}-----------------------------------------${RESET}"
    echo -e "  ${GREEN}1.${RESET} 系统信息查询"
    echo -e "  ${GREEN}2.${RESET} 系统更新"
    echo -e "  ${GREEN}3.${RESET} 系统清理"
    echo -e "  ${GREEN}4.${RESET} 📇 NAT 信息卡"
    echo -e "${CYAN}-----------------------------------------${RESET}"
    echo -e "  ${GREEN}5.${RESET} 进入 MTP 代理管理面板"
    echo -e "  ${GREEN}6.${RESET} 进入 Komari 探针管理面板"
    echo -e "  ${GREEN}7.${RESET} 进入 SOCKS5 管理面板"
    echo -e "  ${GREEN}8.${RESET} 🛡️ 安装 SSL 面板 (Lucky)"
    echo -e "${CYAN}-----------------------------------------${RESET}"
    echo -e "  ${YELLOW}9.${RESET} 老王一键工具箱"
    echo -e "  ${YELLOW}10.${RESET} 科技lion一键脚本"
    echo -e "${CYAN}-----------------------------------------${RESET}"
    echo -e "  ${CYAN}u.${RESET}
