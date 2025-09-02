#!/bin/bash

echo "📦 Arrêt du stack docker compose..."
docker compose down -v

echo "🗑️  Suppression des volumes orphelins..."
docker volume rm tp_grafana_data

echo "✅ Nettoyage terminé."