#!/bin/bash
set -euo pipefail

# Aller dans le répertoire où est ton docker-compose.yml
COMPOSE_FILE_DIR="$(dirname "$0")"

cd "$COMPOSE_FILE_DIR"

echo "📦 Arrêt du stack docker compose..."
docker compose down -v

echo "🗑️  Suppression des volumes orphelins..."
docker volume prune -f

echo "✅ Nettoyage terminé."