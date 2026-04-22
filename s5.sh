cat > /usr/local/bin/s5 <<'EOF'
#!/bin/bash

GREEN="\033[32m"
RED="\033[31m"
YELLOW="\033[33m"
CYAN="\033[36m"
RESET="\033[0m"

SCRIPT_VERSION="v1.0.1"

CONF_FILE="/etc/danted.conf"
INFO_FILE="/etc/s5_info.txt"
SERVICE_NAME="danted"
SCRIPT_URL="https://raw.githubusercontent.com/lijboys/SSHTools/main/s5.sh"

pause() { read -p "按回车返回..." ; }

is_valid_port() {
  [[ "$1" =~ ^[0-9]+$ ]] && [ "$1" -ge 1 ] && [ "$1" -le 65535 ]
}

get_public_ip() {
  local ip
  ip=$(curl -s4m3 --connect-timeout 3 ipv4.icanhazip.com 2>/dev/null)
  [ -z "$ip" ] && ip=$(curl -s4m3 --connect-timeout 3 api.ipify.org 2>/dev/null)
  [ -z "$ip" ] && ip=$(curl -s4m3 --connect-timeout 3 ifconfig.me 2>/dev/null)
  echo "$ip"
}

detect_iface() {
  ip route | awk '/default/ {print $5; exit}'
}

install_deps() {
  if command -v apt >/dev/null 2>&1; then
    apt update -y && apt install -y dante-server
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y dante-server
  elif command -v yum >/dev/null 2>&1; then
    yum install -y dante-server
  else
    echo -e "${RED}❌ 不支持的系统包管理器${RESET}"
    return 1
  fi
}

write_conf() {
  local iface="$1" port="$2" user="$3"

  cat > "$CONF_FILE" <<EOT
logoutput: /var/log/danted.log
internal: 0.0.0.0 port = ${port}
external: ${iface}

socksmethod: username
user.privileged: root
user.unprivileged: nobody

client pass {
  from: 0.0.0.0/0 to: 0.0.0.0/0
  log: connect error
}

client block {
  from: 0.0.0.0/0 to: 0.0.0.0/0
  log: error
}

socks pass {
  from: 0.0.0.0/0 to: 0.0.0.0/0
  command: bind connect udpassociate
  socksmethod: username
  log: connect error
}

socks block {
  from: 0.0.0.0/0 to: 0.0.0.0/0
  log: error
}
EOT
}

save_info() {
  local ip="$1" port="$2" user="$3" pass="$4"
  local socks5_link="socks5://${user}:${pass}@${ip}:${port}"
  local tg_link="tg://socks?server=${ip}&port=${port}&user=${user}&pass=${pass}"
  
  cat > "$INFO_FILE" <<EOT
IP="${ip}"
PORT="${port}"
USER="${user}"
PASS="${pass}"
SOCKS5_LINK="${socks5_link}"
TG_LINK="${tg_link}"
EOT
}

read_info() {
  grep "^$1=" "$INFO_FILE" 2>/dev/null | head -n1 | cut -d'"' -f2
}

start_service() {
  systemctl enable ${SERVICE_NAME} >/dev/null 2>&1
  systemctl restart ${SERVICE_NAME}
  sleep 1
  systemctl is-active --quiet ${SERVICE_NAME}
}

install_s5() {
  clear
  echo -e "${CYAN}====== SOCKS5 部署 (Dante) ======${RESET}"

  install_deps || { pause; return; }

  local iface ip port user pass
  iface=$(detect_iface)
  ip=$(get_public_ip)

  [ -z "$iface" ] && iface="eth0"
  [ -z "$ip" ] && ip="你的公网IP"

  read -p "请输入监听端口(默认1080): " port
  port=${port:-1080}
  if ! is_valid_port "$port"; then
    echo -e "${RED}❌ 端口无效${RESET}"; pause; return
  fi

  read -p "请输入用户名(默认s5user): " user
  user=${user:-s5user}

  read -p "请输入密码(默认随机8位): " pass
  [ -z "$pass" ] && pass=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 8)

  if id "$user" >/dev/null 2>&1; then
    echo "$user:$pass" | chpasswd
  else
    useradd -M -s /usr/sbin/nologin "$user"
    echo "$user:$pass" | chpasswd
  fi

  write_conf "$iface" "$port" "$user"

  if start_service; then
    save_info "$ip" "$port" "$user" "$pass"
    echo -e "${GREEN}✅ SOCKS5 部署成功${RESET}"
    echo -e "地址: ${YELLOW}${ip}${RESET}"
    echo -e "端口: ${YELLOW}${port}${RESET}"
    echo -e "账号: ${YELLOW}${user}${RESET}"
    echo -e "密码: ${YELLOW}${pass}${RESET}"
    echo -e "\n${CYAN}📱 TG 代理链接：${RESET}"
    echo -e "${GREEN}$(read_info TG_LINK)${RESET}"
    echo -e "\n${CYAN}🔗 SOCKS5 链接：${RESET}"
    echo -e "${YELLOW}$(read_info SOCKS5_LINK)${RESET}"
  else
    echo -e "${RED}❌ 服务启动失败，请查看日志${RESET}"
  fi
  pause
}

view_info() {
  clear
  if [ ! -f "$INFO_FILE" ]; then
    echo -e "${RED}未找到信息，请先安装${RESET}"
    pause; return
  fi
  echo -e "${CYAN}====== SOCKS5 信息 ======${RESET}"
  echo -e "状态: $(systemctl is-active ${SERVICE_NAME} 2>/dev/null)"
  echo -e "IP:   ${GREEN}$(read_info IP)${RESET}"
  echo -e "端口: ${GREEN}$(read_info PORT)${RESET}"
  echo -e "账号: ${GREEN}$(read_info USER)${RESET}"
  echo -e "密码: ${GREEN}$(read_info PASS)${RESET}"
  echo -e "\n${CYAN}📱 TG 代理链接：${RESET}"
  echo -e "${GREEN}$(read_info TG_LINK)${RESET}"
  echo -e "\n${CYAN}🔗 SOCKS5 链接：${RESET}"
  echo -e "${YELLOW}$(read_info SOCKS5_LINK)${RESET}"
  pause
}

modify_s5() {
  clear
  if [ ! -f "$INFO_FILE" ]; then
    echo -e "${RED}请先安装${RESET}"
    pause; return
  fi

  local old_port old_user old_pass ip iface port user pass
  old_port=$(read_info PORT)
  old_user=$(read_info USER)
  old_pass=$(read_info PASS)
  ip=$(read_info IP)
  iface=$(detect_iface)

  read -p "新端口(回车保持 ${old_port}): " port
  port=${port:-$old_port}
  if ! is_valid_port "$port"; then
    echo -e "${RED}❌ 端口无效${RESET}"; pause; return
  fi

  read -p "新用户名(回车保持 ${old_user}): " user
  user=${user:-$old_user}

  read -p "新密码(回车保持原密码): " pass
  pass=${pass:-$old_pass}

  if [ "$user" != "$old_user" ]; then
    id "$old_user" >/dev/null 2>&1 && userdel "$old_user" 2>/dev/null
    if id "$user" >/dev/null 2>&1; then
      echo "$user:$pass" | chpasswd
    else
      useradd -M -s /usr/sbin/nologin "$user"
      echo "$user:$pass" | chpasswd
    fi
  else
    echo "$user:$pass" | chpasswd
  fi

  write_conf "$iface" "$port" "$user"

  if start_service; then
    save_info "$ip" "$port" "$user" "$pass"
    echo -e "${GREEN}✅ 修改完成${RESET}"
    echo -e "\n${CYAN}📱 TG 代理链接：${RESET}"
    echo -e "${GREEN}$(read_info TG_LINK)${RESET}"
    echo -e "\n${CYAN}🔗 SOCKS5 链接：${RESET}"
    echo -e "${YELLOW}$(read_info SOCKS5_LINK)${RESET}"
  else
    echo -e "${RED}❌ 重启失败，请查看日志${RESET}"
  fi
  pause
}

service_ctl() {
  local action="$1"
  systemctl ${action} ${SERVICE_NAME}
  sleep 1
  echo -e "当前状态: $(systemctl is-active ${SERVICE_NAME} 2>/dev/null)"
  pause
}

view_logs() {
  clear
  echo -e "${CYAN}====== 最近日志 ======${RESET}"
  journalctl -u ${SERVICE_NAME} --no-pager -n 50 2>/dev/null || tail -n 50 /var/log/danted.log 2>/dev/null
  pause
}

uninstall_s5() {
  clear
  read -p "确认卸载 SOCKS5 吗？[y/N]: " c
  [[ "$c" != "y" && "$c" != "Y" ]] && return

  systemctl stop ${SERVICE_NAME} >/dev/null 2>&1
  systemctl disable ${SERVICE_NAME} >/dev/null 2>&1

  if command -v apt >/dev/null 2>&1; then
    apt remove -y dante-server >/dev/null 2>&1
  elif command -v dnf >/dev/null 2>&1; then
    dnf remove -y dante-server >/dev/null 2>&1
  elif command -v yum >/dev/null 2>&1; then
    yum remove -y dante-server >/dev/null 2>&1
  fi

  rm -f "$CONF_FILE" "$INFO_FILE" /var/log/danted.log /usr/local/bin/s5
  echo -e "${GREEN}✅ 已卸载${RESET}"
  pause
}

update_script() {
  clear
  echo -e "${YELLOW}正在从 GitHub 拉取最新脚本...${RESET}"
  local tmp_file
  tmp_file=$(mktemp)
  if curl -fsSL --connect-timeout 10 "${SCRIPT_URL}" -o "$tmp_file" 2>/dev/null; then
    sed -i 's/\r$//' "$tmp_file"
    if bash -n "$tmp_file" 2>/dev/null; then
      mv "$tmp_file" /usr/local/bin/s5
      chmod +x /usr/local/bin/s5
      echo -e "${GREEN}✅ 脚本更新完成！请重新输入 s5 启动最新版。${RESET}"
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

if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}请使用 root 运行${RESET}"
  exit 1
fi

while true; do
  clear
  echo -e "${CYAN}====================================${RESET}"
  echo -e "   SOCKS5 管理面板 ${GREEN}${SCRIPT_VERSION}${RESET}"
  echo -e "${CYAN}====================================${RESET}"
  echo -e "  ${GREEN}1.${RESET} 安装 / 重装 SOCKS5"
  echo -e "  ${GREEN}2.${RESET} 查看连接信息"
  echo -e "  ${GREEN}3.${RESET} 修改端口/账号密码"
  echo -e "  ${YELLOW}4.${RESET} 启动服务"
  echo -e "  ${YELLOW}5.${RESET} 停止服务"
  echo -e "  ${CYAN}6.${RESET} 重启服务"
  echo -e "  ${CYAN}7.${RESET} 查看日志"
  echo -e "  ${BLUE}8.${RESET} 更新脚本 (从 GitHub 同步)"
  echo -e "  ${RED}9.${RESET} 卸载 SOCKS5"
  echo -e "  ${GREEN}0.${RESET} 退出"
  echo -e "${CYAN}====================================${RESET}"
  read -p "请输入选择: " c

  case "$c" in
    1) install_s5 ;;
    2) view_info ;;
    3) modify_s5 ;;
    4) service_ctl start ;;
    5) service_ctl stop ;;
    6) service_ctl restart ;;
    7) view_logs ;;
    8) update_script ;;
    9) uninstall_s5 ;;
    0) clear; exit 0 ;;
    *) echo -e "${RED}输入错误${RESET}"; sleep 1 ;;
  esac
done
EOF

chmod +x /usr/local/bin/s5
