FROM nginx:1.27-alpine

WORKDIR /scripts

COPY ops/nginx/default.conf /etc/nginx/conf.d/default.conf
COPY ops/nginx/start.sh /scripts/start.sh

RUN chmod +x /scripts/start.sh

CMD ["nginx", "-g", "daemon off;"]
