FROM lucee/lucee:7.0.0.224-SNAPSHOT

ENV LUCEE_ADMIN_ENABLED=false

RUN mkdir -p /var/www
COPY www/ /var/www/

COPY lucee-config.json /opt/lucee/server/lucee-server/context/.CFConfig.json

RUN mkdir -p /var/www/logs \
 && ln -sf /proc/1/fd/1 /opt/lucee/server/lucee-server/context/logs/application.log \
 && ln -sf /proc/1/fd/1 /opt/lucee/server/lucee-server/context/logs/exception.log

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=30s --start-period=30s --retries=3 \
  CMD sh -c 'curl -fsS "http://127.0.0.1:${PORT:-8080}/health.cfm" || exit 1'

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]

# docker build -t lucee-skill .
# docker run -d -p 8055:8080 lucee-skill
