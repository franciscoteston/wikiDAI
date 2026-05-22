FROM linuxserver/bookstack:latest

USER root

RUN apk add --no-cache python3 py3-pip mariadb mariadb-client socat

WORKDIR /config/www

COPY start.sh /start.sh
COPY scripts/seed_bookstack.py /config/www/scripts/seed_bookstack.py
COPY seed/manual_banco_mercado.json /config/www/seed/manual_banco_mercado.json
COPY docs/estrutura-bookstack.md /config/www/docs/estrutura-bookstack.md

RUN chmod +x /start.sh /config/www/scripts/seed_bookstack.py

EXPOSE 7860

ENTRYPOINT ["/start.sh"]
