#!/usr/bin/env bash

# Charger variables depuis ../.env
if [ ! -f "../.env" ]; then
  echo "❌ Fichier ../.env introuvable"
  exit 1
fi
export $(grep -v '^#' ../.env | xargs)

GRAFANA_URL="${GRAFANA_URL:-http://localhost:3000}"

# Vérifier jq et curl
if ! command -v jq >/dev/null || ! command -v curl >/dev/null; then
  echo "❌ jq et curl doivent être installés"
  exit 1
fi

# Vérifier le fichier users.json
if [ ! -f "users.json" ]; then
  echo "❌ users.json introuvable"
  exit 1
fi

# Fonction pour vérifier le code HTTP
check_response() {
  local code=$1
  local msg=$2
  if [ "$code" -ge 200 ] && [ "$code" -lt 300 ]; then
    echo "✅ $msg"
  elif [ "$code" -eq 412 ]; then
    echo "⚠️ $msg déjà existant"
  else
    echo "❌ Erreur $code pour $msg"
    exit 1
  fi
}

echo "🚀 Création du dossier formation-grafana..."

# 1️⃣ Vérifier/créer le dossier
folder_uid=$(curl -s -u "$GRAFANA_USER:$GRAFANA_PASSWORD" \
  "$GRAFANA_URL/api/folders" | jq -r '.[] | select(.title=="formation-grafana") | .uid')

if [ -z "$folder_uid" ]; then
  resp=$(curl -s -w "%{http_code}" -u "$GRAFANA_USER:$GRAFANA_PASSWORD" \
    -H "Content-Type: application/json" \
    -d '{"title":"formation-grafana"}' \
    "$GRAFANA_URL/api/folders")
  folder_uid=$(echo "$resp" | head -c -3 | jq -r '.uid')
  code=$(echo "$resp" | tail -c 3)
  check_response $code "Création du dossier formation-grafana"
else
  echo "ℹ️ Dossier existant : $folder_uid"
fi

echo "🚀 Création des teams..."

# Créer une team
create_team() {
  local name="$1"
  resp=$(curl -s -w "%{http_code}" -u "$GRAFANA_USER:$GRAFANA_PASSWORD" \
    -H "Content-Type: application/json" \
    -d "{\"name\":\"$name\"}" \
    "$GRAFANA_URL/api/teams")
  code=$(echo "$resp" | tail -c 3)
  check_response $code "Création team $name"
  echo "$resp" | head -c -3 | jq -r '.teamId'
}

admin_team_id=$(create_team "Admins")
users_team_id=$(create_team "Users")

echo "🚀 Création des utilisateurs et assignation aux teams..."

for row in $(jq -c '.[]' users.json); do
  name=$(echo "$row" | jq -r '.name')
  email=$(echo "$row" | jq -r '.email')
  login=$(echo "$row" | jq -r '.login')
  password=$(echo "$row" | jq -r '.password')
  role=$(echo "$row" | jq -r '.role')

  echo "➡️ Création utilisateur : $login ($role)"

  # Création utilisateur
  resp=$(curl -s -w "%{http_code}" -u "$GRAFANA_USER:$GRAFANA_PASSWORD" \
    -H "Content-Type: application/json" \
    -d "{\"name\":\"$name\",\"email\":\"$email\",\"login\":\"$login\",\"password\":\"$password\"}" \
    "$GRAFANA_URL/api/admin/users")
  code=$(echo "$resp" | tail -c 3)
  check_response $code "Utilisateur $login"

  # Récupérer l'ID de l'utilisateur
  user_id=$(curl -s -u "$GRAFANA_USER:$GRAFANA_PASSWORD" \
    "$GRAFANA_URL/api/users/lookup?loginOrEmail=$login" | jq '.id')

  if [ "$role" == "Admin" ]; then
    # Ajouter à la team Admins
    resp=$(curl -s -w "%{http_code}" -u "$GRAFANA_USER:$GRAFANA_PASSWORD" \
      -X POST -H "Content-Type: application/json" \
      -d "{\"userId\":$user_id}" \
      "$GRAFANA_URL/api/teams/$admin_team_id/members")
    code=$(echo "$resp" | tail -c 3)
    check_response $code "Ajout $login à Admins"
  else
    # Ajouter à la team Users
    resp=$(curl -s -w "%{http_code}" -u "$GRAFANA_USER:$GRAFANA_PASSWORD" \
      -X POST -H "Content-Type: application/json" \
      -d "{\"userId\":$user_id}" \
      "$GRAFANA_URL/api/teams/$users_team_id/members")
    code=$(echo "$resp" | tail -c 3)
    check_response $code "Ajout $login à Users"

    # Donner permissions Editor à la team sur le dossier
    resp=$(curl -s -w "%{http_code}" -u "$GRAFANA_USER:$GRAFANA_PASSWORD" \
      -X POST -H "Content-Type: application/json" \
      -d "[{\"role\":\"Editor\",\"teamId\":$users_team_id}]" \
      "$GRAFANA_URL/api/folders/$folder_uid/permissions")
    code=$(echo "$resp" | tail -c 3)
    check_response $code "Permissions Editor sur formation-grafana pour team Users"
  fi
done

echo "✅ Tous les utilisateurs et teams configurés avec permissions vérifiées."
