FROM --platform=linux/amd64 lucee/lucee:8.0.0.156-SNAPSHOT-nginx-amd64

ENV LUCEE_ADMIN_ENABLED=false

RUN mkdir -p /var/www
COPY www/ /var/www/

COPY lucee-config.json /opt/lucee/server/lucee-server/context/.CFConfig.json
COPY Server.cfc /opt/lucee/server/lucee-server/context/context/Server.cfc


RUN mkdir -p /var/www/logs \
  && ln -sf /proc/1/fd/1 /opt/lucee/server/lucee-server/context/logs/application.log \
  && ln -sf /proc/1/fd/1 /opt/lucee/server/lucee-server/context/logs/exception.log

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=30s --start-period=30s --retries=3 \
  CMD sh -c 'curl -fsS "http://127.0.0.1:${PORT:-8080}/healthcheck/" || exit 1'

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]

# docker build -t lucee-download8 .
# docker run -d -p 8056:8080 lucee-download8
