#!/usr/bin/env bash
set -euo pipefail

# Charger les variables d'environnement depuis le .env du dossier parent
if [ -f ../.env ]; then
  export $(grep -v '^#' ../.env | xargs)
else
  echo "❌ Fichier ../.env introuvable"
  exit 1
fi

# Variables Grafana depuis .env
GRAFANA_URL="${GRAFANA_URL:-http://localhost:3000}"
GRAFANA_ADMIN_USER="${GRAFANA_ADMIN_USER:-admin}"
GRAFANA_ADMIN_PASSWORD="${GRAFANA_ADMIN_PASSWORD:-admin}"

AUTH="-u ${GRAFANA_ADMIN_USER}:${GRAFANA_ADMIN_PASSWORD}"

# JSON contenant les utilisateurs
USERS_JSON="users.json"

if [ ! -f "$USERS_JSON" ]; then
  echo "❌ Fichier $USERS_JSON introuvable"
  exit 1
fi

# Fonction : créer un dossier s'il n'existe pas
create_folder() {
  local folder_name="$1"
  folder_id=$(curl -s $AUTH "${GRAFANA_URL}/api/folders" | jq -r ".[] | select(.title==\"$folder_name\") | .id")

  if [ -z "$folder_id" ]; then
    echo "📁 Création du dossier : $folder_name"
    folder_id=$(curl -s -X POST $AUTH \
      -H "Content-Type: application/json" \
      -d "{\"title\":\"$folder_name\"}" \
      "${GRAFANA_URL}/api/folders" | jq -r '.id')
  fi

  echo "$folder_id"
}

# Vérifier et créer les dossiers nécessaires
declare -A FOLDER_IDS
for folder in grafana-correction grafana-formation; do
  FOLDER_IDS[$folder]=$(create_folder "$folder")
done

# Créer les utilisateurs et gérer les permissions
jq -c '.[]' "$USERS_JSON" | while read -r user; do
  name=$(echo "$user" | jq -r '.name')
  email=$(echo "$user" | jq -r '.email')
  login=$(echo "$user" | jq -r '.login')
  password=$(echo "$user" | jq -r '.password')
  role=$(echo "$user" | jq -r '.role // empty')

  echo "👤 Création utilisateur : $login"

  # Vérifier si l'utilisateur existe déjà
  user_id=$(curl -s $AUTH "${GRAFANA_URL}/api/users/lookup?loginOrEmail=$login" | jq -r '.id // empty')

  if [ -z "$user_id" ]; then
    user_id=$(curl -s -X POST $AUTH \
      -H "Content-Type: application/json" \
      -d "{\"name\":\"$name\",\"email\":\"$email\",\"login\":\"$login\",\"password\":\"$password\"}" \
      "${GRAFANA_URL}/api/admin/users" | jq -r '.id')
  fi

  # Si Admin -> mettre le rôle global Admin
  if [ "$role" == "Admin" ]; then
    echo "⚙️ Attribution rôle Admin à $login"
    curl -s -X PATCH $AUTH \
      -H "Content-Type: application/json" \
      -d '{"isGrafanaAdmin": true}' \
      "${GRAFANA_URL}/api/admin/users/$user_id" >/dev/null
  fi

  # Si user avec dossiers
  if echo "$user" | jq -e '.folder' >/dev/null; then
    for row in $(echo "$user" | jq -c '.folder[]'); do
      folder_name=$(echo "$row" | jq -r '.folder')
      folder_role=$(echo "$row" | jq -r '.role')

      # Mapper les rôles Grafana
      case "$folder_role" in
        Reader) perm="Viewer" ;;
        Editor) perm="Editor" ;;
        Admin) perm="Admin" ;;
        *) perm="Viewer" ;;
      esac

      folder_uid=$(curl -s $AUTH "${GRAFANA_URL}/api/folders" | jq -r ".[] | select(.title==\"$folder_name\") | .uid")

      echo "📂 Attribution $perm sur dossier $folder_name à $login"

      curl -s -X POST $AUTH \
        -H "Content-Type: application/json" \
        -d "{\"items\":[{\"userId\":$user_id,\"permission\":\"$perm\"}]}" \
        "${GRAFANA_URL}/api/folders/$folder_uid/permissions" >/dev/null
    done
  fi
done

echo "✅ Provisioning terminé."
