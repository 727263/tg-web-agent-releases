#!/bin/bash
# Telegram WEB 代理一键安装 / 更新（Linux amd64）。请用 root 运行。
#
# 首次安装：
#   curl -fsSL https://raw.githubusercontent.com/727263/tg-web-agent-releases/main/install.sh | bash -s -- --hostname proxy.example.com --email you@example.com
#
# 已安装过再执行同一条命令，只替换程序并重启，不改 config.yaml。
#
# 环境变量：HOSTNAME EMAIL PREFIX RELEASES_REPO
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "请用 root 运行" >&2
  exit 1
fi

hostname="${HOSTNAME:-}"
email="${EMAIL:-}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --hostname) hostname="$2"; shift 2 ;;
    --email) email="$2"; shift 2 ;;
    *) echo "未知参数 $1" >&2; exit 1 ;;
  esac
done

prefix="${PREFIX:-/opt/tg-web-agent}"
releases_repo="${RELEASES_REPO:-727263/tg-web-agent-releases}"
src="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || pwd)"

info() { echo "[INFO] $*" >&2; }

is_elf() {
  local f="$1"
  [[ -f "$f" ]] || return 1
  local magic
  magic="$(od -An -t x1 -N 4 "$f" | tr -d ' \n')"
  [[ "$magic" == "7f454c46" ]]
}

pick_bin() {
  local c
  for c in \
    "${src}/tg-web-agent" \
    "./tg-web-agent"
  do
    if is_elf "$c"; then
      echo "$c"
      return 0
    fi
  done
  return 1
}

download_bin() {
  local url="https://github.com/${releases_repo}/releases/latest/download/tg-web-agent"
  local tmp
  tmp="$(mktemp /tmp/tg-web-agent-XXXXXX)"
  info "下载程序：${url}"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL -o "${tmp}" "${url}" || { rm -f "${tmp}"; echo "下载失败" >&2; exit 1; }
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "${tmp}" "${url}" || { rm -f "${tmp}"; echo "下载失败" >&2; exit 1; }
  else
    echo "需要 curl 或 wget" >&2
    exit 1
  fi
  if ! is_elf "${tmp}"; then
    rm -f "${tmp}"
    echo "下载到的不是 Linux 程序" >&2
    exit 1
  fi
  echo "${tmp}"
}

install_bin() {
  local bin
  bin="$(pick_bin || true)"
  if [[ -z "${bin}" ]]; then
    bin="$(download_bin)"
  fi
  info "使用程序：${bin}"
  install -d -m 0755 "${prefix}"
  if [[ "$(readlink -f "${bin}" 2>/dev/null || echo "${bin}")" == "$(readlink -f "${prefix}/tg-web-agent" 2>/dev/null || echo "")" ]]; then
    chmod 0755 "${prefix}/tg-web-agent"
  else
    install -m 0755 "${bin}" "${prefix}/tg-web-agent"
  fi
  if [[ "${bin}" == /tmp/tg-web-agent-* ]]; then
    rm -f "${bin}"
  fi
}

write_unit() {
  cat > /etc/systemd/system/tg-web-agent.service <<EOF
[Unit]
Description=Telegram WEB proxy agent
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=${prefix}
Environment=TZ=Asia/Shanghai
ExecStartPre=${prefix}/firewall.sh
ExecStart=${prefix}/tg-web-agent -config ${prefix}/config.yaml
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
}

write_firewall() {
  cat > "${prefix}/firewall.sh" <<'EOF'
#!/bin/bash
set -euo pipefail
for port in 2398 8888; do
  iptables -C INPUT -p tcp --dport "$port" -j DROP 2>/dev/null || \
    iptables -I INPUT 1 -p tcp --dport "$port" -j DROP
  iptables -C INPUT -p tcp --dport "$port" -i lo -j ACCEPT 2>/dev/null || \
    iptables -I INPUT 1 -p tcp --dport "$port" -i lo -j ACCEPT
done
EOF
  chmod 0755 "${prefix}/firewall.sh"
}

if [[ ! -f "${prefix}/config.yaml" && ( -z "$hostname" || -z "$email" ) ]]; then
  echo "首次安装需要 --hostname 和 --email" >&2
  exit 1
fi

install_bin
write_firewall
write_unit

if [[ -f "${prefix}/config.yaml" ]]; then
  systemctl daemon-reload
  systemctl enable tg-web-agent
  systemctl restart tg-web-agent
  echo
  echo "已更新程序，配置文件没有改动。"
  echo "面板  http://服务器IP:9100/panel/"
  echo "配置  ${prefix}/config.yaml"
  exit 0
fi

secret="$(openssl rand -hex 16)"
panel_pass="$(openssl rand -hex 12)"

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y git build-essential libssl-dev zlib1g-dev curl ca-certificates iptables iproute2 openssl

if command -v timedatectl >/dev/null 2>&1; then
  timedatectl set-timezone Asia/Shanghai 2>/dev/null || true
fi

if ! id mtproxy >/dev/null 2>&1; then
  useradd --system --home-dir /etc/mtproxy --shell /usr/sbin/nologin mtproxy
fi
install -d -m 0755 /etc/mtproxy
fetch_mtproxy() {
  local url="$1" dest="$2" name="$3"
  if curl -fsSL --max-time 20 -o "${dest}" "${url}"; then
    return 0
  fi
  info "连不上 core.telegram.org，改从安装仓库下载 ${name}"
  curl -fsSL --max-time 30 -o "${dest}" \
    "https://raw.githubusercontent.com/${releases_repo}/main/mtproxy/${name}" \
    || { echo "下载 ${name} 失败" >&2; exit 1; }
}
fetch_mtproxy "https://core.telegram.org/getProxySecret" /etc/mtproxy/proxy-secret proxy-secret
fetch_mtproxy "https://core.telegram.org/getProxyConfig" /etc/mtproxy/proxy-multi.conf proxy-multi.conf
chmod 0644 /etc/mtproxy/proxy-secret /etc/mtproxy/proxy-multi.conf

if [[ ! -x /usr/local/bin/mtproxy ]]; then
  rm -rf /tmp/MTProxy
  git clone --depth 1 https://github.com/TelegramMessenger/MTProxy.git /tmp/MTProxy
  make -C /tmp/MTProxy
  if [[ -x /tmp/MTProxy/objs/bin/mtproto-proxy ]]; then
    install -m 0755 /tmp/MTProxy/objs/bin/mtproto-proxy /usr/local/bin/mtproxy
  elif [[ -x /tmp/MTProxy/objs/bin/mtproxy ]]; then
    install -m 0755 /tmp/MTProxy/objs/bin/mtproxy /usr/local/bin/mtproxy
  else
    echo "编译完成但没有找到 mtproto-proxy" >&2
    exit 1
  fi
fi

install -d -m 0755 "${prefix}/data/site" "${prefix}/data/acme"

local_ip="$(ip -4 route get 1.1.1.1 | awk '{for (i=1;i<=NF;i++) if ($i=="src") {print $(i+1); exit}}')"
public_ip="$(curl -4 -fsS --max-time 8 https://api.ipify.org || true)"
nat=""
if [[ -n "$local_ip" && -n "$public_ip" && "$local_ip" != "$public_ip" ]]; then
  nat="${local_ip}:${public_ip}"
fi

if [[ ! -f "${prefix}/data/site/index.html" ]]; then
  cat > "${prefix}/data/site/index.html" <<EOF
<!doctype html>
<meta charset="utf-8">
<title>${hostname}</title>
<h1>${hostname}</h1>
<p>Notes.</p>
EOF
fi

cat > "${prefix}/config.yaml" <<EOF
hostname: ${hostname}
secret_hex: ${secret}
acme_email: ${email}
acme_cache: ${prefix}/data/acme
tls_mode: autocert
listen_https: ":443"
listen_http: ":80"
backend: 127.0.0.1:2398
site_dir: ${prefix}/data/site
site_title: ${hostname}
site_theme: notes
domains: []
panel_listen: ":9100"
panel_user: admin
panel_pass: ${panel_pass}
mtproxy_bin: /usr/local/bin/mtproxy
mtproxy_user: mtproxy
mtproxy_secret_file: /etc/mtproxy/proxy-secret
mtproxy_config: /etc/mtproxy/proxy-multi.conf
mtproxy_nat: "${nat}"
mtproxy_tag: ""
mtproxy_port: 2398
mtproxy_stats_port: 8888
EOF
chmod 0600 "${prefix}/config.yaml"

systemctl daemon-reload
systemctl enable --now tg-web-agent

echo
echo "面板  http://服务器IP:9100/panel/"
echo "用户  admin"
echo "密码  ${panel_pass}"
echo "链接  https://t.me/webproxy?server=${hostname}&secret=${secret}"
echo "桌面版选 WEB，服务器填 ${hostname}，密钥填 ${secret}"
echo "把 data/site 换成你自己的网站，避免所有人用同一份页面。"
