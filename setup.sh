#!/bin/bash

# setup.sh - Dokploy Docker Compose kurulum script'i

# Root kontrolü
if [ "$(id -u)" != "0" ]; then
    echo "Bu script root olarak çalıştırılmalıdır" >&2
    exit 1
fi

# Port kontrolü
check_port() {
    local port=$1
    if ss -tulnp | grep ":$port " >/dev/null; then
        echo "Hata: $port portu zaten kullanımda" >&2
        return 1
    fi
    return 0
}

# 80 ve 443 portlarını kontrol et
if ! check_port 80; then
    exit 1
fi

if ! check_port 443; then
    exit 1
fi

# Docker kontrolü
if ! command -v docker &> /dev/null; then
    echo "Docker kurulu değil. Docker'ı kurmak için:"
    echo "curl -sSL https://get.docker.com | sh"
    exit 1
fi

if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
    echo "Docker Compose kurulu değil."
    exit 1
fi

# IP adresini al
get_ip() {
    local ip=""

    # Önce private IP'yi dene
    ip=$(ip addr show | grep -E "inet (192\.168\.|10\.|172\.1[6-9]\.|172\.2[0-9]\.|172\.3[0-1]\.)" | head -n1 | awk '{print $2}' | cut -d/ -f1)

    # Private IP yoksa public IP'yi al
    if [ -z "$ip" ]; then
        ip=$(curl -4s --connect-timeout 5 https://ifconfig.io 2>/dev/null || \
             curl -4s --connect-timeout 5 https://icanhazip.com 2>/dev/null || \
             curl -4s --connect-timeout 5 https://ipecho.net/plain 2>/dev/null)
    fi

    echo "$ip"
}

# Dizinleri oluştur
echo "Gerekli dizinler oluşturuluyor..."
mkdir -p dokploy-data/traefik/dynamic
chmod 777 dokploy-data

# Traefik config dosyasını oluştur
if [ ! -f dokploy-data/traefik/traefik.yml ]; then
    echo "Traefik konfigürasyonu oluşturuluyor..."
    cat > dokploy-data/traefik/traefik.yml << 'EOF'
api:
  dashboard: true
  debug: true

entryPoints:
  web:
    address: ":80"
    http:
      redirections:
        entryPoint:
          to: websecure
          scheme: https
          permanent: true

  websecure:
    address: ":443"
    http3: {}
    http:
      tls:
        certResolver: letsencrypt

providers:
  docker:
    endpoint: "unix:///var/run/docker.sock"
    exposedByDefault: false
    network: dokploy-network

  file:
    directory: /etc/dokploy/traefik/dynamic
    watch: true

certificatesResolvers:
  letsencrypt:
    acme:
      email: admin@example.com
      storage: /etc/traefik/acme.json
      httpChallenge:
        entryPoint: web
EOF
fi

# .env dosyasını oluştur
if [ ! -f .env ]; then
    IP_ADDR=$(get_ip)
    echo "IP adresi tespit edildi: $IP_ADDR"
    echo "ADVERTISE_ADDR=$IP_ADDR" > .env
fi

# Docker Compose'u başlat
echo "Dokploy başlatılıyor..."
docker-compose up -d

# Sonuç mesajı
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
BLUE="\033[0;34m"
NC="\033[0m"

IP_ADDR=$(grep ADVERTISE_ADDR .env | cut -d= -f2)

echo ""
printf "${GREEN}Dokploy başarıyla kuruldu!${NC}\n"
printf "${BLUE}Servislerin başlaması için 15 saniye bekleyin${NC}\n"
printf "${YELLOW}Dokploy'a erişmek için: http://${IP_ADDR}:3000${NC}\n"
echo ""
echo "Servis durumunu kontrol etmek için: docker-compose ps"
echo "Logları görmek için: docker-compose logs -f"