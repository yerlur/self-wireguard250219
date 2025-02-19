#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# 询问用户 WireGuard 端口号（默认 51820）
read -p "请输入 WireGuard 端口号（默认 51820）: " WG_PORT
WG_PORT=${WG_PORT:-51820}

# 询问用户使用的域名
read -p "请输入你购买的域名（如 vpn.example.com）: " WG_DOMAIN

# 安装必要的软件包
apt update && apt install -y wireguard qrencode fail2ban iptables

# 生成密钥对
mkdir -p /etc/wireguard
cd /etc/wireguard
umask 077
wg genkey | tee privatekey | wg pubkey > publickey

# 读取密钥
PRIVATE_KEY=$(cat privatekey)
PUBLIC_KEY=$(cat publickey)

# 生成 WireGuard 配置文件
cat > /etc/wireguard/wg0.conf <<EOF
[Interface]
Address = 10.0.0.1/24
ListenPort = $WG_PORT
PrivateKey = $PRIVATE_KEY
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE
EOF

# 启动并启用 WireGuard
wg-quick up wg0
systemctl enable wg-quick@wg0

# 生成客户端配置文件
CLIENT_PRIVATE_KEY=$(wg genkey)
CLIENT_PUBLIC_KEY=$(echo "$CLIENT_PRIVATE_KEY" | wg pubkey)

cat > /etc/wireguard/client.conf <<EOF
[Interface]
PrivateKey = $CLIENT_PRIVATE_KEY
Address = 10.0.0.2/24
DNS = 8.8.8.8

[Peer]
PublicKey = $PUBLIC_KEY
Endpoint = $WG_DOMAIN:$WG_PORT
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 21
EOF

# 在服务器添加客户端公钥
wg set wg0 peer $CLIENT_PUBLIC_KEY allowed-ips 10.0.0.2/32
systemctl restart wg-quick@wg0

# 生成二维码
qrencode -t ansiutf8 < /etc/wireguard/client.conf

# 设定 Fail2Ban 规则，自动封锁扫描端口的 IP
cat > /etc/fail2ban/jail.local <<EOF
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5

[sshd]
enabled = true

[wireguard]
enabled = true
port = $WG_PORT
filter = wireguard
action = iptables[name=WireGuard, port=$WG_PORT, protocol=udp]
logpath = /var/log/syslog
maxretry = 3
EOF

# 设定 iptables 规则，防止端口扫描
iptables -A INPUT -p udp --dport $WG_PORT -m recent --set --name WIREGUARD
iptables -A INPUT -p udp --dport $WG_PORT -m recent --update --seconds 60 --hitcount 4 --name WIREGUARD -j DROP

# 启动 Fail2Ban
systemctl restart fail2ban
systemctl enable fail2ban

# 显示 WireGuard 客户端配置链接
echo -e "${GREEN}WireGuard 客户端配置文件路径: /etc/wireguard/client.conf${NC}"
echo -e "${GREEN}扫描以下二维码以配置 WireGuard:${NC}"
qrencode -t ansiutf8 < /etc/wireguard/client.conf
