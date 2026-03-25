#!/bin/bash

set -e

echo "🚀 Установка sing-box..."

apt update && apt install -y curl unzip openssl

bash <(curl -fsSL https://sing-box.app/install.sh)

mkdir -p /etc/sing-box

echo "🔑 Генерация ключей Reality..."
KEYS=$(sing-box generate reality-keypair)
PRIVATE_KEY=$(echo "$KEYS" | grep PrivateKey | awk '{print $2}')
PUBLIC_KEY=$(echo "$KEYS" | grep PublicKey | awk '{print $2}')

echo "🧬 Генерация UUID..."
UUID=$(cat /proc/sys/kernel/random/uuid)

SHORT_ID=$(openssl rand -hex 8)

HY2_PASS=$(openssl rand -hex 8)
OBFS_PASS=$(openssl rand -hex 8)

echo "🔐 Генерация сертификата..."
openssl req -x509 -nodes -newkey rsa:2048 \
-keyout /etc/sing-box/hy2.key \
-out /etc/sing-box/hy2.crt \
-days 3650 \
-subj "/CN=www.cloudflare.com"

echo "⚙️ Создание конфига..."

cat > /etc/sing-box/config.json <<EOF
{
  "log": {
    "level": "info"
  },
  "inbounds": [
    {
      "type": "hysteria2",
      "tag": "hy2-in",
      "listen": "::",
      "listen_port": 8443,
      "up_mbps": 100,
      "down_mbps": 100,
      "obfs": {
        "type": "salamander",
        "password": "$OBFS_PASS"
      },
      "users": [
        {
          "name": "user",
          "password": "$HY2_PASS"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "www.cloudflare.com",
        "certificate_path": "/etc/sing-box/hy2.crt",
        "key_path": "/etc/sing-box/hy2.key"
      }
    },
    {
      "type": "vless",
      "tag": "reality-in",
      "listen": "0.0.0.0",
      "listen_port": 443,
      "users": [
        {
          "uuid": "$UUID"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "www.cloudflare.com",
        "reality": {
          "enabled": true,
          "handshake": {
            "server": "www.cloudflare.com",
            "server_port": 443
          },
          "private_key": "$PRIVATE_KEY",
          "short_id": ["$SHORT_ID"]
        }
      }
    }
  ],
  "outbounds": [
    { "type": "direct" }
  ]
}
EOF

echo "🧩 Создание systemd сервиса..."

cat > /etc/systemd/system/sing-box.service <<EOF
[Unit]
Description=sing-box
After=network.target

[Service]
ExecStart=/usr/local/bin/sing-box run -c /etc/sing-box/config.json
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reexec
systemctl daemon-reload
systemctl enable sing-box
systemctl start sing-box

IP=$(curl -s ifconfig.me)

echo ""
echo "===================="
echo "🔥 ГОТОВО"
echo "===================="
echo ""

echo "📡 VLESS Reality:"
echo "vless://$UUID@$IP:443?type=tcp&security=reality&encryption=none&pbk=$PUBLIC_KEY&fp=chrome&sni=www.cloudflare.com&sid=$SHORT_ID#Reality"

echo ""
echo "⚡ Hysteria2:"
echo "hy2://$HY2_PASS@$IP:8443/?insecure=1&sni=www.cloudflare.com&obfs=salamander&obfs-password=$OBFS_PASS#HY2"

echo ""
echo "🧠 Сохрани эти данные:"
echo "UUID: $UUID"
echo "PublicKey: $PUBLIC_KEY"
echo "ShortID: $SHORT_ID"
echo "HY2 Password: $HY2_PASS"
echo "OBFS Password: $OBFS_PASS"
