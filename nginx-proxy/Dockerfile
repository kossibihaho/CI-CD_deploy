FROM nginx:1.27-alpine

RUN rm /etc/nginx/conf.d/default.conf
COPY conf.d/ /etc/nginx/conf.d/

EXPOSE 80 443
