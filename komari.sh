#!/bin/bash

# =========================================================
#  NooMili - Komari 专用运维脚本
#  GitHub: https://github.com/lijboys/SSHTools
# =========================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PLAIN='\033[0m'

if [ "$EUID" -ne 0 ]; then echo -e "${RED}Error: Please run as root!${PLAIN}"; exit 1; fi

# 强行回到主目录，防止目录报错
cd ~

# ================= 自动创建快捷键 =================
if [ ! -f "/usr/local/bin/komari" ]; then
    curl -fsSL "https://raw.githubusercontent.com/lijboys/SSHTools/main/komari.sh" -o /usr/local/bin/komari 2>/dev/null || cp -f "$0" /usr/local/bin/komari
    chmod +x /usr/local/bin/komari
fi
# ==================================================

# 缓存公网IP
if [ -z "$PUBLIC_IP" ]; then
    PUBLIC_IP=$(curl -s4m2 ifconfig.me || curl -s4m2 ipinfo.io/ip)
fi

get_current_port() {
    if [ -f "/opt/komari/.nat_port" ]; then
        cat /opt/komari/.nat_port
    else
        echo "25774"
    fi
}

check_install() {
    if [ -f "/opt/komari/komari" ]; then
        STATUS="${GREEN}已安装${PLAIN}"
    else
        STATUS="${RED}未安装${PLAIN}"
    fi
}

draw_menu() {
    check_install
    CURRENT_PORT=$(get_current_port)
    
    clear
    echo -e "${BLUE}=======================================${PLAIN}"
    echo -e "       📊 Komari 探针管理面板"
    echo -e "${BLUE}=======================================${PLAIN}"
    echo -e "当前状态: komari $STATUS"
    
    if [ -f "/opt/komari/komari" ]; then
        echo -e "公网访问端口: ${YELLOW}${CURRENT_PORT}${PLAIN}"
        echo -e "直连访问地址: ${CYAN}http://${PUBLIC_IP}:${CURRENT_PORT}${PLAIN} (IP直连，无需域名)"
        
        if [ -d "/etc/nginx/sites-enabled/" ]; then
            DOMAINS=$(ls -1 /etc/nginx/sites-enabled/ 2>/dev/null | grep -v "default" | grep -v "komari-nat" | tr '\n' ' ')
            if [ -n "$DOMAINS" ]; then
                echo -e "已绑定域名:   ${GREEN}${DOMAINS}${PLAIN}"
            fi
        fi
    fi
    
    echo -e "官方介绍：https://github.com/komari-monitor/komari"
    echo -e "${BLUE}---------------------------------------${PLAIN}"
    echo -e "  ${GREEN}1.${PLAIN} 安装                        ${GREEN}2.${PLAIN} 更新 (探针程序)"
    echo -e "  ${RED}3.${PLAIN} 彻底卸载                    ${YELLOW}4.${PLAIN} 查看初始凭据"
    echo -e "${BLUE}---------------------------------------${PLAIN}"
    echo -e "  ${GREEN}5.${PLAIN} 修改面板端口 ${YELLOW}(纯 IP直连，NAT改端口专用)${PLAIN}"
    echo -e "  ${GREEN}6.${PLAIN} 添加域名访问 ${YELLOW}(建站级，含防墙/SSL优化)${PLAIN}"
    echo -e "  ${RED}7.${PLAIN} 删除域名访问"
    echo -e "${BLUE}---------------------------------------${PLAIN}"
    echo -e "  ${CYAN}88.${PLAIN} 更新探针面板代码 (从 GitHub 同步)"
    echo -e "  ${YELLOW}9.${PLAIN} 返回主菜单 (NooMili)"
    echo -e "  ${GREEN}0.${PLAIN} 退出脚本"
    echo -e "${BLUE}=======================================${PLAIN}"
    echo -n " 请输入你的选择: "
}

show_credentials() {
    LOG_LINE=$(journalctl -u komari -n 200 | grep -E "Username:|Password:" | tail -n 1)
    if [ -n "$LOG_LINE" ]; then
        USERNAME=$(echo "$LOG_LINE" | sed -n 's/.*Username: \([^ ,]*\).*/\1/p')
        PASSWORD=$(echo "$LOG_LINE" | sed -n 's/.*Password: \([^ ]*\).*/\1/p')
        echo -e "👉 初始账号: ${GREEN}${USERNAME}${PLAIN}"
        echo -e "👉 初始密码: ${YELLOW}${PASSWORD}${PLAIN}"
    else
        echo -e "${YELLOW}日志中暂未找到账号信息，密码获取稍有延迟，请稍后使用选项 4 查看。${PLAIN}"
    fi
}

change_port() {
    echo -e "\n${CYAN}--- NAT 端口接驳向导 ---${PLAIN}"
    read -p "👉 请输入 NAT 商家分配给你的可用端口 (如 2201，直接回车则保持默认): " new_port
    if [ -z "$new_port" ]; then 
        echo -e "${YELLOW}已保留默认端口。${PLAIN}"
        return
    fi
    
    echo -e "${YELLOW}正在配置底层路由，接驳端口...${PLAIN}"
    cat > /etc/nginx/sites-available/komari-nat <<EOF
server {
    listen $new_port;
    server_name _;
    location / {
        proxy_pass http://127.0.0.1:25774;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
    }
}
EOF
    ln -sf /etc/nginx/sites-available/komari-nat /etc/nginx/sites-enabled/
    systemctl restart nginx
    
    iptables -I INPUT -p tcp --dport $new_port -j ACCEPT
    iptables -D INPUT -p tcp --dport 25774 -j ACCEPT 2>/dev/null
    iptables -A INPUT -p tcp --dport 25774 -j DROP
    
    echo "$new_port" > /opt/komari/.nat_port
    echo -e "${GREEN}✅ 端口映射成功！你可以直接使用 IP+端口 访问了。${PLAIN}"
}

install_komari() {
    apt update && apt install -y curl wget sed socat nginx-light iptables
    echo -e "${YELLOW}正在拉取官方程序...${PLAIN}"
    wget -qO /tmp/komari-install.sh https://raw.githubusercontent.com/komari-monitor/komari/main/install-komari.sh
    chmod +x /tmp/komari-install.sh
    echo "1" | bash /tmp/komari-install.sh
    rm -f /tmp/komari-install.sh
    
    echo "25774" > /opt/komari/.nat_port
    
    echo -e "\n${GREEN}=======================================${PLAIN}"
    echo -e "${GREEN}✅ 探针核心安装完成！正在提取初始账号信息...${PLAIN}"
    sleep 3
    show_credentials
    echo -e "${GREEN}=======================================${PLAIN}"
    
    echo -e "\n${YELLOW}💡 检测到你可能在使用 NAT 小鸡，默认端口 25774 无法直接访问。${PLAIN}"
    read -p "是否需要立即修改面板端口？[Y/n]: " need_port
    if [[ "$need_port" == "Y" || "$need_port" == "y" || "$need_port" == "" ]]; then
        change_port
        CURRENT_PORT=$(get_current_port)
        echo -e "\n${CYAN}🎉 全部配置完毕！现在请在浏览器打开：${PLAIN}"
        echo -e "${YELLOW}http://${PUBLIC_IP}:${CURRENT_PORT}${PLAIN}"
    fi
    
    echo ""
    read -p "按回车返回菜单..."
}

add_domain() {
    read -p "请输入域名: " domain
    
    echo -e "选择模式: 1) 普通域名+自动SSL  2) Cloudflare 回源模式 (由CF提供免费SSL)"
    read -p "请选择: " cf_mode

    if [ "$cf_mode" == "2" ]; then
        cat > /etc/nginx/sites-available/${domain} <<EOF
server {
    listen 80;
    server_name ${domain};
    location / {
        proxy_pass http://127.0.0.1:25774;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
        echo -e "${GREEN}CF回源配置完成！请去 CF 网页版面板开启小黄云，并确保 Origin Rule 指向你小鸡的 80 或映射端口。${PLAIN}"
    else
        echo -e "${YELLOW}正在配置 SSL...${PLAIN}"
    fi
    ln -sf /etc/nginx/sites-available/${domain} /etc/nginx/sites-enabled/
    systemctl restart nginx
    read -p "处理完成，按回车返回..."
}

update_panel() {
    clear
    echo -e "${YELLOW}正在从 GitHub 拉取最新探针面板代码...${PLAIN}"
    curl -fsSL "https://raw.githubusercontent.com/lijboys/SSHTools/main/komari.sh" -o /usr/local/bin/komari
    chmod +x /usr/local/bin/komari
    echo -e "${GREEN}✅ 探针面板更新完成！即将重启面板...${PLAIN}"
    sleep 2; exec /usr/local/bin/komari
}

# 脚本入口
while true; do
    draw_menu
    read choice
    case $choice in
        1) install_komari ;;
        2) 
           echo -e "${YELLOW}正在升级官方 Komari 探针核心...${PLAIN}"
           wget -qO /tmp/komari-install.sh https://raw.githubusercontent.com/komari-monitor/komari/main/install-komari.sh
           chmod +x /tmp/komari-install.sh
           echo "2" | bash /tmp/komari-install.sh
           rm -f /tmp/komari-install.sh
           read -p "升级完成，按回车返回..."
           ;;
        3) 
           clear
           echo -e "${RED}正在彻底卸载 Komari 探针及所有配置...${PLAIN}"
           wget -qO /tmp/komari-install.sh https://raw.githubusercontent.com/komari-monitor/komari/main/install-komari.sh
           chmod +x /tmp/komari-install.sh
           echo "3" | bash /tmp/komari-install.sh
           rm -f /tmp/komari-install.sh
           rm -f /etc/nginx/sites-enabled/komari-nat /etc/nginx/sites-available/komari-nat
           systemctl restart nginx 2>/dev/null
           rm -f /usr/local/bin/komari
           echo -e "${GREEN}✅ 彻底卸载成功！面板即将自动关闭...${PLAIN}"
           sleep 2; exit 0 
           ;;
        4) 
           echo -e "${BLUE}=======================================${PLAIN}"
           show_credentials
           echo -e "${BLUE}=======================================${PLAIN}"
           read -p "回车继续..." ;;
        5) change_port ;;
        6) add_domain ;;
        7) 
           ls -1 /etc/nginx/sites-available/ | grep -v "default" | grep -v "komari-nat"
           read -p "输入要删除的域名: " d
           rm -f /etc/nginx/sites-available/$d /etc/nginx/sites-enabled/$d
           systemctl restart nginx ;;
        88) update_panel ;;
        9) 
           if [ -f "/usr/local/bin/n" ]; then
               exec /usr/local/bin/n
           else
               echo -e "${RED}未安装主控！请先运行主控安装命令。${PLAIN}"
               sleep 2
           fi
           ;;
        0) clear; exit 0 ;;
        *) echo -e "${RED}输入错误，请重新选择！${PLAIN}"; sleep 1 ;;
    esac
done
