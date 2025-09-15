#!/bin/bash

set -e

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

generate_secret() {
    openssl rand -hex 16
}

echo "Checking for dependencies..."

if ! command_exists docker; then
    echo "Docker is not installed. Please install Docker and run this script again."
    exit 1
fi

if ! command_exists docker-compose; then
    echo "Docker Compose is not installed. Please install Docker Compose and run this script again."
    exit 1
fi

echo "All dependencies are satisfied."

echo "Starting configuration..."

echo "Configuring for Cloudflare Tunnels access..."

echo "Detecting server internal IP address..."
INTERNAL_IP=$(hostname -I | awk '{print $1}' || ip route get 1 | awk '{print $7; exit}' || echo "localhost")
echo "Detected internal IP: $INTERNAL_IP"

GRAFANA_DOMAIN="${INTERNAL_IP}:3000"
UMAMI_DOMAIN="${INTERNAL_IP}:8081"
UPTIME_KUMA_DOMAIN="${INTERNAL_IP}:3001"

echo "Using Cloudflare Tunnels configuration:"
echo "  Grafana: ${INTERNAL_IP}:3000 (tunnel to grafana.yourdomain.com)"
echo "  Umami: ${INTERNAL_IP}:8081 (tunnel to umami.yourdomain.com)"
echo "  Uptime Kuma: ${INTERNAL_IP}:3001 (tunnel to uptime.yourdomain.com)"
echo ""
echo "Note: You'll need to configure your Cloudflare Tunnel to route:"
echo "  grafana.yourdomain.com -> ${INTERNAL_IP}:3000"
echo "  umami.yourdomain.com -> ${INTERNAL_IP}:8081"
echo "  uptime.yourdomain.com -> ${INTERNAL_IP}:3001"

read -p "Do you want to set up OpenReplay? (y/n): " SETUP_OPENREPLAY
if [[ "$SETUP_OPENREPLAY" == "y" || "$SETUP_OPENREPLAY" == "Y" ]]; then
    OPENREPLAY_DOMAIN="${INTERNAL_IP}:8082"
    echo "OpenReplay will be available at: ${INTERNAL_IP}:8082 (tunnel to openreplay.yourdomain.com)"
    echo "Configure your Cloudflare Tunnel to route: openreplay.yourdomain.com -> ${INTERNAL_IP}:8082"
fi

echo "Generating .env file..."

GF_SECURITY_ADMIN_PASSWORD=$(generate_secret)
UMAMI_APP_SECRET=$(generate_secret)
UMAMI_DB_PASS=$(generate_secret)

cat > .env << EOL
TZ=America/Los_Angeles

GF_SECURITY_ADMIN_USER=admin
GF_SECURITY_ADMIN_PASSWORD=${GF_SECURITY_ADMIN_PASSWORD}

UMAMI_APP_SECRET=${UMAMI_APP_SECRET}
UMAMI_DB_USER=umami
UMAMI_DB_PASS=${UMAMI_DB_PASS}

POSTGRES_DB=umami
POSTGRES_USER=\${UMAMI_DB_USER}
POSTGRES_PASSWORD=\${UMAMI_DB_PASS}

UPTIME_KUMA_PORT=3001

LOKI_RETENTION_PERIOD=168h
EOL

echo ".env file created successfully."

if [[ "$SETUP_OPENREPLAY" == "y" || "$SETUP_OPENREPLAY" == "Y" ]]; then
    echo "Generating .env.openreplay file..."

    OPENREPLAY_POSTGRES_PASSWORD=$(generate_secret)
    OPENREPLAY_MINIO_PASSWORD=$(generate_secret)

    cat > ./openreplay/.env.openreplay << EOL
POSTGRES_PASSWORD=${OPENREPLAY_POSTGRES_PASSWORD}
MINIO_ROOT_PASSWORD=${OPENREPLAY_MINIO_PASSWORD}
EOL

    echo ".env.openreplay file created successfully."
fi

echo "Configuring services for Cloudflare Tunnels access..."

cat > docker-compose.override.yml << EOL
version: "3.9"
services:
  umami:
    ports:
      - "8081:3000"
  
  grafana:
    ports:
      - "3000:3000"
  
  uptime-kuma:
    ports:
      - "3001:3001"
EOL

if [[ "$SETUP_OPENREPLAY" == "y" || "$SETUP_OPENREPLAY" == "Y" ]]; then
    echo "OpenReplay will be started separately with its own compose file"
fi

echo "Created docker-compose.override.yml for Cloudflare Tunnels access"

echo "Starting the core analytics stack..."
docker-compose up -d
echo "Core stack started successfully."

if [[ "$SETUP_OPENREPLAY" == "y" || "$SETUP_OPENREPLAY" == "Y" ]]; then
    echo "Starting OpenReplay stack..."
    docker-compose -f ./openreplay/docker-compose.openreplay.yml --env-file ./openreplay/.env.openreplay up -d
    echo "OpenReplay stack started successfully."
fi

echo "Deployment complete!"
echo ""
echo "Your analytics stack is now running!"
echo ""
echo "Services are running locally and ready for Cloudflare Tunnels:"
echo "  Grafana: ${INTERNAL_IP}:3000"
echo "  Umami: ${INTERNAL_IP}:8081"
echo "  Uptime Kuma: ${INTERNAL_IP}:3001"
if [[ "$SETUP_OPENREPLAY" == "y" || "$SETUP_OPENREPLAY" == "Y" ]]; then
    echo "  OpenReplay: ${INTERNAL_IP}:8082"
fi
echo ""
echo "Configure your Cloudflare Tunnel to route:"
echo "  grafana.yourdomain.com -> ${INTERNAL_IP}:3000"
echo "  umami.yourdomain.com -> ${INTERNAL_IP}:8081"
echo "  uptime.yourdomain.com -> ${INTERNAL_IP}:3001"
if [[ "$SETUP_OPENREPLAY" == "y" || "$SETUP_OPENREPLAY" == "Y" ]]; then
    echo "  openreplay.yourdomain.com -> ${INTERNAL_IP}:8082"
fi
echo ""
echo "Default Grafana credentials:"
echo "  Username: admin"
echo "  Password: (check your .env file)"
echo ""
echo "To stop the services, run: docker-compose down"