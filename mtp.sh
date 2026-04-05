#!/bin/bash

GREEN="\033[32m"
RED="\033[31m"
YELLOW="\033[33m"
CYAN="\033[36m"
RESET="\033[0m"

CONFIG_FILE="/etc/mtg.toml"
INFO_FILE="/etc/mtg_info.txt"

# 你的真实 GitHub Raw 链接
SCRIPT_URL="https://raw.githubusercontent.com/lijboys/SSHTools/main/mtp.sh"

if [ "$EUID" -ne 0 ]; then echo -e "${RED}请使用 root 用户运行！${RESET}"; exit 1; fi

get_status() {
    if command -v systemctl >/dev/null 2>&1; then
        if systemctl is-active --quiet mtg; then echo -e "${GREEN}运行中 (systemd)${RESET}"; else echo -e "${RED}已停止${RESET}"; fi
    else
        if pgrep -f "mtg run" > /dev/null; then echo -e "${GREEN}运行中 (nohup)${RESET}"; else echo -e "${RED}已停止${RESET}"; fi
    fi
}

choose_and_generate_secret() {
    echo ""
    echo -e "${CYAN}--- 请选择 FakeTLS 伪装域名 (藏木于林) ---${RESET}"
    echo -e "  ${GREEN}1.${RESET} cn.bing.com          ${GREEN}2.${RESET} itunes.apple.com"
    echo -e "  ${GREEN}3.${RESET} www.cloudflare.com   ${GREEN}4.${RESET} gateway.icloud.com"
    echo -e "  ${GREEN}5.${RESET} aws.amazon.com       ${GREEN}6.${RESET} cdn.jsdelivr.net"
    echo -e "  ${GREEN}7.${RESET} www.wechat.com       ${GREEN}8.${RESET} update.microsoft.com"
    echo -e "  ${YELLOW}9.${RESET} 自定义伪装域名 (无懈可击：推荐填你自己的域名)"
    echo -e "${CYAN}-----------------------------------------${RESET}"
    read -p "请输入序号选择 (回车默认选 1): " domain_choice
    
    case $domain_choice in
        2) FAKE_DOMAIN="itunes.apple.com" ;;
        3) FAKE_DOMAIN="www.cloudflare.com" ;;
        4) FAKE_DOMAIN="gateway.icloud.com" ;;
        5) FAKE_DOMAIN="aws.amazon.com" ;;
        6) FAKE_DOMAIN="cdn.jsdelivr.net" ;;
        7) FAKE_DOMAIN="www.wechat.com" ;;
        8) FAKE_DOMAIN="update.microsoft.com" ;;
        9) 
            read -p "👉 请输入自定义【FakeTLS 伪装域名】: " FAKE_DOMAIN
            FAKE_DOMAIN=${FAKE_DOMAIN:-cn.bing.com}
            ;;
        *) FAKE_DOMAIN="cn.bing.com" ;;
    esac
    
    echo -e "${YELLOW}正在调用核心动态生成专属伪装密钥...${RESET}"
    SECRET=$(/usr/local/bin/mtg generate-secret "${FAKE_DOMAIN}")
    echo -e "✅ 已设置伪装域名: ${GREEN}${FAKE_DOMAIN}${RESET}"
}

# 强化的公网 IP 检测函数
get_public_ip() {
    local temp_ip
    # 尝试多个可靠的 API，超时设为 3 秒，防止卡死
    temp_ip=$(curl -s4m3 ipv4.icanhazip.com 2>/dev/null || curl -s4m3 api.ipify.org 2>/dev/null || curl -s4m3 ifconfig.me 2>/dev/null)
    # 如果抓到的是有效 IP 格式，则返回，否则返回空
    if [[ "$temp_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "$temp_ip"
    else
        echo ""
    fi
}

install_mtp() {
    clear
    echo -e "${CYAN}=========================================${RESET}"
    echo -e "${CYAN}  🚀 开始部署 mtg v2 伪装代理${RESET}"
    echo -e "${CYAN}=========================================${RESET}"
    
    if command -v systemctl >/dev/null 2>&1; then systemctl stop mtg 2>/dev/null; fi
    pkill -f "mtg run" 2>/dev/null
    
    echo -e "${YELLOW}正在直连拉取官方 mtg v2 核心...${RESET}"
    wget -qO mtg.tar.gz https://github.com/9seconds/mtg/releases/download/v2.1.7/mtg-2.1.7-linux-amd64.tar.gz
    tar -zxf mtg.tar.gz
    mv mtg-2.1.7-linux-amd64/mtg /usr/local/bin/mtg
    chmod +x /usr/local/bin/mtg
    rm -rf mtg.tar.gz mtg-2.1.7-linux-amd64
    
    AUTO_IP=$(get_public_ip)
    # 如果没获取到，给个明确的提示词
    DISPLAY_IP=${AUTO_IP:-"获取失败,请手动输入!"}
    
    echo ""
    echo -e "${CYAN}--- 请选择你的机器网络环境 ---${RESET}"
    echo -e "  ${GREEN}1.${RESET} NAT 小鸡 (仅开放部分映射端口) [默认]"
    echo -e "  ${YELLOW}2.${RESET} 独立 VPS (拥有独立公网 IP，全端口开放)"
    read -p "请输入序号 (回车默认选 1): " net_choice
    
    echo ""
    if [ -z "$net_choice" ] || [ "$net_choice" == "1" ]; then
        echo -e "${YELLOW}💡 提示: 大部分 NAT 支持自定义映射端口，不支持的请手动输入。${RESET}"
        read -p "👉 1. 请输入【公网/外网可用端口】(回车默认 10086): " OUT_PORT
        OUT_PORT=${OUT_PORT:-10086}
        
        read -p "👉 2. 请输入小鸡【内网监听端口】(回车默认与外网一致: $OUT_PORT): " IN_PORT
        IN_PORT=${IN_PORT:-$OUT_PORT}
        
        # 强提醒：如果识别错误，一定要在这里手动输入！
        read -p "👉 3. 请输入商家【公网 IPv4 地址】(识别出: $DISPLAY_IP): " PUBLIC_IP
        PUBLIC_IP=${PUBLIC_IP:-$AUTO_IP}
        
        # 终极防呆：如果用户没输入，而且自动获取也失败了，拦住他不让继续
        if [ -z "$PUBLIC_IP" ]; then
            echo -e "${RED}错误：必须拥有公网 IP 才能生成有效链接！请重新运行并手动输入。${RESET}"
            exit 1
        fi
        
        echo -e "   ${GREEN}✅ NAT 节点配置完成 -> IP: ${PUBLIC_IP} | 内网端口: ${IN_PORT} | 外网端口: ${OUT_PORT}${RESET}"

    elif [ "$net_choice" == "2" ]; then
        echo -e "${YELLOW}💡 提示: 独立 VPS 推荐使用 443 端口(最隐蔽)，但如果你机器上装了建站面板(占用443)，请换一个别的端口。${RESET}"
        read -p "👉 请输入你想使用的端口 (回车默认 443): " IN_PORT
        IN_PORT=${IN_PORT:-443}
        OUT_PORT=$IN_PORT
        
        read -p "👉 请确认【公网 IPv4 地址】(识别出: $DISPLAY_IP，如果不对请手动输入): " PUBLIC_IP
        PUBLIC_IP=${PUBLIC_IP:-$AUTO_IP}
        
        if [ -z "$PUBLIC_IP" ]; then
            echo -e "${RED}错误：无法获取公网 IP！请重新运行并手动输入。${RESET}"
            exit 1
        fi
        
        echo -e "   ${GREEN}✅ VPS 节点配置完成 -> IP: ${PUBLIC_IP} | 端口: ${IN_PORT}${RESET}"
    else
        echo -e "${RED}输入错误，请输入 1 或 2！${RESET}"
        exit 1
    fi
    
    choose_and_generate_secret
    
    cat > $CONFIG_FILE <<EOT
secret = "${SECRET}"
bind-to = "0.0.0.0:${IN_PORT}"
EOT

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
        nohup /usr/local/bin/mtg run /etc/mtg.toml > /var/log/mtg.log 2>&1 &
        (crontab -l 2>/dev/null | grep -v "mtg run"; echo "@reboot nohup /usr/local/bin/mtg run /etc/mtg.toml > /var/log/mtg.log 2>&1 &") | crontab -
    fi
    
    TG_LINK="tg://proxy?server=${PUBLIC_IP}&port=${OUT_PORT}&secret=${SECRET}"
    echo "IN_PORT=${IN_PORT}" > $INFO_FILE
    echo "PUBLIC_IP=${PUBLIC_IP}" >> $INFO_FILE
    echo "OUT_PORT=${OUT_PORT}" >> $INFO_FILE
    echo "FAKE_DOMAIN=${FAKE_DOMAIN}" >> $INFO_FILE
    echo "SECRET=${SECRET}" >> $INFO_FILE
    echo "TG_LINK=${TG_LINK}" >> $INFO_FILE
    
    echo -e "\n${GREEN}✅ 部署成功！程序已在后台监听端口 ${IN_PORT}${RESET}"
    echo -e "你的专属 TG 链接是：\n${YELLOW}${TG_LINK}${RESET}\n"
    read -p "按回车键返回主菜单..."
}

view_link() {
    clear
    echo -e "${CYAN}=========================================${RESET}"
    if [ -f "$INFO_FILE" ]; then
        source $INFO_FILE
        echo -e "当前内网监听端口: ${GREEN}${IN_PORT}${RESET}"
        echo -e "当前对外公网地址: ${GREEN}${PUBLIC_IP}:${OUT_PORT}${RESET}"
        echo -e "当前伪装域名:     ${GREEN}${FAKE_DOMAIN}${RESET}\n"
        echo -e "${YELLOW}👉 TG 一键直连链接：${RESET}"
        echo -e "${GREEN}${TG_LINK}${RESET}"
    else
        echo -e "${RED}未找到配置，请先安装！${RESET}"
    fi
    echo -e "${CYAN}=========================================${RESET}"
    read -p "按回车键返回主菜单..."
}

modify_config() {
    clear
    if [ ! -f "$INFO_FILE" ]; then echo -e "${RED}请先安装！${RESET}"; read -p "按回车返回..."; return; fi
    source $INFO_FILE
    
    AUTO_IP=$(get_public_ip)
    DISPLAY_IP=${AUTO_IP:-"获取失败"}
    
    echo -e "${CYAN}--- 修改映射与配置信息 ---${RESET}"
    read -p "输入新【内网监听端口】 (回车保持 ${IN_PORT}): " NEW_IN
    NEW_IN=${NEW_IN:-$IN_PORT}
    
    # 修改配置时同样提示现在的自动识别IP，防止NAT变动
    echo -e "${YELLOW}当前机器识别到的外部IP为: ${DISPLAY_IP}${RESET}"
    read -p "输入新【公网 IP】 (回车保持 ${PUBLIC_IP}): " NEW_IP
    NEW_IP=${NEW_IP:-$PUBLIC_IP}
    
    read -p "输入新【公网端口】 (回车保持 ${OUT_PORT}): " NEW_OUT
    NEW_OUT=${NEW_OUT:-$OUT_PORT}
    
    echo -e "当前伪装域名为: ${GREEN}${FAKE_DOMAIN}${RESET}"
    read -p "按 1 重新设置伪装域名，按回车键保持不变: " change_domain
    if [ "$change_domain" == "1" ]; then
        choose_and_generate_secret
    else
        SECRET=$SECRET
    fi

    cat > $CONFIG_FILE <<EOT
secret = "${SECRET}"
bind-to = "0.0.0.0:${NEW_IN}"
EOT
    
    TG_LINK="tg://proxy?server=${NEW_IP}&port=${NEW_OUT}&secret=${SECRET}"
    echo "IN_PORT=${NEW_IN}" > $INFO_FILE
    echo "PUBLIC_IP=${NEW_IP}" >> $INFO_FILE
    echo "OUT_PORT=${NEW_OUT}" >> $INFO_FILE
    echo "FAKE_DOMAIN=${FAKE_DOMAIN}" >> $INFO_FILE
    echo "SECRET=${SECRET}" >> $INFO_FILE
    echo "TG_LINK=${TG_LINK}" >> $INFO_FILE
    
    if command -v systemctl >/dev/null 2>&1; then
        systemctl restart mtg
    else
        pkill -f "mtg run"
        nohup /usr/local/bin/mtg run /etc/mtg.toml > /var/log/mtg.log 2>&1 &
    fi
    echo -e "${GREEN}✅ 配置已更新！${RESET}"; read -p "按回车键返回..."
}

uninstall_mtp() {
    clear
    echo -e "${RED}正在卸载...${RESET}"
    if command -v systemctl >/dev/null 2>&1; then
        systemctl stop mtg >/dev/null 2>&1; systemctl disable mtg >/dev/null 2>&1; rm -f /etc/systemd/system/mtg.service; systemctl daemon-reload
    else
        pkill -f "mtg run"; crontab -l 2>/dev/null | grep -v "mtg run" | crontab -
    fi
    rm -f /usr/local/bin/mtg $CONFIG_FILE $INFO_FILE /usr/local/bin/mtp
    echo -e "${GREEN}✅ 卸载干净啦！面板即将自动关闭...${RESET}"
    sleep 2; exit 0
}

update_script() {
    clear
    echo -e "${YELLOW}正在从 GitHub 拉取最新面板代码...${RESET}"
    curl -fsSL "${SCRIPT_URL}" -o /usr/local/bin/mtp
    chmod +x /usr/local/bin/mtp
    echo -e "${GREEN}✅ 面板更新完成！请重新输入 mtp 启动最新版。${RESET}"
    sleep 2; exit 0
}

if [ ! -f "/usr/local/bin/mtp" ]; then
    curl -fsSL "${SCRIPT_URL}" -o /usr/local/bin/mtp
    chmod +x /usr/local/bin/mtp
fi

while true; do
    clear
    echo -e "${CYAN}=========================================${RESET}"
    echo -e "    🦇 MTP 代理管理面板 (支持 VPS/NAT) 🦇"
    echo -e "${CYAN}=========================================${RESET}"
    echo -e "当前状态: $(get_status)"
    echo -e "快捷指令: ${GREEN}mtp${RESET}"
    echo -e "${CYAN}-----------------------------------------${RESET}"
    echo -e "  ${GREEN}1.${RESET} 安装 / 重装 MTP (自动适配网络环境)"
    echo -e "  ${GREEN}2.${RESET} 查看当前 TG 链接与信息"
    echo -e "  ${GREEN}3.${RESET} 修改端口、IP与伪装域名"
    echo -e "  ${YELLOW}4.${RESET} 启动 MTP 服务"
    echo -e "  ${YELLOW}5.${RESET} 停止 MTP 服务"
    echo -e "  ${RED}6.${RESET} 彻底卸载 MTP"
    echo -e "  ${CYAN}7.${RESET} 更新面板代码 (从 GitHub 同步)"
    echo -e "  ${GREEN}0.${RESET} 退出面板"
    echo -e "  ${YELLOW}00.${RESET} 返回主菜单 (NooMili)"
    echo -e "${CYAN}=========================================${RESET}"
    read -p "请输入序号选择功能: " choice
    
    case $choice in
        1) install_mtp ;; 
        2) view_link ;; 
        3) modify_config ;;
        4) if command -v systemctl >/dev/null 2>&1; then systemctl start mtg; else nohup /usr/local/bin/mtg run /etc/mtg.toml > /var/log/mtg.log 2>&1 & fi; echo -e "${GREEN}已启动！${RESET}"; sleep 1 ;;
        5) if command -v systemctl >/dev/null 2>&1; then systemctl stop mtg; else pkill -f "mtg run"; fi; echo -e "${RED}已停止！${RESET}"; sleep 1 ;;
        6) uninstall_mtp ;; 
        7) update_script ;; 
        0) clear; exit 0 ;;
        00) if [ -f "/usr/local/bin/n" ]; then exec /usr/local/bin/n; else echo -e "${RED}未安装主控！请先运行主控安装命令。${RESET}"; sleep 2; fi ;;
        *) echo -e "${RED}输入错误！${RESET}"; sleep 1 ;;
    esac
done
