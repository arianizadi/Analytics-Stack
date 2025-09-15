#!/bin/bash
#
# This script automates the deployment of the analytics stack.
# It checks for dependencies, configures the environment, and starts the services.

set -e

# --- Helper Functions ---

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to generate a random secret
generate_secret() {
    openssl rand -hex 16
}

# --- Dependency Check ---

echo "Checking for dependencies..."

# Check for Docker
if ! command_exists docker; then
    echo "Docker is not installed. Please install Docker and run this script again."
    exit 1
fi

# Check for Docker Compose
if ! command_exists docker-compose; then
    echo "Docker Compose is not installed. Please install Docker Compose and run this script again."
    exit 1
fi

echo "All dependencies are satisfied."

# --- Configuration ---

echo "Starting configuration..."

# Prompt for email (needed for SSL certificates)
read -p "Enter your email address for SSL certificates: " EMAIL_ADDRESS

# Ask about access method
echo "How do you want to access your services?"
echo "1) Domain names with SSL (traditional setup)"
echo "2) IP addresses (direct access)"
echo "3) Cloudflare Tunnels (recommended for VPS)"
read -p "Choose option (1/2/3): " ACCESS_METHOD

case $ACCESS_METHOD in
    1)
        USE_DOMAINS="y"
        # Prompt for domain names
        read -p "Enter the domain for Grafana (e.g., grafana.yourdomain.com): " GRAFANA_DOMAIN
        read -p "Enter the domain for Umami (e.g., umami.yourdomain.com): " UMAMI_DOMAIN
        read -p "Enter the domain for Uptime Kuma (e.g., uptime.yourdomain.com): " UPTIME_KUMA_DOMAIN
        ;;
    2)
        USE_DOMAINS="n"
        # Get the server's public IP address
        echo "Detecting server IP address..."
        SERVER_IP=$(curl -s ifconfig.me || curl -s ipinfo.io/ip || echo "localhost")
        echo "Detected IP: $SERVER_IP"
        
        # Use IP addresses with different ports
        GRAFANA_DOMAIN="${SERVER_IP}:3000"
        UMAMI_DOMAIN="${SERVER_IP}:8081"
        UPTIME_KUMA_DOMAIN="${SERVER_IP}:3001"
        
        echo "Using IP addresses:"
        echo "  Grafana: http://$GRAFANA_DOMAIN"
        echo "  Umami: http://$UMAMI_DOMAIN"
        echo "  Uptime Kuma: http://$UPTIME_KUMA_DOMAIN"
        ;;
    3)
        USE_DOMAINS="n"
        USE_CLOUDFLARE_TUNNELS="y"
        # Use localhost with service names for Cloudflare Tunnels
        GRAFANA_DOMAIN="localhost:3000"
        UMAMI_DOMAIN="localhost:8081"
        UPTIME_KUMA_DOMAIN="localhost:3001"
        
        echo "Using Cloudflare Tunnels configuration:"
        echo "  Grafana: localhost:3000 (tunnel to grafana.yourdomain.com)"
        echo "  Umami: localhost:8081 (tunnel to umami.yourdomain.com)"
        echo "  Uptime Kuma: localhost:3001 (tunnel to uptime.yourdomain.com)"
        echo ""
        echo "Note: You'll need to configure your Cloudflare Tunnel to route:"
        echo "  grafana.yourdomain.com -> localhost:3000"
        echo "  umami.yourdomain.com -> localhost:8081"
        echo "  uptime.yourdomain.com -> localhost:3001"
        ;;
    *)
        echo "Invalid option. Using IP addresses as fallback."
        USE_DOMAINS="n"
        SERVER_IP=$(curl -s ifconfig.me || curl -s ipinfo.io/ip || echo "localhost")
        GRAFANA_DOMAIN="${SERVER_IP}:3000"
        UMAMI_DOMAIN="${SERVER_IP}:8081"
        UPTIME_KUMA_DOMAIN="${SERVER_IP}:3001"
        ;;
esac

# Ask about OpenReplay
read -p "Do you want to set up OpenReplay? (y/n): " SETUP_OPENREPLAY
if [[ "$SETUP_OPENREPLAY" == "y" || "$SETUP_OPENREPLAY" == "Y" ]]; then
    case $ACCESS_METHOD in
        1)
            read -p "Enter the domain for OpenReplay (e.g., openreplay.yourdomain.com): " OPENREPLAY_DOMAIN
            ;;
        2)
            OPENREPLAY_DOMAIN="${SERVER_IP}:8082"
            echo "OpenReplay will be available at: http://$OPENREPLAY_DOMAIN"
            ;;
        3)
            OPENREPLAY_DOMAIN="localhost:8082"
            echo "OpenReplay will be available at: localhost:8082 (tunnel to openreplay.yourdomain.com)"
            echo "Configure your Cloudflare Tunnel to route: openreplay.yourdomain.com -> localhost:8082"
            ;;
        *)
            OPENREPLAY_DOMAIN="${SERVER_IP}:8082"
            echo "OpenReplay will be available at: http://$OPENREPLAY_DOMAIN"
            ;;
    esac
fi

# Generate .env file
echo "Generating .env file..."

# Generate secrets
GF_SECURITY_ADMIN_PASSWORD=$(generate_secret)
UMAMI_APP_SECRET=$(generate_secret)
UMAMI_DB_PASS=$(generate_secret)

# Create .env file
cat > .env << EOL
# Global
TZ=America/Los_Angeles

# Grafana
GF_SECURITY_ADMIN_USER=admin
GF_SECURITY_ADMIN_PASSWORD=${GF_SECURITY_ADMIN_PASSWORD}

# Umami
UMAMI_APP_SECRET=${UMAMI_APP_SECRET}
UMAMI_DB_USER=umami
UMAMI_DB_PASS=${UMAMI_DB_PASS}

# Postgres (Umami)
POSTGRES_DB=umami
POSTGRES_USER=\${UMAMI_DB_USER}
POSTGRES_PASSWORD=\${UMAMI_DB_PASS}

# Uptime Kuma
UPTIME_KUMA_PORT=3001

# Loki
LOKI_RETENTION_PERIOD=168h   # 7 days (tune up)
EOL

echo ".env file created successfully."

# Create Caddyfile (only if not using Cloudflare Tunnels)
if [[ "$USE_CLOUDFLARE_TUNNELS" != "y" ]]; then
    echo "Creating Caddyfile..."
    
    if [[ "$USE_DOMAINS" == "y" || "$USE_DOMAINS" == "Y" ]]; then
        # Use domains with SSL
        cat > ./caddy/Caddyfile << EOL
{
    email ${EMAIL_ADDRESS}
}

${GRAFANA_DOMAIN} {
    reverse_proxy grafana:3000
}

${UMAMI_DOMAIN} {
    reverse_proxy umami:3000
}

${UPTIME_KUMA_DOMAIN} {
    reverse_proxy uptime-kuma:3001
}
EOL
    else
        # Use IP addresses without SSL (HTTP only)
        cat > ./caddy/Caddyfile << EOL
{
    auto_https off
}

${GRAFANA_DOMAIN} {
    reverse_proxy grafana:3000
}

${UMAMI_DOMAIN} {
    reverse_proxy umami:3000
}

${UPTIME_KUMA_DOMAIN} {
    reverse_proxy uptime-kuma:3001
}
EOL
    fi
else
    echo "Skipping Caddyfile creation (using Cloudflare Tunnels)"
fi

if [[ "$SETUP_OPENREPLAY" == "y" || "$SETUP_OPENREPLAY" == "Y" ]]; then
    # Add OpenReplay to Caddyfile only if not using Cloudflare Tunnels
    if [[ "$USE_CLOUDFLARE_TUNNELS" != "y" ]]; then
        cat >> ./caddy/Caddyfile << EOL

${OPENREPLAY_DOMAIN} {
    reverse_proxy openreplay-web:80
}
EOL
    fi

    # Generate OpenReplay .env file
    echo "Generating .env.openreplay file..."

    # Generate secrets
    OPENREPLAY_POSTGRES_PASSWORD=$(generate_secret)
    OPENREPLAY_MINIO_PASSWORD=$(generate_secret)

    # Create .env.openreplay file
    cat > ./openreplay/.env.openreplay << EOL
POSTGRES_PASSWORD=${OPENREPLAY_POSTGRES_PASSWORD}
MINIO_ROOT_PASSWORD=${OPENREPLAY_MINIO_PASSWORD}
EOL

    echo ".env.openreplay file created successfully."
fi

if [[ "$USE_CLOUDFLARE_TUNNELS" != "y" ]]; then
    echo "Caddyfile created successfully."
fi

# --- Deployment ---

echo "Modifying docker-compose.yml for deployment..."

# If using IP addresses or Cloudflare Tunnels, we need to expose ports directly
if [[ "$USE_DOMAINS" != "y" && "$USE_DOMAINS" != "Y" ]]; then
    if [[ "$USE_CLOUDFLARE_TUNNELS" == "y" ]]; then
        echo "Configuring services for Cloudflare Tunnels access..."
    else
        echo "Configuring services for IP-based access..."
    fi
    
    # Create a temporary docker-compose override file
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
        cat >> docker-compose.override.yml << EOL
  
  openreplay-web:
    ports:
      - "8082:80"
EOL
    fi
    
    if [[ "$USE_CLOUDFLARE_TUNNELS" == "y" ]]; then
        echo "Created docker-compose.override.yml for Cloudflare Tunnels access"
    else
        echo "Created docker-compose.override.yml for IP-based access"
    fi
fi

# Start the core stack
echo "Starting the core analytics stack..."
docker-compose up -d
echo "Core stack started successfully."

# Deploy OpenReplay if requested
if [[ "$SETUP_OPENREPLAY" == "y" || "$SETUP_OPENREPLAY" == "Y" ]]; then
    echo "Starting OpenReplay stack..."
    docker-compose -f ./openreplay/docker-compose.openreplay.yml --env-file ./openreplay/.env.openreplay up -d
    echo "OpenReplay stack started successfully."
fi

echo "Deployment complete!"
echo ""
echo "Your analytics stack is now running!"
echo ""
if [[ "$USE_CLOUDFLARE_TUNNELS" == "y" ]]; then
    echo "Services are running locally and ready for Cloudflare Tunnels:"
    echo "  Grafana: localhost:3000"
    echo "  Umami: localhost:8081"
    echo "  Uptime Kuma: localhost:3001"
    if [[ "$SETUP_OPENREPLAY" == "y" || "$SETUP_OPENREPLAY" == "Y" ]]; then
        echo "  OpenReplay: localhost:8082"
    fi
    echo ""
    echo "Configure your Cloudflare Tunnel to route:"
    echo "  grafana.yourdomain.com -> localhost:3000"
    echo "  umami.yourdomain.com -> localhost:8081"
    echo "  uptime.yourdomain.com -> localhost:3001"
    if [[ "$SETUP_OPENREPLAY" == "y" || "$SETUP_OPENREPLAY" == "Y" ]]; then
        echo "  openreplay.yourdomain.com -> localhost:8082"
    fi
elif [[ "$USE_DOMAINS" == "y" || "$USE_DOMAINS" == "Y" ]]; then
    echo "Access your services at:"
    echo "  Grafana: https://$GRAFANA_DOMAIN"
    echo "  Umami: https://$UMAMI_DOMAIN"
    echo "  Uptime Kuma: https://$UPTIME_KUMA_DOMAIN"
    if [[ "$SETUP_OPENREPLAY" == "y" || "$SETUP_OPENREPLAY" == "Y" ]]; then
        echo "  OpenReplay: https://$OPENREPLAY_DOMAIN"
    fi
else
    echo "Access your services at:"
    echo "  Grafana: http://$GRAFANA_DOMAIN"
    echo "  Umami: http://$UMAMI_DOMAIN"
    echo "  Uptime Kuma: http://$UPTIME_KUMA_DOMAIN"
    if [[ "$SETUP_OPENREPLAY" == "y" || "$SETUP_OPENREPLAY" == "Y" ]]; then
        echo "  OpenReplay: http://$OPENREPLAY_DOMAIN"
    fi
fi
echo ""
echo "Default Grafana credentials:"
echo "  Username: admin"
echo "  Password: (check your .env file)"
echo ""
echo "To stop the services, run: docker-compose down"
