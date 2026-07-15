FROM nginx:1.27-alpine

RUN rm -rf /usr/share/nginx/html/*

COPY . /usr/share/nginx/html

HEALTHCHECK --interval=5s --timeout=3s --start-period=5s --retries=3 \
  CMD wget -q --spider http://localhost/ || exit 1

EXPOSE 80
