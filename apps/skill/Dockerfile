FROM lucee/lucee:7.0.0.224-SNAPSHOT

ENV LUCEE_ADMIN_ENABLED=false

RUN mkdir -p /var/www
COPY www/ /var/www/

COPY lucee-config.json /opt/lucee/server/lucee-server/context/.CFConfig.json

RUN mkdir -p /var/www/logs \
 && ln -sf /proc/1/fd/1 /opt/lucee/server/lucee-server/context/logs/application.log \
 && ln -sf /proc/1/fd/1 /opt/lucee/server/lucee-server/context/logs/exception.log

EXPOSE 8888

HEALTHCHECK --interval=30s --timeout=30s --start-period=30s --retries=3 \
  CMD curl -fsS "http://127.0.0.1:8888/health.cfm" || exit 1

# docker build -t lucee-skill .
# docker run -d -p 8055:8888 -p 8855:8888 lucee-skill
