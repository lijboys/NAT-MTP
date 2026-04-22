cat > /usr/local/bin/mtp <<'EOFMTP'
#!/bin/bash

GREEN="\033[32m"
RED="\033[31m"
YELLOW="\033[33m"
CYAN="\033[36m"
RESET="\033[0m"

_OS_TYPE=""
_PKG_MANAGER=""

get_os() {
  [ -n "$_OS_TYPE" ] && { echo "$_OS_TYPE"; return; }
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    _OS_TYPE="$ID"
  else
    _OS_TYPE="unknown"
  fi
  echo "$_OS_TYPE"
}

get_pkg_manager() {
  [ -n "$_PKG_MANAGER" ] && { echo "$_PKG_MANAGER"; return; }
  
  if command -v apk >/dev/null 2>&1; then
    _PKG_MANAGER="apk"
  elif command -v apt >/dev/null 2>&1; then
    _PKG_MANAGER="apt"
  elif command -v dnf >/dev/null 2>&1; then
    _PKG_MANAGER="dnf"
  elif command -v yum >/dev/null 2>&1; then
    _PKG_MANAGER="yum"
  else
    _PKG_MANAGER="unknown"
  fi
  echo "$_PKG_MANAGER"
}

get_arch() {
  case "$(uname -m)" in
    x86_64|amd64) echo "amd64" ;;
    aarch64|arm64) echo "arm64" ;;
    armv7l|armv7) echo "armv7" ;;
    *) echo "unsupported" ;;
  esac
}

install_package() {
  local pkg_mgr=$(get_pkg_manager)
  local packages=("$@")
  
  case "$pkg_mgr" in
    apk)
      apk add --no-cache "${packages[@]}" >/dev/null 2>&1
      ;;
    apt)
      apt update -y >/dev/null 2>&1
      apt install -y "${packages[@]}" >/dev/null 2>&1
      ;;
    dnf)
      dnf install -y "${packages[@]}" >/dev/null 2>&1
      ;;
    yum)
      yum install -y "${packages[@]}" >/dev/null 2>&1
      ;;
    *)
      return 1
      ;;
  esac
}

check_and_install_deps() {
  local missing=()
  for cmd in "$@"; do
    command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
  done
  
  [ ${#missing[@]} -eq 0 ] && return 0
  
  echo -e "${YELLOW}检测到缺少依赖: ${missing[*]}${RESET}"
  echo -e "${YELLOW}正在自动安装...${RESET}"
  
  if install_package "${missing[@]}"; then
    echo -e "${GREEN}✅ 依赖安装完成${RESET}"
    return 0
  else
    echo -e "${RED}❌ 依赖安装失败${RESET}"
    return 1
  fi
}

is_valid_port() {
  [[ "$1" =~ ^[0-9]+$ ]] && [ "$1" -ge 1 ] && [ "$1" -le 65535 ]
}

is_valid_ipv4() {
  local ip=$1
  [[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
  IFS='.' read -r o1 o2 o3 o4 <<< "$ip"
  for o in "$o1" "$o2" "$o3" "$o4"; do
    [[ "$o" =~ ^[0-9]+$ ]] && [ "$o" -ge 0 ] && [ "$o" -le 255 ] || return 1
  done
  return 0
}

is_valid_domain() {
  [[ "$1" =~ ^[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]
}

is_port_in_use() {
  ss -tln 2>/dev/null | awk '{print $4}' | grep -qE "[:.]$1$"
}

get_public_ip() {
  local sources=("ipv4.icanhazip.com" "api.ipify.org" "ifconfig.me")
  for src in "${sources[@]}"; do
    local ip=$(curl -s4m3 --connect-timeout 3 "$src" 2>/dev/null)
    is_valid_ipv4 "$ip" && { echo "$ip"; return 0; }
  done
  return 1
}

start_service() {
  local service=$1
  local os=$(get_os)
  
  if command -v systemctl >/dev/null 2>&1; then
    systemctl enable "$service" >/dev/null 2>&1
    systemctl restart "$service" >/dev/null 2>&1
  elif [ "$os" = "alpine" ] && command -v rc-service >/dev/null 2>&1; then
    rc-update add "$service" >/dev/null 2>&1
    rc-service "$service" restart >/dev/null 2>&1
  else
    return 1
  fi
  sleep 1
}

stop_service() {
  local service=$1
  local os=$(get_os)
  
  if command -v systemctl >/dev/null 2>&1; then
    systemctl stop "$service" >/dev/null 2>&1
  elif [ "$os" = "alpine" ] && command -v rc-service >/dev/null 2>&1; then
    rc-service "$service" stop >/dev/null 2>&1
  else
    pkill -9 -f "$service" 2>/dev/null
  fi
  sleep 1
}

get_service_status() {
  local service=$1
  local os=$(get_os)
  
  if command -v systemctl >/dev/null 2>&1; then
    systemctl is-active --quiet "$service" 2>/dev/null && echo -e "${GREEN}运行中${RESET}" || echo -e "${RED}已停止${RESET}"
  elif [ "$os" = "alpine" ] && command -v rc-service >/dev/null 2>&1; then
    rc-service "$service" status >/dev/null 2>&1 && echo -e "${GREEN}运行中${RESET}" || echo -e "${RED}已停止${RESET}"
  else
    pgrep -f "$service" >/dev/null 2>&1 && echo -e "${GREEN}运行中${RESET}" || echo -e "${RED}已停止${RESET}"
  fi
}

read_config() {
  local file=$1 key=$2
  grep "^${key}=" "$file" 2>/dev/null | head -n1 | cut -d'"' -f2
}

download_file() {
  local url=$1 output=$2
  curl -fsSL --connect-timeout 10 "$url" -o "$output" 2>/dev/null
}

die() {
  echo -e "${RED}❌ $*${RESET}" >&2
  exit 1
}

warn() {
  echo -e "${YELLOW}⚠️ $*${RESET}"
}

info() {
  echo -e "${GREEN}✅ $*${RESET}"
}

pause_menu() {
  read -p "按回车键返回..."
}

# ================= MTG 特定函数 =================

SCRIPT_VERSION="v1.3.0"
MTG_VERSION="2.1.7"

CONFIG_FILE="/etc/mtg.toml"
INFO_FILE="/etc/mtg_info.txt"
SERVICE_FILE="/etc/systemd/system/mtg.service"
INIT_FILE="/etc/init.d/mtg"
LOG_FILE="/var/log/mtg.log"

[ "$EUID" -ne 0 ] && die "请使用 root 用户运行"

download_mtg() {
  local arch=$(get_arch)
  [ "$arch" = "unsupported" ] && die "不支持的架构: $(uname -m)"
  
  local url="https://github.com/9seconds/mtg/releases/download/v${MTG_VERSION}/mtg-${MTG_VERSION}-linux-${arch}.tar.gz"
  local tmp_dir=$(mktemp -d)
  
  echo -e "${YELLOW}正在下载 mtg v${MTG_VERSION} (${arch})...${RESET}"
  download_file "$url" "${tmp_dir}/mtg.tar.gz" || { rm -rf "$tmp_dir"; return 1; }
  
  tar -zxf "${tmp_dir}/mtg.tar.gz" -C "$tmp_dir" 2>/dev/null || { rm -rf "$tmp_dir"; return 1; }
  local mtg_bin=$(find "$tmp_dir" -type f -name mtg 2>/dev/null | head -n1)
  [ -z "$mtg_bin" ] && { rm -rf "$tmp_dir"; return 1; }
  
  install -m 755 "$mtg_bin" /usr/local/bin/mtg
  rm -rf "$tmp_dir"
  /usr/local/bin/mtg --help >/dev/null 2>&1 || return 1
}

generate_secret() {
  /usr/local/bin/mtg generate-secret "$1" 2>/dev/null
}

write_mtg_config() {
  cat > "$CONFIG_FILE" <<EOF
secret = "$2"
bind-to = "0.0.0.0:$1"
EOF
}

write_mtg_info() {
  local tg_link="tg://proxy?server=$2&port=$3&secret=$5"
  cat > "$INFO_FILE" <<EOF
IN_PORT="$1"
PUBLIC_IP="$2"
OUT_PORT="$3"
FAKE_DOMAIN="$4"
SECRET="$5"
TG_LINK="${tg_link}"
EOF
}

create_systemd_service() {
  mkdir -p /etc/systemd/system/
  cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=MTG v2 Proxy
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/mtg run ${CONFIG_FILE}
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload 2>/dev/null
}

create_openrc_service() {
  cat > "$INIT_FILE" <<'EOF'
#!/sbin/openrc-run

description="MTG v2 Proxy"
command="/usr/local/bin/mtg"
command_args="run /etc/mtg.toml"
pidfile="/var/run/mtg.pid"

depend() {
  need net
}

start() {
  ebegin "Starting MTG"
  start-stop-daemon --start --quiet --pidfile "$pidfile" \
    --exec "$command" -- $command_args >> /var/log/mtg.log 2>&1 &
  eend $?
}

stop() {
  ebegin "Stopping MTG"
  start-stop-daemon --stop --quiet --pidfile "$pidfile"
  eend $?
}
EOF
  chmod +x "$INIT_FILE"
}

setup_service() {
  local os=$(get_os)
  
  if command -v systemctl >/dev/null 2>&1; then
    create_systemd_service
    start_service mtg
  elif [ "$os" = "alpine" ]; then
    create_openrc_service
    start_service mtg
  fi
}

choose_domain() {
  clear
  echo -e "${CYAN}================ FakeTLS 伪装域名选择 ================${RESET}"
  echo -e "  ${GREEN}1.${RESET} www.cloudflare.com (推荐)"
  echo -e "  ${GREEN}2.${RESET} www.microsoft.com"
  echo -e "  ${GREEN}3.${RESET} www.apple.com"
  echo -e "  ${GREEN}4.${RESET} www.bing.com"
  echo -e "  ${YELLOW}10.${RESET} 自定义域名"
  echo -e "${CYAN}======================================================${RESET}"
  
  read -p "请选择 (回车默认 1): " choice
  
  case "$choice" in
    2) echo "www.microsoft.com" ;;
    3) echo "www.apple.com" ;;
    4) echo "www.bing.com" ;;
    10)
      read -p "输入自定义域名: " domain
      is_valid_domain "$domain" && echo "$domain" || echo "www.cloudflare.com"
      ;;
    *) echo "www.cloudflare.com" ;;
  esac
}

install_mtp() {
  clear
  echo -e "${CYAN}=========================================${RESET}"
  echo -e "${CYAN}  🚀 开始部署 MTG v2 伪装代理${RESET}"
  echo -e "${CYAN}=========================================${RESET}"
  
  check_and_install_deps curl tar grep awk sed pgrep ss || return 1
  
  if [ -f "/usr/local/bin/mtg" ] && [ -f "$INFO_FILE" ]; then
    warn "检测到已安装 MTG"
    read -p "是否覆盖重装？[y/N]: " confirm
    [[ "$confirm" != "y" && "$confirm" != "Y" ]] && return
  fi
  
  stop_service mtg
  download_mtg || { die "MTG 下载失败"; return 1; }
  
  local auto_ip=$(get_public_ip)
  local display_ip=${auto_ip:-"获取失败"}
  
  echo ""
  echo -e "${CYAN}--- 网络环境选择 ---${RESET}"
  echo -e "  ${GREEN}1.${RESET} NAT 小鸡 [默认]"
  echo -e "  ${YELLOW}2.${RESET} 独立 VPS"
  read -p "选择 (回车默认 1): " net_choice
  
  if [ -z "$net_choice" ] || [ "$net_choice" = "1" ]; then
    read -p "外网端口 (默认 10086): " out_port
    out_port=${out_port:-10086}
    is_valid_port "$out_port" || die "端口无效"
    
    read -p "内网端口 (默认 $out_port): " in_port
    in_port=${in_port:-$out_port}
    is_valid_port "$in_port" || die "端口无效"
    is_port_in_use "$in_port" && die "端口已占用"
  else
    read -p "监听端口 (默认 443): " in_port
    in_port=${in_port:-443}
    is_valid_port "$in_port" || die "端口无效"
    is_port_in_use "$in_port" && die "端口已占用"
    out_port=$in_port
  fi
  
  read -p "公网 IP (默认 $display_ip): " public_ip
  public_ip=${public_ip:-$auto_ip}
  is_valid_ipv4 "$public_ip" || die "IP 无效"
  
  local domain=$(choose_domain)
  local secret=$(generate_secret "$domain") || die "密钥生成失败"
  
  write_mtg_config "$in_port" "$secret"
  setup_service
  
  if get_service_status mtg | grep -q "运行中"; then
    write_mtg_info "$in_port" "$public_ip" "$out_port" "$domain" "$secret"
    info "部署成功！"
    echo -e "\n${CYAN}TG 链接：${RESET}"
    echo -e "${GREEN}tg://proxy?server=${public_ip}&port=${out_port}&secret=${secret}${RESET}"
  else
    die "服务启动失败"
  fi
  
  pause_menu
}

view_info() {
  clear
  [ ! -f "$INFO_FILE" ] && { warn "未安装"; pause_menu; return; }
  
  echo -e "${CYAN}=========================================${RESET}"
  echo -e "状态: $(get_service_status mtg)"
  echo -e "内网端口: ${GREEN}$(read_config "$INFO_FILE" IN_PORT)${RESET}"
  echo -e "公网地址: ${GREEN}$(read_config "$INFO_FILE" PUBLIC_IP):$(read_config "$INFO_FILE" OUT_PORT)${RESET}"
  echo -e "伪装域名: ${GREEN}$(read_config "$INFO_FILE" FAKE_DOMAIN)${RESET}"
  echo -e "\n${CYAN}TG 链接：${RESET}"
  echo -e "${GREEN}$(read_config "$INFO_FILE" TG_LINK)${RESET}"
  echo -e "${CYAN}=========================================${RESET}"
  pause_menu
}

modify_config() {
  clear
  [ ! -f "$INFO_FILE" ] && { warn "请先安装"; pause_menu; return; }
  
  local in_port=$(read_config "$INFO_FILE" IN_PORT)
  local public_ip=$(read_config "$INFO_FILE" PUBLIC_IP)
  local out_port=$(read_config "$INFO_FILE" OUT_PORT)
  local domain=$(read_config "$INFO_FILE" FAKE_DOMAIN)
  local secret=$(read_config "$INFO_FILE" SECRET)
  
  echo -e "${CYAN}--- 修改配置 ---${RESET}"
  read -p "内网端口 (默认 $in_port): " new_in
  new_in=${new_in:-$in_port}
  is_valid_port "$new_in" || die "端口无效"
  
  read -p "公网 IP (默认 $public_ip): " new_ip
  new_ip=${new_ip:-$public_ip}
  is_valid_ipv4 "$new_ip" || die "IP 无效"
  
  read -p "公网端口 (默认 $out_port): " new_out
  new_out=${new_out:-$out_port}
  is_valid_port "$new_out" || die "端口无效"
  
  write_mtg_config "$new_in" "$secret"
  start_service mtg
  write_mtg_info "$new_in" "$new_ip" "$new_out" "$domain" "$secret"
  
  info "配置已更新"
  pause_menu
}

view_logs() {
  clear
  echo -e "${CYAN}=========================================${RESET}"
  echo -e "               📜 MTG 运行日志"
  echo -e "${CYAN}=========================================${RESET}"
  if command -v journalctl >/dev/null 2>&1; then
    journalctl -u mtg --no-pager -n 50 2>/dev/null || echo "暂无日志"
  else
    tail -n 50 "$LOG_FILE" 2>/dev/null || echo "暂无日志"
  fi
  echo -e "${CYAN}=========================================${RESET}"
  pause_menu
}

uninstall_mtp() {
  clear
  warn "即将卸载 MTG"
  read -p "确认？[y/N]: " confirm
  [[ "$confirm" != "y" && "$confirm" != "Y" ]] && return
  
  stop_service mtg
  rm -f /usr/local/bin/mtg "$CONFIG_FILE" "$INFO_FILE" "$SERVICE_FILE" "$INIT_FILE"
  systemctl daemon-reload 2>/dev/null
  info "卸载完成"
  sleep 2
  exit 0
}

while true; do
  clear
  
  local status=$(get_service_status mtg)
  local ip=$([ -f "$INFO_FILE" ] && read_config "$INFO_FILE" PUBLIC_IP || echo "-")
  local port=$([ -f "$INFO_FILE" ] && read_config "$INFO_FILE" OUT_PORT || echo "-")
  
  echo -e "${CYAN}=========================================${RESET}"
  echo -e "   📡 MTG 代理管理面板 ${GREEN}${SCRIPT_VERSION}${RESET}"
  echo -e "${CYAN}=========================================${RESET}"
  echo -e "状态: $status"
  echo -e "地址: ${YELLOW}${ip}:${port}${RESET}"
  echo -e "${CYAN}-----------------------------------------${RESET}"
  echo -e "  ${GREEN}1.${RESET} 安装/重装"
  echo -e "  ${GREEN}2.${RESET} 查看信息"
  echo -e "  ${GREEN}3.${RESET} 修改配置"
  echo -e "  ${YELLOW}4.${RESET} 启动"
  echo -e "  ${YELLOW}5.${RESET} 停止"
  echo -e "  ${CYAN}6.${RESET} 重启"
  echo -e "  ${CYAN}7.${RESET} 查看日志"
  echo -e "  ${RED}8.${RESET} 卸载"
  echo -e "  ${GREEN}0.${RESET} 退出"
  echo -e "${CYAN}=========================================${RESET}"
  
  read -p "选择: " choice
  
  case "$choice" in
    1) install_mtp ;;
    2) view_info ;;
    3) modify_config ;;
    4) start_service mtg; pause_menu ;;
    5) stop_service mtg; pause_menu ;;
    6) start_service mtg; pause_menu ;;
    7) view_logs ;;
    8) uninstall_mtp ;;
    0) exit 0 ;;
    *) warn "输入错误"; sleep 1 ;;
  esac
done

EOFMTP

chmod +x /usr/local/bin/mtp
echo -e "${GREEN}✅ mtp 已安装到 /usr/local/bin/mtp${RESET}"
