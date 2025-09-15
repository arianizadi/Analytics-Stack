#!/bin/bash
#
# This script completely cleans up the analytics stack deployment.
# It removes all containers, volumes, networks, and generated files.
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

echo "=========================================="
echo "Analytics Stack Cleanup Script"
echo "=========================================="
echo ""

# Check for Docker
if ! command_exists docker; then
    print_error "Docker is not installed. Nothing to clean up."
    exit 1
fi

# Check for Docker Compose
if ! command_exists docker-compose; then
    print_error "Docker Compose is not installed. Nothing to clean up."
    exit 1
fi

# Confirmation prompt
print_warning "This will completely remove:"
echo "  - All Docker containers (running and stopped)"
echo "  - All Docker volumes (data will be lost!)"
echo "  - All Docker networks"
echo "  - All generated configuration files"
echo "  - All SSL certificates"
echo "  - All environment files"
echo ""
read -p "Are you sure you want to continue? (yes/no): " CONFIRM

if [[ "$CONFIRM" != "yes" ]]; then
    print_status "Cleanup cancelled."
    exit 0
fi

echo ""
print_status "Starting cleanup process..."

# --- Stop and Remove Containers ---
print_status "Stopping and removing containers..."

# Stop main stack
if [ -f "docker-compose.yml" ]; then
    print_status "Stopping main analytics stack..."
    docker-compose down --remove-orphans 2>/dev/null || true
fi

# Stop OpenReplay stack
if [ -f "openreplay/docker-compose.openreplay.yml" ]; then
    print_status "Stopping OpenReplay stack..."
    docker-compose -f ./openreplay/docker-compose.openreplay.yml down --remove-orphans 2>/dev/null || true
fi

# Stop any remaining containers by name
CONTAINERS=(
    "pg-umami"
    "umami"
    "loki"
    "promtail"
    "prometheus"
    "node-exporter"
    "cadvisor"
    "grafana"
    "uptime-kuma"
    "caddy"
    "openreplay-web"
    "zookeeper"
    "kafka"
    "redis"
    "postgres"
    "clickhouse"
    "minio"
    "ingester"
    "api"
    "web"
)

for container in "${CONTAINERS[@]}"; do
    if docker ps -a --format "table {{.Names}}" | grep -q "^${container}$"; then
        print_status "Removing container: $container"
        docker rm -f "$container" 2>/dev/null || true
    fi
done

# --- Remove Volumes ---
print_status "Removing Docker volumes..."

VOLUMES=(
    "analytics-stack_pgdata"
    "analytics-stack_prom-data"
    "analytics-stack_grafana-data"
    "analytics-stack_loki-data"
    "analytics-stack_kuma-data"
    "analytics-stack_caddy-data"
    "analytics-stack_caddy-config"
    "openreplay_or-pg"
    "openreplay_or-ch"
    "openreplay_or-minio"
    "pgdata"
    "prom-data"
    "grafana-data"
    "loki-data"
    "kuma-data"
    "caddy-data"
    "caddy-config"
    "or-pg"
    "or-ch"
    "or-minio"
)

for volume in "${VOLUMES[@]}"; do
    if docker volume ls --format "table {{.Name}}" | grep -q "^${volume}$"; then
        print_status "Removing volume: $volume"
        docker volume rm "$volume" 2>/dev/null || true
    fi
done

# Remove any volumes with analytics-stack prefix
print_status "Removing any remaining analytics-stack volumes..."
docker volume ls --format "table {{.Name}}" | grep "analytics-stack" | while read -r volume; do
    if [ ! -z "$volume" ]; then
        print_status "Removing volume: $volume"
        docker volume rm "$volume" 2>/dev/null || true
    fi
done

# --- Remove Networks ---
print_status "Removing Docker networks..."

NETWORKS=(
    "analytics-stack_default"
    "openreplay_default"
    "analytics-stack"
    "openreplay"
)

for network in "${NETWORKS[@]}"; do
    if docker network ls --format "table {{.Name}}" | grep -q "^${network}$"; then
        print_status "Removing network: $network"
        docker network rm "$network" 2>/dev/null || true
    fi
done

# --- Remove Generated Files ---
print_status "Removing generated configuration files..."

# Remove .env files
FILES_TO_REMOVE=(
    ".env"
    "openreplay/.env.openreplay"
    "docker-compose.override.yml"
    "caddy/Caddyfile"
)

for file in "${FILES_TO_REMOVE[@]}"; do
    if [ -f "$file" ]; then
        print_status "Removing file: $file"
        rm -f "$file"
    fi
done

# --- Clean up Docker system ---
print_status "Cleaning up Docker system..."

# Remove unused images
print_status "Removing unused Docker images..."
docker image prune -f 2>/dev/null || true

# Remove unused networks
print_status "Removing unused Docker networks..."
docker network prune -f 2>/dev/null || true

# Remove unused volumes
print_status "Removing unused Docker volumes..."
docker volume prune -f 2>/dev/null || true

# Remove build cache
print_status "Removing Docker build cache..."
docker builder prune -f 2>/dev/null || true

# --- Verify Cleanup ---
print_status "Verifying cleanup..."

# Check for remaining containers
REMAINING_CONTAINERS=$(docker ps -a --format "table {{.Names}}" | grep -E "(pg-umami|umami|loki|promtail|prometheus|node-exporter|cadvisor|grafana|uptime-kuma|caddy|openreplay|zookeeper|kafka|redis|clickhouse|minio|ingester|api|web)" | wc -l)

if [ "$REMAINING_CONTAINERS" -gt 0 ]; then
    print_warning "Some containers may still exist:"
    docker ps -a --format "table {{.Names}}" | grep -E "(pg-umami|umami|loki|promtail|prometheus|node-exporter|cadvisor|grafana|uptime-kuma|caddy|openreplay|zookeeper|kafka|redis|clickhouse|minio|ingester|api|web)" || true
else
    print_success "All analytics stack containers removed."
fi

# Check for remaining volumes
REMAINING_VOLUMES=$(docker volume ls --format "table {{.Name}}" | grep -E "(analytics-stack|openreplay|pgdata|prom-data|grafana-data|loki-data|kuma-data|caddy-data|or-pg|or-ch|or-minio)" | wc -l)

if [ "$REMAINING_VOLUMES" -gt 0 ]; then
    print_warning "Some volumes may still exist:"
    docker volume ls --format "table {{.Name}}" | grep -E "(analytics-stack|openreplay|pgdata|prom-data|grafana-data|loki-data|kuma-data|caddy-data|or-pg|or-ch|or-minio)" || true
else
    print_success "All analytics stack volumes removed."
fi

# Check for remaining networks
REMAINING_NETWORKS=$(docker network ls --format "table {{.Name}}" | grep -E "(analytics-stack|openreplay)" | wc -l)

if [ "$REMAINING_NETWORKS" -gt 0 ]; then
    print_warning "Some networks may still exist:"
    docker network ls --format "table {{.Name}}" | grep -E "(analytics-stack|openreplay)" || true
else
    print_success "All analytics stack networks removed."
fi

# Check for remaining files
REMAINING_FILES=0
for file in "${FILES_TO_REMOVE[@]}"; do
    if [ -f "$file" ]; then
        REMAINING_FILES=$((REMAINING_FILES + 1))
    fi
done

if [ "$REMAINING_FILES" -gt 0 ]; then
    print_warning "Some configuration files may still exist:"
    for file in "${FILES_TO_REMOVE[@]}"; do
        if [ -f "$file" ]; then
            echo "  - $file"
        fi
    done
else
    print_success "All generated configuration files removed."
fi

echo ""
echo "=========================================="
print_success "Cleanup completed!"
echo "=========================================="
echo ""
print_status "Summary:"
echo "  - All Docker containers stopped and removed"
echo "  - All Docker volumes removed (data lost)"
echo "  - All Docker networks removed"
echo "  - All generated configuration files removed"
echo "  - Docker system cleaned up"
echo ""
print_status "You can now run ./deploy.sh to start fresh."
echo ""
