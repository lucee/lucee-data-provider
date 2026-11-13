# Cloud Run image for the REST update/extension provider (apps/updateserver).
# Build from the repository root:
#   docker build -f apps/updateserver/Dockerfile -t lucee-update .
#
# This is separate from devops/Dockerfile.update, which remains the Pixl8 image
# (nginx, port 8888) and is still built and deployed by ci.yml.
#
# Same Lucee version and extensions as the Pixl8 image, but the tomcat-only
# light tag (no nginx) so the listen port can follow $PORT, as download.lucee.org
# (apps/download8) does.

FROM --platform=linux/amd64 lucee/lucee:6.2.0.321-light

ENV LUCEE_ADMIN_ENABLED=false
ENV LUCEE_SECURITY_LIMITEVALUATION=true

RUN mkdir -p /opt/lucee/server/lucee-server/deploy \
             /opt/lucee/server/lucee-server/context \
             /var/www/logs \
 && wget -nv https://ext.lucee.org/sentry-extension-5.5.2.15.lex -O /opt/lucee/server/lucee-server/deploy/sentry-extension.lex \
 && wget -nv https://ext.lucee.org/s3-extension-2.0.2.21.lex -O /opt/lucee/server/lucee-server/deploy/s3-extension-2.0.2.21.lex \
 && wget -nv https://ext.lucee.org/image-extension-2.0.0.29.lex -O /opt/lucee/server/lucee-server/deploy/image-extension-2.0.0.29.lex \
 && wget -nv https://ext.lucee.org/esapi-extension-2.2.4.18.lex -O /opt/lucee/server/lucee-server/deploy/esapi-extension-2.2.4.18.lex \
 && wget -nv https://ext.lucee.org/compress-extension-1.0.0.15.lex -O /opt/lucee/server/lucee-server/deploy/compress-extension-1.0.0.15.lex \
 && ln -sf /proc/1/fd/1 /opt/lucee/server/lucee-server/context/logs/application.log \
 && ln -sf /proc/1/fd/1 /opt/lucee/server/lucee-server/context/logs/exception.log \
 && ln -sf /proc/1/fd/1 /opt/lucee/server/lucee-server/context/logs/rest.log \
 && ln -sf /proc/1/fd/1 /opt/lucee/server/lucee-server/context/logs/update-provider.log \
 && ln -sf /proc/1/fd/1 /opt/lucee/server/lucee-server/context/logs/deploy.log

COPY apps/updateserver /var/www
COPY devops/.CFconfig-update.json5 /opt/lucee/server/lucee-server/context/.CFConfig.json
# Applied on first start by Application.cfc (LDEV-5371 workaround), uses SENTRY_DSN / SENTRY_ENV
COPY devops/.CFconfig-sentry.json /opt/lucee/server/lucee-server/deploy/.CFconfig-sentry.json

COPY apps/updateserver/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

EXPOSE 8080

# Startup loads extension and core metadata and can take more than a minute.
HEALTHCHECK --interval=30s --timeout=30s --start-period=120s --retries=5 \
  CMD sh -c 'curl -fsS "http://127.0.0.1:${PORT:-8080}/healthcheck/" || exit 1'

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
