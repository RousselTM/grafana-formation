#!/bin/bash

echo "📦 Arrêt du stack docker compose..."
docker compose down -v

echo "🗑️  Suppression des volumes orphelins..."
docker volume prune -f

echo "✅ Nettoyage terminé."