#!/bin/bash

# 一键安装 WireGuard 并生成配置文件的脚本
# 适用于 Debian 10
# 生成客户端配置、配置链接，并提供二维码

# 退出时如果发生错误
set -e

# 检查是否为 root 用户
if [[ $EUID -ne 0 ]]; then
    echo "请使用 root 用户运行此脚本"
    exit 1
fi

# 安装所需软件
apt update && apt install -y wireguard qrencode

# 生成 WireGuard 服务器私钥和公钥
wg genkey | tee /etc/wireguard/server_private.key | wg pubkey > /etc/wireguard/server_public.key

# 读取生成的私钥和公钥
SERVER_PRIVATE_KEY=$(cat /etc/wireguard/server_private.key)
SERVER_PUBLIC_KEY=$(cat /etc/wireguard/server_public.key)

# 定义网络接口和端口
WG_INTERFACE="wg0"
WG_PORT=51820
WG_IP="10.0.0.1/24"

# 生成 WireGuard 服务器配置
cat > /etc/wireguard/$WG_INTERFACE.conf <<EOL
[Interface]
Address = $WG_IP
ListenPort = $WG_PORT
PrivateKey = $SERVER_PRIVATE_KEY
SaveConfig = true
PostUp = iptables -A FORWARD -i $WG_INTERFACE -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i $WG_INTERFACE -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE
EOL

# 开启 IP 转发
echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
sysctl -p

# 启动 WireGuard 服务
systemctl enable wg-quick@$WG_INTERFACE
systemctl start wg-quick@$WG_INTERFACE

# 生成 WireGuard 客户端密钥
wg genkey | tee /etc/wireguard/client_private.key | wg pubkey > /etc/wireguard/client_public.key

# 读取客户端密钥
CLIENT_PRIVATE_KEY=$(cat /etc/wireguard/client_private.key)
CLIENT_PUBLIC_KEY=$(cat /etc/wireguard/client_public.key)

# 服务器 IP
SERVER_IP=$(curl -s ifconfig.me)

# 生成客户端配置文件
cat > /etc/wireguard/client.conf <<EOL
[Interface]
PrivateKey = $CLIENT_PRIVATE_KEY
Address = 10.0.0.2/24
DNS = 8.8.8.8

[Peer]
PublicKey = $SERVER_PUBLIC_KEY
Endpoint = $SERVER_IP:$WG_PORT
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
EOL

# 在服务器上添加客户端 Peer
wg set $WG_INTERFACE peer $CLIENT_PUBLIC_KEY allowed-ips 10.0.0.2/32

# 生成 Base64 编码的配置链接（适用于 WireGuard App）
CONFIG_LINK="wireguard://$(base64 -w 0 /etc/wireguard/client.conf)"
echo "配置链接: $CONFIG_LINK"

# 生成二维码以便扫描
qrencode -t ansiutf8 < /etc/wireguard/client.conf
echo "二维码已生成，可扫描导入 WireGuard"

# 完成
echo "WireGuard 安装完成！"
echo "客户端配置文件路径: /etc/wireguard/client.conf"
