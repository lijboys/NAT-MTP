#!/bin/bash

# ============================================
# SSHTools 工具箱 - NAT/VPS 多功能管理面板
# Version: v2.2.4
# ============================================

GREEN="\033[32m"
RED="\033[31m"
YELLOW="\033[33m"
CYAN="\033[36m"
BLUE="\033[34m"
RESET="\033[0m"

SCRIPT_VERSION="v2.2.4"

# GitHub Raw 链接
NAT_URL="https://raw.githubusercontent.com/lijboys/SSHTools/refs/heads/main/NooMili.sh"
MTP_URL="https://raw.githubusercontent.com/lijboys/SSHTools/refs/heads/main/mtp.sh"
KOMARI_URL="https://raw.githubusercontent.com/lijboys/SSHTools/refs/heads/main/komari.sh"

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
    local ip_type=$1
    local sources=()
    if [ "$ip_type" = "4" ]; then
        sources=("ipv4.icanhazip.com" "api.ipify.org" "ifconfig.me")
    else
        sources=("ipv6.icanhazip.com" "api6.ipify.org" "ifconfig.co")
    fi
    
    for src in "${sources[@]}"; do
        local result=$(curl -s${ip_type}m3 --connect-timeout 3 "$src" 2>/dev/null)
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
# （show_sys_info、update_system、clean_system、nat_info_card 保持不变，这里省略以节省篇幅）
# 你原来的这四个函数可以直接复制粘贴进去，无需修改

# ================= NAT 信息卡（保持不变） =================
# nat_info_card 函数也保持你原来的代码

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
    fi
    /usr/local/bin/mtp
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
    fi
    /usr/local/bin/komari
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

    # 已安装检测
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
    local tmp_file=$(mktemp)
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
    echo -e "  ${RED}1.${RESET} 彻底卸载全部 (主控 + MTP + Komari)"
    echo -e "  ${YELLOW}2.${RESET} 仅卸载主控面板 (保留子模块独立运行)"
    echo -e "  ${GREEN}0.${RESET} 取消并返回"
    read -p "请输入选择: " un_choice
    case $un_choice in
        1)
            echo -e "${RED}正在清理所有组件...${RESET}"
            if [ -f "/usr/local/bin/mtp" ]; then
                systemctl stop mtg >/dev/null 2>&1
                systemctl disable mtg >/dev/null 2>&1
                rm -f /etc/systemd/system/mtg.service
                systemctl daemon-reload
                pkill -f "mtg run" 2>/dev/null
                crontab -l 2>/dev/null | grep -v "mtg run" | crontab -
                rm -f /usr/local/bin/mtg /etc/mtg.toml /etc/mtg_info.txt /usr/local/bin/mtp
            fi
            if [ -f "/usr/local/bin/komari" ]; then
                systemctl stop komari >/dev/null 2>&1
                systemctl disable komari >/dev/null 2>&1
                rm -f /etc/systemd/system/komari.service
                systemctl daemon-reload
                pkill -f "komari" 2>/dev/null
                rm -rf /opt/komari /usr/local/bin/komari
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

# ================= 主菜单（已优化序号） =================
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
    echo -e "  ${GREEN}7.${RESET} 🛡️ 安装 SSL 面板 (Lucky)"
    echo -e "${CYAN}-----------------------------------------${RESET}"
    echo -e "  ${YELLOW}8.${RESET} 老王一键工具箱"
    echo -e "  ${YELLOW}9.${RESET} 科技lion一键脚本"
    echo -e "${CYAN}-----------------------------------------${RESET}"
    echo -e "  ${CYAN}u.${RESET} 更新主控脚本"
    echo -e "  ${RED}x.${RESET} 卸载工具箱"
    echo -e "  ${GREEN}0.${RESET} 退出面板"
    echo -e "${CYAN}=========================================${RESET}"
    read -p "请输入你的选择: " choice
    
    case "$choice" in
        1) show_sys_info ;;
        2) update_system ;;
        3) clean_system ;;
        4) nat_info_card ;;
        5) launch_mtp ;;
        6) launch_komari ;;
        7) launch_lucky ;;
        8) run_external "老王一键工具箱" "bash <(curl -fsSL ssh_tool.eooce.com)" ;;
        9) run_external "科技lion一键脚本" "bash <(curl -sL kejilion.sh)" ;;
        u|U) update_nat ;;
        x|X) uninstall_nat ;;
        0) clear; exit 0 ;;
        *) echo -e "${RED}输入错误，请重新选择！${RESET}"; sleep 1 ;;
    esac
done
