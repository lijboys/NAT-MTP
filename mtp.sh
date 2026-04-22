cat > /tmp/mtp_optimized.sh <<'EOFMTP'
#!/bin/bash

# 加载通用库
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh" || source /usr/local/bin/lib.sh || {
  echo "❌ 无法加载通用库"
  exit 1
}

SCRIPT_VERSION="v1.3.0"
MTG_VERSION="2.1.7"

CONFIG_FILE="/etc/mtg.toml"
INFO_FILE="/etc/mtg_info.txt"
SERVICE_FILE="/etc/systemd/system/mtg.service"
INIT_FILE="/etc/init.d/mtg"
LOG_FILE="/var/log/mtg.log"

[ "$EUID" -ne 0 ] && die "请使用 root 用户运行"

# ================= MTG 特定函数 =================

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
  local domain=$1
  /usr/local/bin/mtg generate-secret "$domain" 2>/dev/null
}

write_mtg_config() {
  local port=$1 secret=$2
  cat > "$CONFIG_FILE" <<EOF
secret = "${secret}"
bind-to = "0.0.0.0:${port}"
EOF
}

write_mtg_info() {
  local in_port=$1 public_ip=$2 out_port=$3 domain=$4 secret=$5
  local tg_link="tg://proxy?server=${public_ip}&port=${out_port}&secret=${secret}"
  cat > "$INFO_FILE" <<EOF
IN_PORT="${in_port}"
PUBLIC_IP="${public_ip}"
OUT_PORT="${out_port}"
FAKE_DOMAIN="${domain}"
SECRET="${secret}"
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

uninstall_mtp() {
  clear
  warn "即将卸载 MTG"
  read -p "确认？[y/N]: " confirm
  [[ "$confirm" != "y" && "$confirm" != "Y" ]] && return
  
  stop_service mtg
  rm -f /usr/local/bin/mtg "$CONFIG_FILE" "$INFO_FILE" "$SERVICE_FILE" "$INIT_FILE" /usr/local/bin/mtp
  systemctl daemon-reload 2>/dev/null
  info "卸载完成"
  sleep 2
  exit 0
}

# ================= 主菜单 =================

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
  echo -e "  ${YELLOW}4.${RESET} 启动"
  echo -e "  ${YELLOW}5.${RESET} 停止"
  echo -e "  ${CYAN}6.${RESET} 重启"
  echo -e "  ${RED}7.${RESET} 卸载"
  echo -e "  ${GREEN}0.${RESET} 退出"
  echo -e "${CYAN}=========================================${RESET}"
  
  read -p "选择: " choice
  
  case "$choice" in
    1) install_mtp ;;
    2) view_info ;;
    4) start_service mtg; pause_menu ;;
    5) stop_service mtg; pause_menu ;;
    6) start_service mtg; pause_menu ;;
    7) uninstall_mtp ;;
    0) exit 0 ;;
    *) warn "输入错误"; sleep 1 ;;
  esac
done

EOFMTP

chmod +x /tmp/mtp_optimized.sh
echo "mtp_optimized.sh 已创建"
