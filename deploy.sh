#!/bin/bash
set -e

APP_NAME=$1
PROJECT_DIR="/home/ubuntu/CI-CD_deploy"
cd $PROJECT_DIR

# 1. Détecter la couleur actuellement active (blue ou green)
CURRENT=$(grep -oP "(?<=${APP_NAME}_)\w+(?=:80;)" nginx-proxy/conf.d/upstreams/${APP_NAME}_active.conf)
if [ "$CURRENT" == "blue" ]; then NEW="green"; else NEW="blue"; fi

echo ">>> Actif actuellement : ${APP_NAME}_${CURRENT} | Déploiement de : ${APP_NAME}_${NEW}"

# 2. Builder la nouvelle image et démarrer le nouveau conteneur (couleur inactive)
docker build -t ${APP_NAME}:latest ./${APP_NAME^}
docker rm -f ${APP_NAME}_${NEW} 2>/dev/null || true
docker run -d --name ${APP_NAME}_${NEW} --network ci-cd_deploy_webnet ${APP_NAME}:latest

# 3. Health check : on attend que le nouveau conteneur soit "healthy" (max 30s)
echo ">>> Vérification du health check..."
for i in {1..15}; do
  STATUS=$(docker inspect --format='{{.State.Health.Status}}' ${APP_NAME}_${NEW} 2>/dev/null || echo "starting")
  if [ "$STATUS" == "healthy" ]; then
    echo ">>> ${APP_NAME}_${NEW} est healthy !"
    break
  fi
  if [ $i -eq 15 ]; then
    echo "!!! Health check échoué, rollback : suppression du nouveau conteneur"
    docker rm -f ${APP_NAME}_${NEW}
    exit 1
  fi
  sleep 2
done

# 4. Bascule Nginx vers le nouveau conteneur
echo "set \$${APP_NAME}_upstream ${APP_NAME}_${NEW}:80;" > nginx-proxy/conf.d/upstreams/${APP_NAME}_active.conf
docker compose exec nginx-proxy nginx -s reload

# 5. Arrêter l'ancien conteneur (seulement maintenant, trafic déjà basculé)
sleep 12
docker rm -f ${APP_NAME}_${CURRENT} 2>/dev/null || true

echo ">>> Déploiement de ${APP_NAME} terminé sans interruption : ${CURRENT} → ${NEW}"
