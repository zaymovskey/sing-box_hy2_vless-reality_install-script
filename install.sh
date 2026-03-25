#!/bin/bash

set -euo pipefail

echo "🚀 Установка sing-box..."

apt update
apt install -y curl unzip openssl

bash <(curl -fsSL https://sing-box.app/install.sh)

BIN_PATH="$(command -v sing-box)"

if [ -z "$BIN_PATH" ]; then
  echo "❌ sing-box не найден в PATH"
  exit 1
fi

echo "✅ sing-box найден: $BIN_PATH"
"$BIN_PATH" version

mkdir -p /etc/sing-box

echo "🔑 Генерация ключей Reality..."
KEYS="$("$BIN_PATH" generate reality-keypair)"
PRIVATE_KEY="$(echo "$KEYS" | grep PrivateKey | awk '{print $2}')"
PUBLIC_KEY="$(echo "$KEYS" | grep PublicKey | awk '{print $2}')"

if [ -z "$PRIVATE_KEY" ] || [ -z "$PUBLIC_KEY" ]; then
  echo "❌ Не удалось сгенерировать reality keys"
  exit 1
fi

echo "🧬 Генерация UUID..."
UUID="$(cat /proc/sys/kernel/random/uuid)"

SHORT_ID="$(openssl rand -hex 8)"
HY2_PASS="$(openssl rand -hex 8)"
OBFS_PASS="$(openssl rand -hex 8)"

echo "🔐 Генерация сертификата для Hysteria2..."
openssl req -x509 -nodes -newkey rsa:2048 \
  -keyout /etc/sing-box/hy2.key \
  -out /etc/sing-box/hy2.crt \
  -days 3650 \
  -subj "/CN=www.cloudflare.com"

chmod 600 /etc/sing-box/hy2.key
chmod 644 /etc/sing-box/hy2.crt

echo "⚙️ Создание конфига..."

cat > /etc/sing-box/config.json <<EOF
{
  "log": {
    "disabled": false,
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "hysteria2",
      "tag": "hy2-in",
      "listen": "::",
      "listen_port": 8443,
      "sniff": true,
      "sniff_override_destination": true,
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
      "ignore_client_bandwidth": false,
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
      "sniff": true,
      "sniff_override_destination": true,
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
    { "type": "direct", "tag": "direct" },
    { "type": "block", "tag": "block" }
  ],
  "route": {
    "final": "direct"
  }
}
EOF

echo "🧪 Проверка конфига..."
"$BIN_PATH" check -c /etc/sing-box/config.json

echo "🧩 Создание systemd сервиса..."

cat > /etc/systemd/system/sing-box.service <<EOF
[Unit]
Description=sing-box
After=network.target nss-lookup.target

[Service]
Type=simple
ExecStart=$BIN_PATH run -c /etc/sing-box/config.json
WorkingDirectory=/etc/sing-box
Restart=always
RestartSec=3
User=root
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

echo "🔄 Перезагрузка systemd..."
systemctl daemon-reexec
systemctl daemon-reload
systemctl enable sing-box
systemctl restart sing-box

echo "📡 Определение внешнего IP..."
IP="$(curl -4 -s ifconfig.me || true)"

if [ -z "$IP" ]; then
  IP="YOUR_SERVER_IP"
fi

echo ""
echo "===================="
echo "🔥 ГОТОВО"
echo "===================="
echo ""

echo "📄 Конфиг:"
echo "/etc/sing-box/config.json"
echo ""

echo "📡 VLESS Reality:"
echo "vless://$UUID@$IP:443?type=tcp&security=reality&encryption=none&pbk=$PUBLIC_KEY&fp=chrome&sni=www.cloudflare.com&sid=$SHORT_ID&spx=%2F#Reality"
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
echo ""

echo "📋 Полезные команды:"
echo "systemctl status sing-box"
echo "journalctl -u sing-box -f"
echo "ss -tulnp | grep -E '443|8443'"
