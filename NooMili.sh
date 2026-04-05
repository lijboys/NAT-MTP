#!/bin/bash

GREEN="\033[32m"
RED="\033[31m"
YELLOW="\033[33m"
CYAN="\033[36m"
BLUE="\033[34m"
RESET="\033[0m"

# 你的 GitHub Raw 链接 (已全面更新为 SSHTools 仓库)
NAT_URL="https://raw.githubusercontent.com/lijboys/SSHTools/refs/heads/main/NooMili.sh"
MTP_URL="https://raw.githubusercontent.com/lijboys/SSHTools/refs/heads/main/mtp.sh"
KOMARI_URL="https://raw.githubusercontent.com/lijboys/SSHTools/refs/heads/main/komari.sh"

if [ "$EUID" -ne 0 ]; then echo -e "${RED}请使用 root 用户运行！${RESET}"; exit 1; fi

# 安装主控快捷键 n
if [ ! -f "/usr/local/bin/n" ]; then
    curl -fsSL "${NAT_URL}" -o /usr/local/bin/n 2>/dev/null || cp -f "$0" /usr/local/bin/n
    chmod +x /usr/local/bin/n
fi

# ================= 系统基础功能 =================

show_sys_info() {
    clear
    echo -e "${CYAN}====================================================${RESET}"
    echo -e "                 🖥️  系统核心信息看板"
    echo -e "${CYAN}====================================================${RESET}"
    
    echo -e "${YELLOW}正在探测各项硬件与网络指标，请稍候...${RESET}"
    
    # 系统与内核
    OS_NAME=$(cat /etc/os-release | grep -w "PRETTY_NAME" | cut -d= -f2 | tr -d '"')
    KERNEL_VER=$(uname -r)
    ARCH=$(uname -m)
    UPTIME=$(uptime -p | sed 's/up //')
    LOAD_AVG=$(cat /proc/loadavg | awk '{print $1, $2, $3}')
    
    # CPU 信息
    CPU_MODEL=$(awk -F': ' '/model name/ {print $2}' /proc/cpuinfo | head -n 1)
    CPU_CORES=$(nproc)
    if [ -z "$CPU_MODEL" ]; then CPU_MODEL="Virtual CPU (未识别)"; fi
    
    # 内存信息
    MEM_INFO=$(free -m | grep Mem)
    MEM_TOTAL=$(echo $MEM_INFO | awk '{print $2}')
    MEM_USED=$(echo $MEM_INFO | awk '{print $3}')
    MEM_PERCENT=$(awk "BEGIN {printf \"%.1f\", $MEM_USED/$MEM_TOTAL*100}")
    
    # 硬盘信息 (根目录)
    DISK_INFO=$(df -h / | tail -n 1)
    DISK_TOTAL=$(echo $DISK_INFO | awk '{print $2}')
    DISK_USED=$(echo $DISK_INFO | awk '{print $3}')
    DISK_PERCENT=$(echo $DISK_INFO | awk '{print $5}')
    
    # IP 信息 (多源防挂检测，最长等待 3 秒)
    IPV4=$(curl -s4m3 ipv4.icanhazip.com 2>/dev/null || curl -s4m3 api.ipify.org 2>/dev/null)
    IPV6=$(curl -s6m3 ipv6.icanhazip.com 2>/dev/null || curl -s6m3 api6.ipify.org 2>/dev/null)
    LOCAL_IP=$(hostname -I | awk '{print $1}')
    
    clear
    echo -e "${CYAN}====================================================${RESET}"
    echo -e " 💻 ${GREEN}系统 OS:${RESET}   $OS_NAME ($ARCH)"
    echo -e " ⚙️  ${GREEN}系统内核:${RESET}  $KERNEL_VER"
    echo -e " ⏱️  ${GREEN}在线时间:${RESET}  $UPTIME"
    echo -e " 📈 ${GREEN}系统负载:${RESET}  $LOAD_AVG ${YELLOW}(1分/5分/15分)${RESET}"
    echo -e "${CYAN}----------------------------------------------------${RESET}"
    echo -e " 🧠 ${GREEN}CPU 核心:${RESET}  $CPU_CORES Core(s) | $CPU_MODEL"
    echo -e " 📦 ${GREEN}内存占用:${RESET}  ${YELLOW}${MEM_USED}MB${RESET} / ${MEM_TOTAL}MB (${MEM_PERCENT}%)"
    echo -e " 💽 ${GREEN}硬盘空间:${RESET}  ${YELLOW}${DISK_USED}${RESET} / ${DISK_TOTAL} (${DISK_PERCENT})"
    echo -e "${CYAN}----------------------------------------------------${RESET}"
    echo -e " 🌐 ${GREEN}内网 IPv4:${RESET} ${LOCAL_IP:-"未分配"}"
    echo -e " 🌍 ${GREEN}公网 IPv4:${RESET} ${YELLOW}${IPV4:-"未分配或无 IPv4"}${RESET}"
    echo -e " 🌍 ${GREEN}公网 IPv6:${RESET} ${YELLOW}${IPV6:-"未分配或无 IPv6"}${RESET}"
    echo -e "${CYAN}====================================================${RESET}"
    
    read -p "按回车键返回主菜单..."
}

update_system() {
    clear
    echo -e "${CYAN}=========================================${RESET}"
    echo -e "          🔄 正在执行全自动系统更新"
    echo -e "${CYAN}=========================================${RESET}"
    
    if command -v apt-get >/dev/null 2>&1; then
        echo -e "${YELLOW}检测到 Debian/Ubuntu 系统，正在使用 APT 更新...${RESET}"
        # 禁用交互式提示，防止更新卡住
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -y
        apt-get upgrade -y
    elif command -v yum >/dev/null 2>&1; then
        echo -e "${YELLOW}检测到 CentOS/RHEL 系系统，正在使用 YUM 更新...${RESET}"
        yum makecache
        yum update -y
    else
        echo -e "${RED}未知的包管理器！请手动执行更新。${RESET}"
    fi
    
    echo -e "${CYAN}=========================================${RESET}"
    echo -e "${GREEN}✅ 系统内核及软件包更新完毕！${RESET}"
    read -p "按回车键返回主菜单..."
}

clean_system() {
    clear
    echo -e "${CYAN}=========================================${RESET}"
    echo -e "          🧹 开始深度系统瘦身清理"
    echo -e "${CYAN}=========================================${RESET}"
    
    # 记录清理前的硬盘使用量 (KB)
    SPACE_BEFORE=$(df / | tail -n 1 | awk '{print $3}')
    
    # 1. 清理系统日志 (最容易爆满的地方，保留最近 50MB)
    echo -e "${YELLOW}[1/3] 正在清理 systemd 冗余日志记录...${RESET}"
    if command -v journalctl >/dev/null 2>&1; then
        journalctl --vacuum-size=50M >/dev/null 2>&1
    fi
    
    # 2. 清理包管理器缓存和无用依赖
    echo -e "${YELLOW}[2/3] 正在清理软件包缓存与孤儿依赖...${RESET}"
    if command -v apt-get >/dev/null 2>&1; then
        export DEBIAN_FRONTEND=noninteractive
        apt-get autoremove -y >/dev/null 2>&1
        apt-get clean >/dev/null 2>&1
    elif command -v yum >/dev/null 2>&1; then
        yum autoremove -y >/dev/null 2>&1
        yum clean all >/dev/null 2>&1
    fi
    
    # 3. 清空临时目录
    echo -e "${YELLOW}[3/3] 正在清空临时文件残余...${RESET}"
    rm -rf /tmp/* /var/tmp/* >/dev/null 2>&1
    
    # 计算清理出的空间
    SPACE_AFTER=$(df / | tail -n 1 | awk '{print $3}')
    FREED_KB=$((SPACE_BEFORE - SPACE_AFTER))
    
    # 防止因为后台写入导致算出来是负数
    if [ "$FREED_KB" -lt 0 ]; then FREED_KB=0; fi
    FREED_MB=$(awk "BEGIN {printf \"%.2f\", $FREED_KB/1024}")
    
    echo -e "${CYAN}=========================================${RESET}"
    echo -e "${GREEN}✅ 清理完成！本次共为您的小鸡释放了 ${YELLOW}${FREED_MB} MB${GREEN} 的硬盘空间！${RESET}"
    read -p "按回车键返回主菜单..."
}

# ================= 业务与外部脚本 =================

launch_mtp() {
    if [ ! -f "/usr/local/bin/mtp" ]; then
        echo -e "${YELLOW}首次进入，正在拉取 MTP 代理面板...${RESET}"
        curl -fsSL "${MTP_URL}" -o /usr/local/bin/mtp
        chmod +x /usr/local/bin/mtp
    fi
    /usr/local/bin/mtp
}

launch_komari() {
    if [ ! -f "/usr/local/bin/komari" ]; then
        echo -e "${YELLOW}首次进入，正在拉取 Komari 探针面板...${RESET}"
        curl -fsSL "${KOMARI_URL}" -o /usr/local/bin/komari
        chmod +x /usr/local/bin/komari
    fi
    /usr/local/bin/komari
}

launch_lucky() {
    clear
    echo -e "${CYAN}=========================================${RESET}"
    echo -e "        🛡️ Lucky (Web 版 SSL/反代管理)部署"
    echo -e "${CYAN}=========================================${RESET}"
    echo -e "说明：Lucky 是一款极低内存占用的 Web 面板工具。"
    echo -e "支持全自动申请 Let's Encrypt 等 SSL 证书，并自带反向代理功能。"
    echo -e "非常适合 NAT 小鸡使用！"
    echo -e "${CYAN}-----------------------------------------${RESET}"
    read -p "确认安装 Lucky 面板吗？[Y/n]: " install_choice
    if [[ "$install_choice" == "Y" || "$install_choice" == "y" || "$install_choice" == "" ]]; then
        echo -e "${YELLOW}正在调用 Lucky 官方一键安装脚本...${RESET}"
        # 调用大吉官方的一键脚本
        curl -fsSL https://gitee.com/gdy666/lucky/raw/main/install.sh | bash
        echo -e "${GREEN}✅ Lucky 部署完毕！请根据上方官方提示的端口和默认密码登录 Web 页面。${RESET}"
    else
        echo -e "${YELLOW}已取消安装。${RESET}"
    fi
    read -p "按回车键返回主菜单..."
}

update_nat() {
    clear
    echo -e "${YELLOW}正在从 GitHub 拉取最新主控代码...${RESET}"
    curl -fsSL "${NAT_URL}" -o /usr/local/bin/n
    chmod +x /usr/local/bin/n
    echo -e "${GREEN}✅ 主控面板更新完成！即将重启面板...${RESET}"
    sleep 2; exec /usr/local/bin/n
}

uninstall_nat() {
    clear
    echo -e "${CYAN}--- 卸载选项 ---${RESET}"
    echo -e "  ${RED}1.${RESET} 彻底卸载全部 (主控 + MTP + Komari)"
    echo -e "  ${YELLOW}2.${RESET} 仅卸载主控面板 (保留子模块独立运行)"
    echo -e "  ${GREEN}0.${RESET} 取消并返回"
    read -p "请输入选择: " un_choice
    case $un_choice in
        1)
            echo -e "${RED}正在清理所有组件...${RESET}"
            if [ -f "/usr/local/bin/mtp" ]; then
                systemctl stop mtg >/dev/null 2>&1; systemctl disable mtg >/dev/null 2>&1; rm -f /etc/systemd/system/mtg.service; systemctl daemon-reload
                pkill -f "mtg run" 2>/dev/null; crontab -l 2>/dev/null | grep -v "mtg run" | crontab -
                rm -f /usr/local/bin/mtg /etc/mtg.toml /etc/mtg_info.txt /usr/local/bin/mtp
            fi
            if [ -f "/usr/local/bin/komari" ]; then
                systemctl stop komari >/dev/null 2>&1; systemctl disable komari >/dev/null 2>&1; rm -f /etc/systemd/system/komari.service; systemctl daemon-reload
                pkill -f "komari" 2>/dev/null
                rm -rf /opt/komari /usr/local/bin/komari 
            fi
            # 提示手动卸载 Lucky
            echo -e "${YELLOW}提示: 如果你安装了 Lucky，请在终端输入 lucky_uninstall 进行彻底卸载。${RESET}"
            rm -f /usr/local/bin/n
            echo -e "${GREEN}✅ 基础工具已卸载！再见！${RESET}"
            exit 0
            ;;
        2)
            rm -f /usr/local/bin/n
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
    echo -e " SSHTools工具箱 ${GREEN}v2.2.0${RESET}"
    echo -e " 命令行输入 ${YELLOW}n${RESET} 可快速启动脚本"
    echo -e "${CYAN}-----------------------------------------${RESET}"
    echo -e "  ${GREEN}1.${RESET} 系统信息查询"
    echo -e "  ${GREEN}2.${RESET} 系统更新 (apt/yum)"
    echo -e "  ${GREEN}3.${RESET} 系统清理 (释放空间)"
    echo -e "${CYAN}-----------------------------------------${RESET}"
    echo -e "  ${GREEN}4.${RESET} 进入 MTP 代理管理面板"
    echo -e "  ${GREEN}5.${RESET} 进入 Komari 探针管理面板"
    echo -e "  ${GREEN}6.${RESET} 🛡️ 安装 SSL 面板 (Web自动证书管理)"
    echo -e "${CYAN}-----------------------------------------${RESET}"
    echo -e "  ${YELLOW}7.${RESET} 老王一键工具箱 (外部)"
    echo -e "  ${YELLOW}8.${RESET} 科技lion一键脚本 (外部)"
    echo -e "${CYAN}-----------------------------------------${RESET}"
    echo -e "  ${CYAN}9.${RESET} 更新 SSHTools 主控脚本"
    echo -e "  ${RED}10.${RESET} 卸载工具箱"
    echo -e "  ${GREEN}0.${RESET} 退出面板"
    echo -e "${CYAN}=========================================${RESET}"
    read -p "请输入你的选择: " choice
    
    case $choice in
        1) show_sys_info ;;
        2) update_system ;;
        3) clean_system ;;
        4) launch_mtp ;;
        5) launch_komari ;;
        6) launch_lucky ;;
        7) clear; bash <(curl -fsSL ssh_tool.eooce.com) ;;
        8) clear; bash <(curl -sL kejilion.sh) ;;
        9) update_nat ;;
        10) uninstall_nat ;;
        0) clear; exit 0 ;;
        *) echo -e "${RED}输入错误，请重新选择！${RESET}"; sleep 1 ;;
    esac
done
