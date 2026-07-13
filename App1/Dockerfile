FROM nginx:1.27-alpine

# Supprime la config par défaut de Nginx
RUN rm -rf /usr/share/nginx/html/*

# Copie les fichiers statiques du template (index.html, assets/, vendor/...)
COPY . /usr/share/nginx/html

EXPOSE 80
