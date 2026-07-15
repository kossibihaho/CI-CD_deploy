#!/bin/bash
set -e

APP_NAME=$1
PROJECT_DIR="/home/ubuntu/CI-CD_deploy"
cd $PROJECT_DIR

# Associer chaque app à son domaine, pour la vérification finale
case $APP_NAME in
  app1) DOMAIN="kossiapp.duckdns.org" ;;
  app2) DOMAIN="kossiapp2.duckdns.org" ;;
  *) echo "!!! Application inconnue : $APP_NAME"; exit 1 ;;
esac

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

# 4bis. Vérification finale via le domaine public, avec retry
#       (le cache DNS interne de Nginx - resolver valid=10s - peut encore
#       pointer vers l'ancien conteneur juste après le reload, donc on
#       retente plusieurs fois avant de considérer que la bascule est OK)
echo ">>> Vérification finale via https://${DOMAIN}..."
for i in {1..6}; do
  CODE=$(curl -s -o /dev/null -w "%{http_code}" https://${DOMAIN})
  echo "    Tentative $i : HTTP $CODE"
  if [ "$CODE" == "200" ]; then
    echo ">>> Bascule confirmée, ${DOMAIN} répond correctement."
    break
  fi
  if [ $i -eq 6 ]; then
    echo "!!! ${DOMAIN} ne répond toujours pas après la bascule, rollback"
    echo "set \$${APP_NAME}_upstream ${APP_NAME}_${CURRENT}:80;" > nginx-proxy/conf.d/upstreams/${APP_NAME}_active.conf
    docker compose exec nginx-proxy nginx -s reload
    docker rm -f ${APP_NAME}_${NEW}
    exit 1
  fi
  sleep 2
done

# 5. Arrêter l'ancien conteneur (seulement maintenant, trafic déjà basculé
#    ET confirmé stable — délai supérieur au "valid=10s" du resolver Nginx
#    pour éviter que le cache DNS pointe encore vers un conteneur supprimé)
sleep 12
docker rm -f ${APP_NAME}_${CURRENT} 2>/dev/null || true

echo ">>> Déploiement de ${APP_NAME} terminé sans interruption : ${CURRENT} → ${NEW}"
