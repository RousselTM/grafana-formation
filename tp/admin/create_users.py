import json
import os
import requests
from dotenv import load_dotenv

# Charger les variables depuis .env
load_dotenv()
grafana_user = os.getenv("GRAFANA_USER")
grafana_password = os.getenv("GRAFANA_PASSWORD")
grafana_url = os.getenv("GRAFANA_URL", "http://localhost:3000")

# Charger les utilisateurs
with open("users.json") as f:
    users = json.load(f)

# Création des utilisateurs
for user in users:
    payload = {
        "name": user["name"],
        "email": user["email"],
        "login": user["login"],
        "password": user["password"]
    }
    r = requests.post(
        f"{grafana_url}/api/admin/users",
        auth=(grafana_user, grafana_password),
        json=payload
    )
    if r.status_code == 200:
        print(f"✅ Utilisateur créé : {user['login']} ({user['role']})")
    elif r.status_code == 412:
        print(f"⚠️ Utilisateur {user['login']} existe déjà")
    else:
        print(f"❌ Erreur pour {user['login']}: {r.text}")

    # Ajouter rôle dans l'organisation (Admin ou Editor)
    role = user["role"]
    assign_payload = {
        "loginOrEmail": user["login"],
        "role": role
    }
    r2 = requests.post(
        f"{grafana_url}/api/orgs/1/users",
        auth=(grafana_user, grafana_password),
        json=assign_payload
    )
    if r2.status_code == 200:
        print(f"   ➡️ Rôle {role} assigné")
    else:
        print(f"   ⚠️ Erreur assignation rôle: {r2.text}")
