#!/bin/bash

# 颜色设置
GREEN="\033[32m"
RED="\033[31m"
YELLOW="\033[33m"
CYAN="\033[36m"
RESET="\033[0m"

CONFIG_FILE="/etc/mtg.toml"
INFO_FILE="/etc/mtg_info.txt"

# 权限自检
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}请使用 root 用户运行此脚本！${RESET}"
  exit 1
fi

# 兼容无 systemd 系统的状态检测
get_status() {
    if command -v systemctl >/dev/null 2>&1; then
        if systemctl is-active --quiet mtg; then
            echo -e "${GREEN}运行中 (systemd)${RESET}"
        else
            echo -e "${RED}已停止${RESET}"
        fi
    else
        if pgrep -f "mtg run" > /dev/null; then
            echo -e "${GREEN}运行中 (nohup)${RESET}"
        else
            echo -e "${RED}已停止${RESET}"
        fi
    fi
}

install_mtp() {
    clear
    echo -e "${CYAN}=========================================${RESET}"
    echo -e "${CYAN}  🚀 开始部署 NAT 专属 mtg v2 代理${RESET}"
    echo -e "${CYAN}=========================================${RESET}"
    
    # 停止旧进程
    if command -v systemctl >/dev/null 2>&1; then systemctl stop mtg 2>/dev/null; fi
    pkill -f "mtg run" 2>/dev/null
    
    echo -e "${YELLOW}正在直连拉取官方 mtg v2 核心...${RESET}"
    wget -qO mtg.tar.gz https://github.com/9seconds/mtg/releases/download/v2.1.7/mtg-2.1.7-linux-amd64.tar.gz
    tar -zxf mtg.tar.gz
    mv mtg-2.1.7-linux-amd64/mtg /usr/local/bin/mtg
    chmod +x /usr/local/bin/mtg
    rm -rf mtg.tar.gz mtg-2.1.7-linux-amd64
    
    # 自动识别公网 IP
    AUTO_IP=$(curl -s4m5 ifconfig.me || curl -s4m5 ipinfo.io/ip)
    
    echo ""
    read -p "👉 1. 请输入小鸡的【内网端口】: " IN_PORT
    read -p "👉 2. 请输入商家的【公网 IPv4 地址】 (回车默认使用自动识别的 $AUTO_IP): " PUBLIC_IP
    PUBLIC_IP=${PUBLIC_IP:-$AUTO_IP}
    read -p "👉 3. 请输入面板分配的【公网端口】: " OUT_PORT
    
    echo -e "${YELLOW}正在生成 FakeTLS 伪装密钥 (bing.com)...${RESET}"
    # 修正了语法，去掉了 -c
    SECRET=$(/usr/local/bin/mtg generate-secret tls bing.com)
    
    cat > $CONFIG_FILE <<EOT
secret = "${SECRET}"
bind-to = "0.0.0.0:${IN_PORT}"
EOT

    # 兼容启动逻辑：优先使用 systemd，如果没有则用 nohup 和 crontab 开机自启
    if command -v systemctl >/dev/null 2>&1; then
        mkdir -p /etc/systemd/system/
        cat > /etc/systemd/system/mtg.service <<EOT
[Unit]
Description=MTG v2 Proxy
After=network.target
[Service]
ExecStart=/usr/local/bin/mtg run /etc/mtg.toml
Restart=always
RestartSec=3
[Install]
WantedBy=multi-user.target
EOT
        systemctl daemon-reload
        systemctl enable mtg >/dev/null 2>&1
        systemctl restart mtg
    else
        echo -e "${YELLOW}检测到系统无 systemctl，使用 nohup 进程守护...${RESET}"
        nohup /usr/local/bin/mtg run /etc/mtg.toml > /var/log/mtg.log 2>&1 &
        # 写入 crontab 实现开机自启
        (crontab -l 2>/dev/null | grep -v "mtg run"; echo "@reboot nohup /usr/local/bin/mtg run /etc/mtg.toml > /var/log/mtg.log 2>&1 &") | crontab -
    fi
    
    TG_LINK="tg://proxy?server=${PUBLIC_IP}&port=${OUT_PORT}&secret=${SECRET}"
    echo "IN_PORT=${IN_PORT}" > $INFO_FILE
    echo "PUBLIC_IP=${PUBLIC_IP}" >> $INFO_FILE
    echo "OUT_PORT=${OUT_PORT}" >> $INFO_FILE
    echo "SECRET=${SECRET}" >> $INFO_FILE
    echo "TG_LINK=${TG_LINK}" >> $INFO_FILE
    
    echo -e "\n${GREEN}✅ 部署成功！${RESET}"
    echo -e "你的 TG 一键直连链接是：\n${YELLOW}${TG_LINK}${RESET}\n"
    read -p "按回车键返回主菜单..."
}

view_link() {
    clear
    echo -e "${CYAN}=========================================${RESET}"
    if [ -f "$INFO_FILE" ]; then
        source $INFO_FILE
        echo -e "当前内网端口: ${GREEN}${IN_PORT}${RESET}"
        echo -e "当前公网地址: ${GREEN}${PUBLIC_IP}:${OUT_PORT}${RESET}\n"
        echo -e "${YELLOW}👉 TG 一键直连链接：${RESET}"
        echo -e "${GREEN}${TG_LINK}${RESET}"
    else
        echo -e "${RED}没有找到配置信息，请先选择 1 进行安装！${RESET}"
    fi
    echo -e "${CYAN}=========================================${RESET}"
    echo ""
    read -p "按回车键返回主菜单..."
}

modify_config() {
    clear
    if [ ! -f "$INFO_FILE" ]; then
        echo -e "${RED}请先安装 MTP 服务！${RESET}"
        read -p "按回车键返回..."
        return
    fi
    source $INFO_FILE
    echo -e "${CYAN}--- 修改 NAT 映射信息 ---${RESET}"
    read -p "输入新的【内网端口】 (回车保持 ${IN_PORT}): " NEW_IN
    NEW_IN=${NEW_IN:-$IN_PORT}
    read -p "输入新的【公网 IP】 (回车保持 ${PUBLIC_IP}): " NEW_IP
    NEW_IP=${NEW_IP:-$PUBLIC_IP}
    read -p "输入新的【公网端口】 (回车保持 ${OUT_PORT}): " NEW_OUT
    NEW_OUT=${NEW_OUT:-$OUT_PORT}

    cat > $CONFIG_FILE <<EOT
secret = "${SECRET}"
bind-to = "0.0.0.0:${NEW_IN}"
EOT
    
    TG_LINK="tg://proxy?server=${NEW_IP}&port=${NEW_OUT}&secret=${SECRET}"
    echo "IN_PORT=${NEW_IN}" > $INFO_FILE
    echo "PUBLIC_IP=${NEW_IP}" >> $INFO_FILE
    echo "OUT_PORT=${NEW_OUT}" >> $INFO_FILE
    echo "SECRET=${SECRET}" >> $INFO_FILE
    echo "TG_LINK=${TG_LINK}" >> $INFO_FILE
    
    if command -v systemctl >/dev/null 2>&1; then
        systemctl restart mtg
    else
        pkill -f "mtg run"
        nohup /usr/local/bin/mtg run /etc/mtg.toml > /var/log/mtg.log 2>&1 &
    fi
    
    echo -e "${GREEN}✅ 配置已更新并重启服务！${RESET}"
    read -p "按回车键返回主菜单..."
}

uninstall_mtp() {
    clear
    echo -e "${RED}正在卸载 MTProxy...${RESET}"
    if command -v systemctl >/dev/null 2>&1; then
        systemctl stop mtg >/dev/null 2>&1
        systemctl disable mtg >/dev/null 2>&1
        rm -f /etc/systemd/system/mtg.service
        systemctl daemon-reload
    else
        pkill -f "mtg run"
        crontab -l 2>/dev/null | grep -v "mtg run" | crontab -
    fi
    rm -f /usr/local/bin/mtg $CONFIG_FILE $INFO_FILE /usr/local/bin/nm
    echo -e "${GREEN}✅ 卸载干净啦！${RESET}"
    read -p "按回车键返回主菜单..."
}

# 自动注入快捷指令 nm
if [ ! -f "/usr/local/bin/nm" ]; then
    # 注意：下面这里的链接替换成你 GitHub 上真实的 raw 链接
    curl -fsSL "https://raw.githubusercontent.com/lijboys/NAT-MTP/main/nm.sh" -o /usr/local/bin/nm
    chmod +x /usr/local/bin/nm
fi

# 主菜单循环
while true; do
    clear
    echo -e "${CYAN}=========================================${RESET}"
    echo -e "     🦇 NAT 专属 mtg v2 管理面板 🦇"
    echo -e "${CYAN}=========================================${RESET}"
    echo -e "当前状态: $(get_status)"
    echo -e "快捷指令: ${GREEN}nm${RESET}"
    echo -e "${CYAN}-----------------------------------------${RESET}"
    echo -e "  ${GREEN}1.${RESET} 安装 / 重装 MTP (带完美伪装)"
    echo -e "  ${GREEN}2.${RESET} 查看当前 TG 链接与信息"
    echo -e "  ${GREEN}3.${RESET} 修改端口与 IP (面板映射变更时使用)"
    echo -e "  ${YELLOW}4.${RESET} 启动 MTP 服务"
    echo -e "  ${YELLOW}5.${RESET} 停止 MTP 服务"
    echo -e "  ${RED}6.${RESET} 彻底卸载 MTP"
    echo -e "  ${GREEN}0.${RESET} 退出面板"
    echo -e "${CYAN}=========================================${RESET}"
    read -p "请输入序号选择功能: " choice
    
    case $choice in
        1) install_mtp ;;
        2) view_link ;;
        3) modify_config ;;
        4) 
            if command -v systemctl >/dev/null 2>&1; then systemctl start mtg; else nohup /usr/local/bin/mtg run /etc/mtg.toml > /var/log/mtg.log 2>&1 & fi
            echo -e "${GREEN}已启动！${RESET}"; sleep 1 
            ;;
        5) 
            if command -v systemctl >/dev/null 2>&1; then systemctl stop mtg; else pkill -f "mtg run"; fi
            echo -e "${RED}已停止！${RESET}"; sleep 1 
            ;;
        6) uninstall_mtp ;;
        0) clear; exit 0 ;;
        *) echo -e "${RED}输入错误，请输入 0-6 之间的数字！${RESET}"; sleep 2 ;;
    esac
done
