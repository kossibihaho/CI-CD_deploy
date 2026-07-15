FROM nginx:1.27-alpine

# Supprime la config par défaut de Nginx
RUN rm -rf /usr/share/nginx/html/*

# Copie les fichiers statiques du template (index.html, assets/, vendor/...)
COPY . /usr/share/nginx/html

# Nginx doit pouvoir dire "je suis prêt" — on teste sa propre racine
HEALTHCHECK --interval=5s --timeout=3s --start-period=5s --retries=3 \
  CMD wget -q --spider http://localhost/ || exit 1

EXPOSE 80
