#!/bin/bash

# =========================================================
#  SSHTools - Komari 专用运维脚本 (lijboys 版)
#  GitHub: https://github.com/lijboys/SSHTools
# =========================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PLAIN='\033[0m'

if [ "$EUID" -ne 0 ]; then echo -e "${RED}Error: Please run as root!${PLAIN}"; exit 1; fi

# ================= 自动创建快捷键 =================
if [ ! -f "/usr/local/bin/komari" ]; then
    curl -fsSL "https://raw.githubusercontent.com/lijboys/SSHTools/main/komari.sh" -o /usr/local/bin/komari 2>/dev/null || cp -f "$0" /usr/local/bin/komari
    chmod +x /usr/local/bin/komari
fi
# ==================================================

# 状态检测
check_install() {
    if [ -f "/opt/komari/komari" ]; then
        STATUS="${GREEN}已安装${PLAIN}"
    else
        STATUS="${RED}未安装${PLAIN}"
    fi
}

draw_menu() {
    check_install
    clear
    echo -e "${BLUE}=======================================${PLAIN}"
    echo -e "        📊 Komari 探针管理面板"
    echo -e "${BLUE}=======================================${PLAIN}"
    echo -e "当前状态: komari $STATUS"
    echo -e "快捷指令: ${GREEN}komari${PLAIN}"
    echo -e "官方介绍：https://github.com/komari-monitor/komari"
    echo -e "${BLUE}---------------------------------------${PLAIN}"
    echo -e "  ${GREEN}1.${PLAIN} 安装                        ${GREEN}2.${PLAIN} 更新"
    echo -e "  ${RED}3.${PLAIN} 卸载                        ${YELLOW}4.${PLAIN} 查看初始凭据"
    echo -e "${BLUE}---------------------------------------${PLAIN}"
    echo -e "  ${GREEN}5.${PLAIN} 添加域名访问 (含SSL/CF回源)   ${RED}6.${PLAIN} 删除域名访问"
    echo -e "  ${GREEN}7.${PLAIN} 允许 IP+端口 访问             ${RED}8.${PLAIN} 阻止 IP+端口 访问"
    echo -e "${BLUE}---------------------------------------${PLAIN}"
    echo -e "  ${YELLOW}00.${PLAIN} 返回主菜单 (SSHTools)       ${GREEN}0.${PLAIN} 退出脚本"
    echo -e "${BLUE}=======================================${PLAIN}"
    echo -n " 请输入你的选择: "
}

# 1. 安装并自动显示密码
install_komari() {
    apt update && apt install -y curl wget sed socat nginx-light iptables
    echo -e "${YELLOW}正在拉取官方程序...${PLAIN}"
    curl -fsSL https://raw.githubusercontent.com/komari-monitor/komari/main/install-komari.sh | bash -s -- 1
    
    echo -e "${GREEN}安装完成！正在为你提取初始账号信息...${PLAIN}"
    sleep 3
    echo -e "${BLUE}=======================================${PLAIN}"
    journalctl -u komari -n 200 | grep -E "Username:|Password:" || echo "密码获取稍有延迟，请稍后使用选项 4 查看。"
    echo -e "${BLUE}=======================================${PLAIN}"
    read -p "按回车返回菜单..."
}

# 5. 添加域名访问 (补全了普通SSL逻辑)
add_domain() {
    read -p "请输入域名: " domain
    read -p "请输入内网端口 (默认 25774): " port
    port=${port:-25774}
    
    echo -e "选择模式: 1) 普通域名+自动SSL/手动SSL  2) Cloudflare 回源模式 (由CF提供SSL)"
    read -p "请选择 [1/2]: " cf_mode

    if [ "$cf_mode" == "2" ]; then
        # CF回源模式：Nginx只监听80，由CF走小黄云转发
        cat > /etc/nginx/sites-available/${domain} <<EOF
server {
    listen 80;
    server_name ${domain};
    location / {
        proxy_pass http://127.0.0.1:${port};
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
        echo -e "${GREEN}CF回源配置完成！请在 CF 网页版开启小黄云，并设置 Origin Rule 指向 80 端口或映射端口。${PLAIN}"
    else
        # 普通SSL模式：自动申请或手动上传
        cat > /etc/nginx/sites-available/${domain} <<EOF
server {
    listen 80;
    server_name ${domain};
    location / {
        proxy_pass http://127.0.0.1:${port};
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
        ln -sf /etc/nginx/sites-available/${domain} /etc/nginx/sites-enabled/
        systemctl restart nginx

        echo -e "${YELLOW}请选择 SSL 配置方式：${PLAIN}"
        echo -e " 1) 自动申请 (ACME.sh)"
        echo -e " 2) 手动上传 (.crt / .key)"
        read -p "请选择 [1/2]: " ssl_mode

        if [ "$ssl_mode" == "1" ]; then
            if [ ! -f "$HOME/.acme.sh/acme.sh" ]; then
                curl https://get.acme.sh | sh
            fi
            ~/.acme.sh/acme.sh --issue -d ${domain} --webroot /var/www/html --server letsencrypt
            mkdir -p /etc/nginx/ssl
            ~/.acme.sh/acme.sh --install-cert -d ${domain} --key-file /etc/nginx/ssl/${domain}.key --fullchain-file /etc/nginx/ssl/${domain}.crt
        else
            mkdir -p /etc/nginx/ssl
            echo -e "${YELLOW}请确保已将证书传至服务器${PLAIN}"
            read -p "证书(.crt/.pem)完整路径: " c_p
            read -p "私钥(.key)完整路径: " k_p
            cp "$c_p" "/etc/nginx/ssl/${domain}.crt" 2>/dev/null
            cp "$k_p" "/etc/nginx/ssl/${domain}.key" 2>/dev/null
        fi

        # 写入完整的 HTTPS Nginx 配置
        cat > /etc/nginx/sites-available/${domain} <<EOF
server {
    listen 80;
    server_name ${domain};
    return 301 https://\$host\$request_uri;
}
server {
    listen 443 ssl;
    server_name ${domain};
    ssl_certificate /etc/nginx/ssl/${domain}.crt;
    ssl_certificate_key /etc/nginx/ssl/${domain}.key;
    location / {
        proxy_pass http://127.0.0.1:${port};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
        echo -e "${GREEN}普通 SSL 模式配置完成！${PLAIN}"
    fi

    # 统一激活 Nginx 配置
    ln -sf /etc/nginx/sites-available/${domain} /etc/nginx/sites-enabled/
    systemctl restart nginx
    read -p "处理完成，按回车返回..."
}

# 7 & 8 防火墙开关 (优化了插入优先级)
manage_firewall() {
    local action=$1
    local port=25774
    if [ "$action" == "allow" ]; then
        iptables -D INPUT -p tcp --dport $port -j DROP 2>/dev/null
        iptables -I INPUT -p tcp --dport $port -j ACCEPT
        echo -e "${GREEN}已开启 IP+端口 ($port) 访问权限。${PLAIN}"
    else
        iptables -D INPUT -p tcp --dport $port -j ACCEPT 2>/dev/null
        # 使用 -I INPUT 1 强制置顶拦截规则
        iptables -I INPUT 1 -p tcp --dport $port -j DROP
        echo -e "${RED}已阻止直接通过 IP+端口 访问。${PLAIN}"
    fi
    read -p "按回车返回..."
}

# 脚本入口
while true; do
    draw_menu
    read choice
    case $choice in
        1) install_komari ;;
        2) curl -fsSL https://raw.githubusercontent.com/komari-monitor/komari/main/install-komari.sh | bash -s -- 2
           read -p "更新完成，回车继续..." ;;
        3) # 彻底卸载
           systemctl stop komari
           systemctl disable komari 2>/dev/null
           rm -rf /opt/komari
           rm -f /etc/systemd/system/komari.service
           systemctl daemon-reload
           echo -e "${GREEN}卸载彻底完成${PLAIN}" ; sleep 2 ;;
        4) journalctl -u komari -n 200 | grep -E "Username:|Password:"
           read -p "回车继续..." ;;
        5) add_domain ;;
        6) ls /etc/nginx/sites-available/
           read -p "输入要删除的域名: " d
           if [ -n "$d" ]; then
               rm -f /etc/nginx/sites-available/$d /etc/nginx/sites-enabled/$d /etc/nginx/ssl/$d.*
               systemctl restart nginx
               echo -e "${GREEN}已删除域名 $d 的所有配置。${PLAIN}"
           fi
           read -p "按回车返回..." ;;
        7) manage_firewall "allow" ;;
        8) manage_firewall "deny" ;;
        00)
           if [ -f "/usr/local/bin/n" ]; then
               exec /usr/local/bin/n
           else
               echo -e "${RED}未安装主菜单环境！${PLAIN}"
               sleep 2
           fi
           ;;
        0) clear; exit 0 ;;
        *) echo -e "${RED}输入错误，请重新选择！${PLAIN}"; sleep 1 ;;
    esac
done
