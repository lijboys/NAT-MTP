#!/bin/bash

GREEN="\033[32m"
RED="\033[31m"
YELLOW="\033[33m"
CYAN="\033[36m"
RESET="\033[0m"

# 你的 GitHub Raw 链接 (已更新为 NooMili.sh)
NAT_URL="https://raw.githubusercontent.com/lijboys/NatTools/main/NooMili.sh"
MTP_URL="https://raw.githubusercontent.com/lijboys/NatTools/main/mtp.sh"
KOMARI_URL="https://raw.githubusercontent.com/lijboys/NatTools/main/komari.sh"

if [ "$EUID" -ne 0 ]; then echo -e "${RED}请使用 root 用户运行！${RESET}"; exit 1; fi

# 清理旧的 nat 快捷键 (兼容你之前的版本)
if [ -f "/usr/local/bin/nat" ]; then rm -f /usr/local/bin/nat; fi

# 安装主控快捷键 n
if [ ! -f "/usr/local/bin/n" ]; then
    curl -fsSL "${NAT_URL}" -o /usr/local/bin/n 2>/dev/null || cp -f "$0" /usr/local/bin/n
    chmod +x /usr/local/bin/n
fi

# ================= 系统基础功能 =================

sys_info() {
    clear
    echo -e "${CYAN}=========================================${RESET}"
    echo -e "           🖥️ 系统信息查询"
    echo -e "${CYAN}=========================================${RESET}"
    echo -e "主机名:   ${GREEN}$(hostname)${RESET}"
    if [ -f /etc/os-release ]; then
        echo -e "系统版本: ${GREEN}$(cat /etc/os-release | grep PRETTY_NAME | cut -d '"' -f 2)${RESET}"
    fi
    echo -e "内核版本: ${GREEN}$(uname -r)${RESET}"
    echo -e "CPU架构:  ${GREEN}$(uname -m)${RESET}"
    echo -e "CPU核心数:${GREEN}$(nproc) 核${RESET}"
    echo -e "内存使用: ${GREEN}$(free -m | awk 'NR==2{printf "%.2f%% ( %sMB / %sMB )", $3*100/$2, $3, $2}')${RESET}"
    echo -e "磁盘使用: ${GREEN}$(df -h / | awk 'NR==2{print $5, " (", $3, "/", $2, ")"}')${RESET}"
    echo -e "${CYAN}=========================================${RESET}"
    read -p "按回车键返回主菜单..."
}

sys_update() {
    clear
    echo -e "${YELLOW}正在更新系统软件源及包，请稍候...${RESET}"
    if [ -x "$(command -v apt)" ]; then
        apt update -y && apt upgrade -y
    elif [ -x "$(command -v yum)" ]; then
        yum update -y
    else
        echo -e "${RED}未知的包管理器，暂不支持自动更新。${RESET}"
    fi
    echo -e "${GREEN}✅ 系统更新完成！${RESET}"
    read -p "按回车键返回主菜单..."
}

sys_clean() {
    clear
    echo -e "${YELLOW}正在清理系统垃圾及无用内核/依赖...${RESET}"
    if [ -x "$(command -v apt)" ]; then
        apt autoremove -y && apt clean -y
    elif [ -x "$(command -v yum)" ]; then
        yum autoremove -y && yum clean all
    fi
    # 清理旧的系统日志 (保留最近1天)
    if command -v journalctl >/dev/null 2>&1; then
        journalctl --vacuum-time=1d >/dev/null 2>&1
    fi
    echo -e "${GREEN}✅ 系统清理完成！空间已释放。${RESET}"
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

update_nat() {
    clear
    echo -e "${YELLOW}正在从 GitHub 拉取最新主控代码...${RESET}"
    curl -fsSL "${NAT_URL}" -o /usr/local/bin/n
    chmod +x /usr/local/bin/n
    echo -e "${GREEN}✅ 主控面板更新完成！即将重启面板...${RESET}"
    sleep 2; /usr/local/bin/n
}

uninstall_nat() {
    clear
    echo -e "${CYAN}--- 卸载选项 ---${RESET}"
    echo -e "  ${RED}1.${RESET} 彻底卸载全部 (主控 + MTP + Komari)"
    echo -e "  ${YELLOW}2.${RESET} 仅卸载主控面板 (保留 MTP 和 Komari 独立运行)"
    echo -e "  ${GREEN}0.${RESET} 取消并返回"
    read -p "请输入选择: " un_choice
    case $un_choice in
        1)
            echo -e "${RED}正在清理所有组件...${RESET}"
            # 清理 MTP
            if [ -f "/usr/local/bin/mtp" ]; then
                systemctl stop mtg >/dev/null 2>&1; systemctl disable mtg >/dev/null 2>&1; rm -f /etc/systemd/system/mtg.service; systemctl daemon-reload
                pkill -f "mtg run" 2>/dev/null; crontab -l 2>/dev/null | grep -v "mtg run" | crontab -
                rm -f /usr/local/bin/mtg /etc/mtg.toml /etc/mtg_info.txt /usr/local/bin/mtp
            fi
            # 清理 Komari
            if [ -f "/usr/local/bin/komari" ]; then
                systemctl stop komari >/dev/null 2>&1; systemctl disable komari >/dev/null 2>&1; rm -f /etc/systemd/system/komari.service; systemctl daemon-reload
                pkill -f "komari" 2>/dev/null
                rm -rf /opt/komari /usr/local/bin/komari 
            fi
            rm -f /usr/local/bin/n
            echo -e "${GREEN}✅ 所有工具已彻底卸载！再见！${RESET}"
            exit 0
            ;;
        2)
            rm -f /usr/local/bin/n
            echo -e "${GREEN}✅ 主控面板已卸载！(MTP 和 Komari 仍可通过各自的快捷键启动)${RESET}"
            exit 0
            ;;
        *) return ;;
    esac
}

# ================= 主菜单 =================
while true; do
    clear
    echo -e "${CYAN}=========================================${RESET}"
    echo -e "       🛠️ NatTools 综合管理工具箱 🛠️"
    echo -e "${CYAN}=========================================${RESET}"
    echo -e "快捷指令: ${GREEN}n${RESET}"
    echo -e "${CYAN}-----------------------------------------${RESET}"
    echo -e "  ${GREEN}1.${RESET} 🖥️ 系统信息查询"
    echo -e "  ${GREEN}2.${RESET} 🔄 系统更新 (apt/yum)"
    echo -e "  ${GREEN}3.${RESET} 🧹 系统清理 (释放空间)"
    echo -e "${CYAN}-----------------------------------------${RESET}"
    echo -e "  ${GREEN}4.${RESET} 🦇 进入 MTP 代理管理面板"
    echo -e "  ${GREEN}5.${RESET} 📊 进入 Komari 探针管理面板"
    echo -e "${CYAN}-----------------------------------------${RESET}"
    echo -e "  ${YELLOW}6.${RESET} 👑 老王一键工具箱 (外部)"
    echo -e "  ${YELLOW}7.${RESET} 🦁 科技lion一键脚本 (外部)"
    echo -e "${CYAN}-----------------------------------------${RESET}"
    echo -e "  ${CYAN}8.${RESET} 🔄 更新 NatTools 主控脚本"
    echo -e "  ${RED}9.${RESET} 🗑️ 卸载工具箱"
    echo -e "  ${GREEN}0.${RESET} 退出面板"
    echo -e "${CYAN}=========================================${RESET}"
    read -p "请输入序号选择功能: " choice
    
    case $choice in
        1) sys_info ;;
        2) sys_update ;;
        3) sys_clean ;;
        4) launch_mtp ;;
        5) launch_komari ;;
        6) clear; bash <(curl -fsSL ssh_tool.eooce.com) ;;
        7) clear; bash <(curl -sL kejilion.sh) ;;
        8) update_nat ;;
        9) uninstall_nat ;;
        0) clear; exit 0 ;;
        *) echo -e "${RED}输入错误！${RESET}"; sleep 1 ;;
    esac
done
