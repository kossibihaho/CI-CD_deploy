# CI-CD_deploy

Infrastructure cloud complète, construite de A à Z sur un serveur vierge (AWS EC2) : conteneurisation, reverse proxy, HTTPS automatisé, déploiement zero-downtime et pipeline CI/CD.



# 🏗️ Architecture
```
Internet
   │
   ▼
[nginx-proxy] :80/:443  ← seul conteneur exposé publiquement
   │
   ├──► app1_blue|green:80  (réseau interne Docker)
   └──► app2_blue|green:80  (réseau interne Docker)

[certbot] ── renouvelle les certificats et recharge Nginx automatiquement
```

- Un seul point d'entrée public (Nginx), les applications ne sont jamais exposées directement.
- Routage par sous-domaine (`server_name`).
- Bascule Blue-Green : deux versions d'une même app coexistent le temps de la mise à jour, sans coupure.




# 🧱 Stack technique

| Domaine | Technologies |
|---|---|
| Serveur | AWS EC2 (Ubuntu), SSH par clé |
| Conteneurisation | Docker, Docker Compose |
| Reverse proxy | Nginx (routage dynamique via variables) |
| HTTPS | Let's Encrypt, Certbot (challenge HTTP-01), renouvellement auto |
| DNS | DuckDNS (sous-domaines dynamiques) |
| CI/CD | GitHub Actions (build → test → deploy → monitoring) |
| Déploiement | Blue-Green, health checks, rollback automatique |





# 🚀 Installation (serveur vierge)

```bash
# 1. Prérequis sur l'hôte : uniquement Docker + Docker Compose
sudo apt update
sudo apt install -y docker.io docker-compose-plugin
sudo systemctl enable --now docker
sudo usermod -aG docker $USER

# 2. Cloner le repo
git clone https://github.com/kossibihaho/CI-CD_deploy.git
cd CI-CD_deploy

# 3. Lancer l'infrastructure
docker compose up -d --build
```



⚠️ Ouvrir les ports **22, 80, 443** dans le Security Group EC2.

## 🔒 Obtenir les certificats HTTPS (première fois uniquement)

```bash
docker compose run --rm --entrypoint "certbot" certbot certonly \
  --webroot -w /var/www/certbot \
  -d kossiapp.duckdns.org \
  --email votre@email.com --agree-tos --no-eff-email

docker compose run --rm --entrypoint "certbot" certbot certonly \
  --webroot -w /var/www/certbot \
  -d kossiapp2.duckdns.org \
  --email votre@email.com --agree-tos --no-eff-email
```

Puis recharger Nginx :
```bash
docker compose exec nginx-proxy nginx -s reload
```

# 🔵🟢 Déploiement Blue-Green

Le script `deploy.sh` bascule une application vers sa nouvelle version sans interruption :

```bash
./deploy.sh app1   # ou app2
```

Étapes réalisées automatiquement :
1. Build de la nouvelle image
2. Démarrage du nouveau conteneur (couleur inactive)
3. Attente du health check (`healthy`)
4. Bascule du routage Nginx (`nginx -s reload`)
5. Vérification finale via le domaine public (avec retry + rollback automatique si échec)
6. Suppression de l'ancien conteneur

## ⚙️ Pipeline CI/CD (GitHub Actions)

Déclenché à chaque `push` sur `master` :

```
build → test → deploy (blue-green) → monitoring
```

**Secrets requis** (Settings → Secrets and variables → Actions) :

| Secret | Description |
|---|---|
| `EC2_HOST` | IP publique / Elastic IP de l'EC2 |
| `EC2_USER` | Utilisateur SSH (`ubuntu`) |
| `EC2_SSH_KEY` | Clé privée SSH dédiée au déploiement |
| `EC2_PROJECT_PATH` | Chemin du projet sur l'EC2 |



## 🛠️ Commandes utiles

```bash
docker compose ps                          # état des conteneurs
docker compose logs nginx-proxy --tail 30  # logs Nginx
docker compose exec nginx-proxy nginx -t   # valider la config Nginx
docker compose run --rm certbot certificates  # lister les certificats
```

## ⚠️ Points de vigilance connus

- **Elastic IP recommandée** : sans elle, l'IP publique EC2 change au redémarrage et désynchronise DuckDNS.
- **Resolver Nginx** : `resolver 127.0.0.11 valid=10s ipv6=off;` — l'IPv6 doit être désactivé pour éviter des échecs de résolution DNS interne.
- **Délai avant suppression de l'ancien conteneur** (`sleep 12` dans `deploy.sh`) : doit toujours être supérieur au `valid=` du resolver, pour éviter un `502` dû à un cache DNS pointant vers un conteneur déjà supprimé.
- **Renouvellement Certbot** : le `--deploy-hook` recharge Nginx automatiquement après chaque renouvellement réel.

