cat > /usr/local/bin/s5 <<'EOF'
#!/bin/sh

GREEN="\033[32m"
RED="\033[31m"
YELLOW="\033[33m"
CYAN="\033[36m"
BLUE="\033[34m"
RESET="\033[0m"

SCRIPT_VERSION="v1.5.0"
CONF_FILE="/etc/danted.conf"
INFO_FILE="/etc/s5_info.txt"
SERVICE_NAME="danted"
LOG_FILE="/var/log/danted.log"
SCRIPT_URL="https://raw.githubusercontent.com/lijboys/SSHTools/main/s5.sh"

GOST_BIN="/usr/local/bin/gost"
GOST_SERVICE="gost-s5"
GOST_PIDFILE="/run/gost-s5.pid"

pause() { printf "按回车键返回主菜单..."; read dummy; }

is_valid_port() {
  case "$1" in
    ''|*[!0-9]*) return 1 ;;
    *) [ "$1" -ge 1 ] && [ "$1" -le 65535 ] ;;
  esac
}

is_valid_ipv4() {
  ip="$1"
  echo "$ip" | grep -Eq '^([0-9]{1,3}\.){3}[0-9]{1,3}$' || return 1
  OLD_IFS="$IFS"
  IFS='.'
  set -- $ip
  IFS="$OLD_IFS"
  for o in "$1" "$2" "$3" "$4"; do
    case "$o" in ''|*[!0-9]*) return 1 ;; esac
    [ "$o" -ge 0 ] && [ "$o" -le 255 ] || return 1
  done
  return 0
}

is_valid_ipv6() {
  ip="$1"
  echo "$ip" | grep -q ":" || return 1
  echo "$ip" | grep -Eq '^[0-9a-fA-F:]+$' || return 1
  return 0
}

is_port_in_use() {
  ss -tln 2>/dev/null | awk '{print $4}' | grep -qE "[:.]$1$"
}

get_public_ip() {
  ip_type="${1:-4}"
  ip=""
  if [ "$ip_type" = "6" ]; then
    ip=$(curl -s6m3 --connect-timeout 3 ipv6.icanhazip.com 2>/dev/null)
    [ -z "$ip" ] && ip=$(curl -s6m3 --connect-timeout 3 api6.ipify.org 2>/dev/null)
    [ -z "$ip" ] && ip=$(curl -s6m3 --connect-timeout 3 ifconfig.co 2>/dev/null)
    is_valid_ipv6 "$ip" && echo "$ip" || echo ""
  else
    ip=$(curl -s4m3 --connect-timeout 3 ipv4.icanhazip.com 2>/dev/null)
    [ -z "$ip" ] && ip=$(curl -s4m3 --connect-timeout 3 api.ipify.org 2>/dev/null)
    [ -z "$ip" ] && ip=$(curl -s4m3 --connect-timeout 3 ifconfig.me 2>/dev/null)
    is_valid_ipv4 "$ip" && echo "$ip" || echo ""
  fi
}

detect_iface() {
  ip route 2>/dev/null | awk '/default/ {print $5; exit}'
}

has_systemd() {
  command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]
}

has_openrc() {
  command -v rc-service >/dev/null 2>&1
}

get_backend_type() {
  ip_type=$(read_info IP_TYPE)
  [ -z "$ip_type" ] && ip_type="4"
  if [ "$ip_type" = "6" ]; then
    echo "gost"
  else
    echo "dante"
  fi
}

get_status() {
  backend=$(get_backend_type)
  if [ "$backend" = "gost" ]; then
    if has_systemd; then
      systemctl is-active --quiet "${GOST_SERVICE}" && echo -e "${GREEN}运行中${RESET}" || echo -e "${RED}已停止${RESET}"
    else
      if [ -f "$GOST_PIDFILE" ] && kill -0 "$(cat "$GOST_PIDFILE" 2>/dev/null)" 2>/dev/null; then
        echo -e "${GREEN}运行中${RESET}"
      else
        echo -e "${RED}已停止${RESET}"
      fi
    fi
  else
    if has_openrc; then
      rc-service ${SERVICE_NAME} status >/dev/null 2>&1 && echo -e "${GREEN}运行中${RESET}" || echo -e "${RED}已停止${RESET}"
    else
      systemctl is-active --quiet ${SERVICE_NAME} && echo -e "${GREEN}运行中${RESET}" || echo -e "${RED}已停止${RESET}"
    fi
  fi
}

detect_pkg_manager() {
  if command -v apk >/dev/null 2>&1; then
    echo "apk"
  elif command -v apt >/dev/null 2>&1; then
    echo "apt"
  elif command -v dnf >/dev/null 2>&1; then
    echo "dnf"
  elif command -v yum >/dev/null 2>&1; then
    echo "yum"
  else
    echo "unknown"
  fi
}

install_common_deps() {
  pkg_mgr=$(detect_pkg_manager)
  case "$pkg_mgr" in
    apk)
      apk add --no-cache curl shadow iproute2 tar gzip >/dev/null 2>&1
      ;;
    apt)
      apt update -y >/dev/null 2>&1
      apt install -y curl passwd iproute2 tar gzip ca-certificates >/dev/null 2>&1
      ;;
    dnf)
      dnf install -y curl shadow-utils iproute tar gzip ca-certificates >/dev/null 2>&1
      ;;
    yum)
      yum install -y curl shadow-utils iproute tar gzip ca-certificates >/dev/null 2>&1
      ;;
    *)
      echo -e "${RED}❌ 不支持的系统包管理器${RESET}"
      return 1
      ;;
  esac
}

install_dante_deps() {
  pkg_mgr=$(detect_pkg_manager)
  case "$pkg_mgr" in
    apk)
      apk add --no-cache dante-server >/dev/null 2>&1
      ;;
    apt)
      apt update -y >/dev/null 2>&1
      apt install -y dante-server >/dev/null 2>&1
      ;;
    dnf)
      dnf install -y dante-server >/dev/null 2>&1
      ;;
    yum)
      yum install -y dante-server >/dev/null 2>&1
      ;;
    *)
      echo -e "${RED}❌ 不支持的系统包管理器${RESET}"
      return 1
      ;;
  esac
}

format_host_for_url() {
  ip="$1"
  ip_type="$2"
  if [ "$ip_type" = "6" ]; then
    echo "[$ip]"
  else
    echo "$ip"
  fi
}

ensure_nobody_user() {
  if ! id nobody >/dev/null 2>&1; then
    if command -v useradd >/dev/null 2>&1; then
      useradd -r -s /usr/sbin/nologin nobody 2>/dev/null || useradd -r -s /sbin/nologin nobody 2>/dev/null || true
    fi
  fi
}

write_dante_conf_ipv4() {
  iface="$1"
  port="$2"
  cat > "$CONF_FILE" <<EOT
logoutput: ${LOG_FILE}
user.privileged: root
user.unprivileged: nobody
socksmethod: username
clientmethod: none
external: ${iface}
internal: 0.0.0.0 port = ${port}

client pass {
  from: 0.0.0.0/0 to: 0.0.0.0/0
  log: error connect disconnect
}

socks pass {
  from: 0.0.0.0/0 to: 0.0.0.0/0
  command: bind connect udpassociate
  log: error connect disconnect
}
EOT
}

save_info() {
  ip="$1"
  port="$2"
  user="$3"
  pass="$4"
  ip_type="$5"

  host=$(format_host_for_url "$ip" "$ip_type")
  socks5_link="socks5://${user}:${pass}@${host}:${port}"
  tg_link="tg://socks?server=${ip}&port=${port}&user=${user}&pass=${pass}"

  cat > "$INFO_FILE" <<EOT
IP="${ip}"
PORT="${port}"
USER="${user}"
PASS="${pass}"
IP_TYPE="${ip_type}"
SOCKS5_LINK="${socks5_link}"
TG_LINK="${tg_link}"
EOT
}

read_info() {
  grep "^$1=" "$INFO_FILE" 2>/dev/null | head -n1 | cut -d'"' -f2
}

stop_dante_service() {
  if has_openrc; then
    rc-service ${SERVICE_NAME} stop >/dev/null 2>&1
  else
    systemctl stop ${SERVICE_NAME} >/dev/null 2>&1
  fi
  sleep 1
}

start_dante_service() {
  if has_openrc; then
    rc-update add ${SERVICE_NAME} default >/dev/null 2>&1
    rc-service ${SERVICE_NAME} restart >/dev/null 2>&1
    sleep 1
    rc-service ${SERVICE_NAME} status >/dev/null 2>&1
  else
    systemctl enable ${SERVICE_NAME} >/dev/null 2>&1
    systemctl restart ${SERVICE_NAME} >/dev/null 2>&1
    sleep 1
    systemctl is-active --quiet ${SERVICE_NAME}
  fi
}

show_dante_debug_on_fail() {
  echo -e "${YELLOW}================ 调试信息开始 ================${RESET}"
  echo -e "${CYAN}[1] 当前配置文件:${RESET}"
  cat "$CONF_FILE" 2>/dev/null || echo "无法读取 $CONF_FILE"
  echo ""

  echo -e "${CYAN}[2] 服务最近日志:${RESET}"
  if command -v journalctl >/dev/null 2>&1; then
    journalctl -u ${SERVICE_NAME} -n 30 --no-pager 2>/dev/null || true
  fi
  tail -n 30 "$LOG_FILE" 2>/dev/null || true
  echo ""

  echo -e "${CYAN}[3] 当前监听端口:${RESET}"
  port_now=$(grep -o 'port = [0-9]*' "$CONF_FILE" 2>/dev/null | awk '{print $3}' | head -n1)
  ss -tlnp 2>/dev/null | grep -E "[:.]${port_now}[[:space:]]" || echo "未检测到监听"
  echo -e "${YELLOW}================ 调试信息结束 ================${RESET}"
}

choose_ip_mode() {
  echo ""
  echo -e "${CYAN}--- 请选择对外使用的 IP 类型 ---${RESET}"
  echo -e "  ${GREEN}1.${RESET} IPv4 ${YELLOW}(默认，Dante 后端)${RESET}"
  echo -e "  ${GREEN}2.${RESET} IPv6 ${YELLOW}(实验性支持，GOST 后端)${RESET}"
  read -p "请输入序号 (回车默认 1): " ip_choice

  if [ -z "$ip_choice" ] || [ "$ip_choice" = "1" ]; then
    IP_TYPE="4"
    AUTO_IP=$(get_public_ip 4)
    DISPLAY_IP=${AUTO_IP:-"获取失败，请手动输入"}
    read -p "👉 请输入公网 IPv4 地址 (识别出: $DISPLAY_IP): " PUBLIC_IP
    PUBLIC_IP=${PUBLIC_IP:-$AUTO_IP}
    is_valid_ipv4 "$PUBLIC_IP" || { echo -e "${RED}❌ 公网 IPv4 地址无效！${RESET}"; return 1; }
  elif [ "$ip_choice" = "2" ]; then
    IP_TYPE="6"
    AUTO_IP=$(get_public_ip 6)
    DISPLAY_IP=${AUTO_IP:-"获取失败，请手动输入"}
    read -p "👉 请输入公网 IPv6 地址 (识别出: $DISPLAY_IP): " PUBLIC_IP
    PUBLIC_IP=${PUBLIC_IP:-$AUTO_IP}
    is_valid_ipv6 "$PUBLIC_IP" || { echo -e "${RED}❌ 公网 IPv6 地址无效！${RESET}"; return 1; }
  else
    echo -e "${RED}❌ 输入错误！${RESET}"
    return 1
  fi
  return 0
}

ensure_user_password() {
  user="$1"
  pass="$2"
  if id "$user" >/dev/null 2>&1; then
    echo "$user:$pass" | chpasswd
  else
    if command -v useradd >/dev/null 2>&1; then
      useradd -M -s /usr/sbin/nologin "$user" 2>/dev/null || useradd -M -s /sbin/nologin "$user" 2>/dev/null || useradd "$user"
    else
      adduser -D -s /sbin/nologin "$user" 2>/dev/null || adduser "$user"
    fi
    echo "$user:$pass" | chpasswd
  fi
}

install_gost_binary() {
  [ -x "$GOST_BIN" ] && return 0

  ARCH=$(uname -m)
  case "$ARCH" in
    x86_64|amd64) GOST_ARCH="amd64" ;;
    aarch64|arm64) GOST_ARCH="arm64" ;;
    armv7l|armv7) GOST_ARCH="armv7" ;;
    armv6l|armv6) GOST_ARCH="armv6" ;;
    i386|i686) GOST_ARCH="386" ;;
    *)
      echo -e "${RED}❌ 不支持的架构: $ARCH${RESET}"
      return 1
      ;;
  esac

  TMP_DIR=$(mktemp -d)
  API_URL="https://api.github.com/repos/go-gost/gost/releases/latest"
  TAG=$(curl -fsSL "$API_URL" 2>/dev/null | grep '"tag_name":' | head -n1 | sed -E 's/.*"([^"]+)".*/\1/')
  [ -z "$TAG" ] && TAG="v3.0.0"

  FILE_NAME="gost_${TAG#v}_linux_${GOST_ARCH}.tar.gz"
  GOST_URL="https://github.com/go-gost/gost/releases/download/${TAG}/${FILE_NAME}"

  echo -e "${YELLOW}正在下载 gost: ${TAG} (${GOST_ARCH})...${RESET}"
  if ! curl -fsSL "$GOST_URL" -o "$TMP_DIR/gost.tar.gz"; then
    echo -e "${RED}❌ gost 下载失败: $GOST_URL${RESET}"
    rm -rf "$TMP_DIR"
    return 1
  fi

  tar -xzf "$TMP_DIR/gost.tar.gz" -C "$TMP_DIR" >/dev/null 2>&1
  GOST_FOUND=$(find "$TMP_DIR" -type f -name gost | head -n1)

  if [ -z "$GOST_FOUND" ]; then
    echo -e "${RED}❌ gost 解压失败${RESET}"
    rm -rf "$TMP_DIR"
    return 1
  fi

  install -m 755 "$GOST_FOUND" "$GOST_BIN"
  rm -rf "$TMP_DIR"
  return 0
}

write_gost_openrc_runner() {
  cat > /usr/local/bin/gost-s5-run <<EOT
#!/bin/sh
exec ${GOST_BIN} -L "socks5://\$(cat /etc/gost-s5-user):\$(cat /etc/gost-s5-pass)@[::]:\$(cat /etc/gost-s5-port)"
EOT
  chmod +x /usr/local/bin/gost-s5-run
}

write_gost_systemd_service() {
  port="$1"
  user="$2"
  pass="$3"

  cat > /etc/systemd/system/${GOST_SERVICE}.service <<EOT
[Unit]
Description=GOST SOCKS5 IPv6 Service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=${GOST_BIN} -L socks5://${user}:${pass}@[::]:${port}
Restart=always
RestartSec=3
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOT

  systemctl daemon-reload
}

write_gost_openrc_service() {
  mkdir -p /etc/init.d

  cat > /etc/init.d/${GOST_SERVICE} <<'EOT'
#!/sbin/openrc-run
name="gost-s5"
description="GOST SOCKS5 IPv6 Service"
command="/usr/local/bin/gost-s5-run"
command_background="yes"
pidfile="/run/gost-s5.pid"
output_log="/var/log/gost-s5.log"
error_log="/var/log/gost-s5.log"
respawn_delay=3
EOT

  chmod +x /etc/init.d/${GOST_SERVICE}
}

write_gost_service() {
  port="$1"
  user="$2"
  pass="$3"

  echo "$port" > /etc/gost-s5-port
  echo "$user" > /etc/gost-s5-user
  echo "$pass" > /etc/gost-s5-pass
  chmod 600 /etc/gost-s5-port /etc/gost-s5-user /etc/gost-s5-pass

  if has_systemd; then
    write_gost_systemd_service "$port" "$user" "$pass"
  elif has_openrc; then
    write_gost_openrc_runner
    write_gost_openrc_service
  else
    echo -e "${RED}❌ 当前系统既没有 systemd 也没有 OpenRC，无法托管 gost${RESET}"
    return 1
  fi
}

start_gost_service() {
  if has_systemd; then
    systemctl enable ${GOST_SERVICE} >/dev/null 2>&1
    systemctl restart ${GOST_SERVICE} >/dev/null 2>&1
    sleep 1
    systemctl is-active --quiet ${GOST_SERVICE}
  elif has_openrc; then
    rc-update add ${GOST_SERVICE} default >/dev/null 2>&1
    rc-service ${GOST_SERVICE} stop >/dev/null 2>&1
    rc-service ${GOST_SERVICE} start >/dev/null 2>&1
    sleep 1
    rc-service ${GOST_SERVICE} status >/dev/null 2>&1
  else
    return 1
  fi
}

stop_gost_service() {
  if has_systemd; then
    systemctl stop ${GOST_SERVICE} >/dev/null 2>&1
  elif has_openrc; then
    rc-service ${GOST_SERVICE} stop >/dev/null 2>&1
  else
    [ -f "$GOST_PIDFILE" ] && kill "$(cat "$GOST_PIDFILE" 2>/dev/null)" 2>/dev/null
  fi
  sleep 1
}

show_gost_debug_on_fail() {
  echo -e "${YELLOW}================ GOST 调试信息开始 ================${RESET}"
  if has_systemd; then
    systemctl status ${GOST_SERVICE} --no-pager -l 2>/dev/null || true
    journalctl -u ${GOST_SERVICE} -n 50 --no-pager 2>/dev/null || true
  elif has_openrc; then
    rc-service ${GOST_SERVICE} status 2>/dev/null || true
    tail -n 50 /var/log/gost-s5.log 2>/dev/null || true
  fi
  echo -e "${CYAN}[监听检查]${RESET}"
  ss -tlnp 2>/dev/null | grep -E "[:.]$(cat /etc/gost-s5-port 2>/dev/null)$" || echo "未检测到监听"
  echo -e "${YELLOW}================ GOST 调试信息结束 ================${RESET}"
}

install_s5_ipv4_dante() {
  clear
  echo -e "${CYAN}=========================================${RESET}"
  echo -e "${CYAN}  🚀 开始部署 SOCKS5 代理 (Dante / IPv4)${RESET}"
  echo -e "${CYAN}=========================================${RESET}"

  stop_dante_service
  install_common_deps || { pause; return; }
  install_dante_deps || { pause; return; }
  ensure_nobody_user

  iface=$(detect_iface)
  [ -z "$iface" ] && iface="eth0"

  echo ""
  echo -e "${YELLOW}💡 提示: SOCKS5 推荐使用 1080 或 10800 端口。${RESET}"
  read -p "👉 请输入监听端口 (回车默认 1080): " port
  port=${port:-1080}

  if ! is_valid_port "$port"; then
    echo -e "${RED}❌ 端口无效！${RESET}"; pause; return
  fi
  if is_port_in_use "$port"; then
    echo -e "${RED}❌ 端口 ${port} 已被占用！${RESET}"; pause; return
  fi

  AUTO_IP=$(get_public_ip 4)
  DISPLAY_IP=${AUTO_IP:-"获取失败，请手动输入"}
  read -p "👉 请输入公网 IPv4 地址 (识别出: $DISPLAY_IP): " PUBLIC_IP
  PUBLIC_IP=${PUBLIC_IP:-$AUTO_IP}
  is_valid_ipv4 "$PUBLIC_IP" || { echo -e "${RED}❌ 公网 IPv4 地址无效！${RESET}"; pause; return; }

  read -p "👉 请输入用户名 (回车默认 s5user): " user
  user=${user:-s5user}

  read -p "👉 请输入密码 (回车默认随机8位): " pass
  [ -z "$pass" ] && pass=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 8)

  ensure_user_password "$user" "$pass"
  write_dante_conf_ipv4 "$iface" "$port"

  if start_dante_service; then
    save_info "$PUBLIC_IP" "$port" "$user" "$pass" "4"
    echo -e "\n${GREEN}✅ SOCKS5 IPv4 部署成功！(Dante)${RESET}"
    echo -e "当前服务状态: $(get_status)"
    echo -e "\n${CYAN}📱 TG 代理链接：${RESET}"
    echo -e "${GREEN}$(read_info TG_LINK)${RESET}"
    echo -e "\n${CYAN}🔗 SOCKS5 链接：${RESET}"
    echo -e "${YELLOW}$(read_info SOCKS5_LINK)${RESET}"
  else
    echo -e "${RED}❌ Dante IPv4 服务启动失败！${RESET}"
    show_dante_debug_on_fail
  fi
  pause
}

install_s5_ipv6_gost() {
  clear
  echo -e "${CYAN}=========================================${RESET}"
  echo -e "${CYAN}  🚀 开始部署 SOCKS5 代理 (GOST / IPv6)${RESET}"
  echo -e "${CYAN}=========================================${RESET}"

  stop_gost_service
  install_common_deps || { pause; return; }

  echo ""
  echo -e "${YELLOW}💡 提示: SOCKS5 推荐使用 1080 或 10800 端口。${RESET}"
  read -p "👉 请输入监听端口 (回车默认 1080): " port
  port=${port:-1080}

  if ! is_valid_port "$port"; then
    echo -e "${RED}❌ 端口无效！${RESET}"; pause; return
  fi
  if is_port_in_use "$port"; then
    echo -e "${RED}❌ 端口 ${port} 已被占用！${RESET}"; pause; return
  fi

  AUTO_IP=$(get_public_ip 6)
  DISPLAY_IP=${AUTO_IP:-"获取失败，请手动输入"}
  read -p "👉 请输入公网 IPv6 地址 (识别出: $DISPLAY_IP): " PUBLIC_IP
  PUBLIC_IP=${PUBLIC_IP:-$AUTO_IP}
  is_valid_ipv6 "$PUBLIC_IP" || { echo -e "${RED}❌ 公网 IPv6 地址无效！${RESET}"; pause; return; }

  read -p "👉 请输入用户名 (回车默认 s5user): " user
  user=${user:-s5user}

  read -p "👉 请输入密码 (回车默认随机8位): " pass
  [ -z "$pass" ] && pass=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 8)

  ensure_user_password "$user" "$pass"
  install_gost_binary || { pause; return; }
  write_gost_service "$port" "$user" "$pass" || { pause; return; }

  if start_gost_service; then
    save_info "$PUBLIC_IP" "$port" "$user" "$pass" "6"
    echo -e "\n${GREEN}✅ SOCKS5 IPv6 部署成功！(GOST)${RESET}"
    echo -e "当前服务状态: $(get_status)"
    echo -e "\n${CYAN}📱 TG 代理链接：${RESET}"
    echo -e "${GREEN}$(read_info TG_LINK)${RESET}"
    echo -e "\n${CYAN}🔗 SOCKS5 链接：${RESET}"
    echo -e "${YELLOW}$(read_info SOCKS5_LINK)${RESET}"
  else
    echo -e "${RED}❌ GOST IPv6 服务启动失败！${RESET}"
    show_gost_debug_on_fail
  fi
  pause
}

install_s5() {
  clear
  echo -e "${CYAN}=========================================${RESET}"
  echo -e "${CYAN}  🚀 开始部署 SOCKS5 代理${RESET}"
  echo -e "${CYAN}=========================================${RESET}"

  if [ -f "$INFO_FILE" ]; then
    echo -e "${YELLOW}⚠️ 检测到当前机器已经存在 SOCKS5 配置信息！${RESET}"
    read -p "👉 是否继续【覆盖重装】？[y/N]: " confirm_reinstall
    case "$confirm_reinstall" in
      y|Y) ;;
      *) echo -e "${GREEN}✅ 已取消安装。${RESET}"; sleep 1; return ;;
    esac
  fi

  choose_ip_mode || { pause; return; }

  if [ "$IP_TYPE" = "6" ]; then
    install_s5_ipv6_gost
  else
    install_s5_ipv4_dante
  fi
}

view_info() {
  clear
  echo -e "${CYAN}=========================================${RESET}"
  if [ ! -f "$INFO_FILE" ]; then
    echo -e "${RED}未找到配置，请先安装！${RESET}"
    echo -e "${CYAN}=========================================${RESET}"
    pause
    return
  fi

  ip_type=$(read_info IP_TYPE)
  [ -z "$ip_type" ] && ip_type="4"
  if [ "$ip_type" = "6" ]; then
    backend_name="GOST"
  else
    backend_name="Dante"
  fi

  echo -e "当前服务状态:     $(get_status)"
  echo -e "当前监听端口:     ${GREEN}$(read_info PORT)${RESET}"
  echo -e "当前对外公网地址: ${GREEN}$(read_info IP):$(read_info PORT)${RESET}"
  echo -e "当前 IP 类型:     ${GREEN}IPv$(read_info IP_TYPE)${RESET}"
  echo -e "当前后端:         ${GREEN}${backend_name}${RESET}"
  echo -e "当前账号:         ${GREEN}$(read_info USER)${RESET}"
  echo -e "当前密码:         ${GREEN}$(read_info PASS)${RESET}"
  echo -e "\n${CYAN}📱 TG 代理链接：${RESET}"
  echo -e "${GREEN}$(read_info TG_LINK)${RESET}"
  echo -e "\n${CYAN}🔗 SOCKS5 链接：${RESET}"
  echo -e "${YELLOW}$(read_info SOCKS5_LINK)${RESET}"
  echo -e "${CYAN}=========================================${RESET}"
  pause
}

modify_s5() {
  clear
  if [ ! -f "$INFO_FILE" ]; then
    echo -e "${RED}请先安装！${RESET}"
    pause
    return
  fi

  old_ip_type=$(read_info IP_TYPE)
  [ -z "$old_ip_type" ] && old_ip_type="4"

  if [ "$old_ip_type" = "6" ]; then
    echo -e "${YELLOW}当前 IPv6 SOCKS5 使用 GOST 后端。${RESET}"
    echo -e "${YELLOW}为避免影响配置一致性，建议直接走覆盖重装流程。${RESET}"
    read -p "是否进入 IPv6 重装流程？[Y/n]: " yn
    case "$yn" in
      n|N) pause; return ;;
      *) install_s5_ipv6_gost; return ;;
    esac
  fi

  old_port=$(read_info PORT)
  old_user=$(read_info USER)
  old_pass=$(read_info PASS)
  old_ip=$(read_info IP)

  iface=$(detect_iface)
  [ -z "$iface" ] && iface="eth0"

  echo -e "${CYAN}--- 修改 IPv4 Dante 配置 ---${RESET}"

  read -p "输入新【监听端口】 (回车保持 ${old_port}): " port
  port=${port:-$old_port}
  if ! is_valid_port "$port"; then
    echo -e "${RED}❌ 端口无效！${RESET}"
    pause
    return
  fi
  if [ "$port" != "$old_port" ] && is_port_in_use "$port"; then
    echo -e "${RED}❌ 端口已被占用！${RESET}"
    pause
    return
  fi

  AUTO_IP=$(get_public_ip 4)
  DISPLAY_IP=${AUTO_IP:-"获取失败"}
  echo -e "${YELLOW}当前机器识别到的 IPv4 为: ${DISPLAY_IP}${RESET}"
  read -p "输入新【公网 IPv4】 (回车保持 ${old_ip}): " NEW_IP
  NEW_IP=${NEW_IP:-$old_ip}
  is_valid_ipv4 "$NEW_IP" || { echo -e "${RED}❌ 公网 IPv4 格式无效！${RESET}"; pause; return; }

  read -p "输入新【用户名】 (回车保持 ${old_user}): " user
  user=${user:-$old_user}

  read -p "输入新【密码】 (回车保持原密码): " pass
  pass=${pass:-$old_pass}

  if [ "$user" != "$old_user" ]; then
    id "$old_user" >/dev/null 2>&1 && userdel "$old_user" 2>/dev/null
  fi

  ensure_nobody_user
  ensure_user_password "$user" "$pass"
  write_dante_conf_ipv4 "$iface" "$port"

  if start_dante_service; then
    save_info "$NEW_IP" "$port" "$user" "$pass" "4"
    echo -e "${GREEN}✅ 配置已更新并重启成功！${RESET}"
    echo -e "\n${CYAN}📱 TG 代理链接：${RESET}"
    echo -e "${GREEN}$(read_info TG_LINK)${RESET}"
    echo -e "\n${CYAN}🔗 SOCKS5 链接：${RESET}"
    echo -e "${YELLOW}$(read_info SOCKS5_LINK)${RESET}"
  else
    echo -e "${RED}❌ 配置已写入，但服务启动失败！${RESET}"
    show_dante_debug_on_fail
  fi
  pause
}

service_ctl() {
  action="$1"
  backend=$(get_backend_type)

  if [ "$backend" = "gost" ]; then
    if has_systemd; then
      systemctl ${action} ${GOST_SERVICE}
    elif has_openrc; then
      rc-service ${GOST_SERVICE} ${action}
    fi
  else
    if has_openrc; then
      rc-service ${SERVICE_NAME} ${action}
    else
      systemctl ${action} ${SERVICE_NAME}
    fi
  fi

  sleep 1
  echo -e "当前状态: $(get_status)"
  pause
}

view_logs() {
  clear
  echo -e "${CYAN}=========================================${RESET}"
  echo -e "               📜 SOCKS5 运行日志"
  echo -e "${CYAN}=========================================${RESET}"

  backend=$(get_backend_type)
  if [ "$backend" = "gost" ]; then
    if has_systemd; then
      journalctl -u ${GOST_SERVICE} --no-pager -n 50 2>/dev/null || echo "暂无日志"
    else
      tail -n 50 /var/log/gost-s5.log 2>/dev/null || echo "暂无日志"
    fi
  else
    if command -v journalctl >/dev/null 2>&1; then
      journalctl -u ${SERVICE_NAME} --no-pager -n 50 2>/dev/null || tail -n 50 "$LOG_FILE" 2>/dev/null || echo "暂无日志"
    else
      tail -n 50 "$LOG_FILE" 2>/dev/null || echo "暂无日志"
    fi
  fi

  echo -e "${CYAN}=========================================${RESET}"
  pause
}

uninstall_s5() {
  clear
  echo -e "${RED}你正在执行 SOCKS5 卸载操作！${RESET}"
  read -p "确认彻底卸载 SOCKS5 吗？[y/N]: " confirm_uninstall
  case "$confirm_uninstall" in
    y|Y) ;;
    *) echo -e "${YELLOW}已取消卸载。${RESET}"; sleep 1; return ;;
  esac

  echo -e "${RED}正在卸载...${RESET}"

  stop_dante_service
  stop_gost_service

  pkg_mgr=$(detect_pkg_manager)
  case "$pkg_mgr" in
    apk) apk del dante-server >/dev/null 2>&1 ;;
    apt) apt remove -y dante-server >/dev/null 2>&1 ;;
    dnf) dnf remove -y dante-server >/dev/null 2>&1 ;;
    yum) yum remove -y dante-server >/dev/null 2>&1 ;;
  esac

  if has_systemd; then
    systemctl disable ${GOST_SERVICE} >/dev/null 2>&1
    rm -f /etc/systemd/system/${GOST_SERVICE}.service
    systemctl daemon-reload >/dev/null 2>&1
  elif has_openrc; then
    rc-update del ${GOST_SERVICE} default >/dev/null 2>&1
    rm -f /etc/init.d/${GOST_SERVICE}
  fi

  rm -f "$CONF_FILE" "$INFO_FILE" "$LOG_FILE"
  rm -f "$GOST_BIN" /usr/local/bin/gost-s5-run
  rm -f /etc/gost-s5-port /etc/gost-s5-user /etc/gost-s5-pass
  rm -f /var/log/gost-s5.log "$GOST_PIDFILE"
  rm -f /usr/local/bin/s5

  echo -e "${GREEN}✅ 卸载完成！${RESET}"
  sleep 2
  exit 0
}

update_script() {
  clear
  echo -e "${YELLOW}正在从 GitHub 拉取最新脚本...${RESET}"
  tmp_file=$(mktemp)
  if curl -fsSL --connect-timeout 10 "${SCRIPT_URL}" -o "$tmp_file" 2>/dev/null; then
    sed -i 's/\r$//' "$tmp_file"
    if sh -n "$tmp_file" 2>/dev/null; then
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

if [ "$(id -u)" -ne 0 ]; then
  echo -e "${RED}请使用 root 用户运行！${RESET}"
  exit 1
fi

while true; do
  clear
  if [ -f "$INFO_FILE" ]; then
    CURRENT_IP=$(read_info IP)
    CURRENT_PORT=$(read_info PORT)
    CURRENT_USER=$(read_info USER)
    CURRENT_IP_TYPE=$(read_info IP_TYPE)
    [ -z "$CURRENT_IP_TYPE" ] && CURRENT_IP_TYPE="4"
  else
    CURRENT_IP="-"
    CURRENT_PORT="-"
    CURRENT_USER="-"
    CURRENT_IP_TYPE="-"
  fi

  echo -e "${CYAN}=========================================${RESET}"
  echo -e "   🦇 SOCKS5 管理面板 ${GREEN}${SCRIPT_VERSION}${RESET}"
  echo -e "${CYAN}=========================================${RESET}"
  echo -e "当前状态: ${RESET}$(get_status)"
  echo -e "当前地址: ${YELLOW}${CURRENT_IP}:${CURRENT_PORT}${RESET}"
  echo -e "IP 类型:  ${GREEN}IPv${CURRENT_IP_TYPE}${RESET}"
  echo -e "当前账号: ${GREEN}${CURRENT_USER}${RESET}"
  echo -e "快捷指令: ${GREEN}s5${RESET}"
  echo -e "${CYAN}-----------------------------------------${RESET}"
  echo -e "  ${GREEN}1.${RESET} 安装 / 重装 SOCKS5"
  echo -e "  ${GREEN}2.${RESET} 查看当前连接信息"
  echo -e "  ${GREEN}3.${RESET} 修改端口、IP 与账号密码"
  echo -e "  ${YELLOW}4.${RESET} 启动 SOCKS5 服务"
  echo -e "  ${YELLOW}5.${RESET} 停止 SOCKS5 服务"
  echo -e "  ${CYAN}6.${RESET} 重启 SOCKS5 服务"
  echo -e "  ${CYAN}7.${RESET} 查看运行日志"
  echo -e "  ${BLUE}8.${RESET} 更新脚本代码 (从 GitHub 同步)"
  echo -e "  ${RED}9.${RESET} 彻底卸载 SOCKS5"
  echo -e "  ${GREEN}0.${RESET} 退出面板"
  echo -e "${CYAN}=========================================${RESET}"
  read -p "请输入序号选择功能: " choice

  case "$choice" in
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
    *) echo -e "${RED}输入错误！${RESET}"; sleep 1 ;;
  esac
done
EOF

chmod +x /usr/local/bin/s5
echo -e "\033[32m✅ S5 最终版已写入：IPv4 走 Dante，IPv6 走 GOST，并兼容 systemd/OpenRC。\033[0m"
