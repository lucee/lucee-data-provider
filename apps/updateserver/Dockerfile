# Cloud Run image for the Maven-only REST update/extension provider
# (apps/updateserver-maven).
#
# The existing Google Cloud Build trigger
# b40e43f4-fd52-45bf-800e-31657819f623 builds this path
# (apps/updateserver/Dockerfile) from the repository root. This file is
# therefore identical in effect to apps/updateserver-maven/Dockerfile, so
# the trigger does not need to be changed. Pixl8 does not use this file;
# it builds devops/Dockerfile.update (and devops/Dockerfile.download)
# from .github/workflows/ci.yml.
#
# Build from the repository root:
#   docker build -f apps/updateserver/Dockerfile -t lucee-update-maven .
#
# Same Lucee version as the Pixl8 image, tomcat-only light tag (no nginx) so
# the listen port can follow $PORT. No S3 extension, no Sentry, no secrets.

FROM --platform=linux/amd64 lucee/lucee:6.2.0.321-light

ENV LUCEE_ADMIN_ENABLED=false
ENV LUCEE_SECURITY_LIMITEVALUATION=true
ENV LUCEE_LOGGING_FORCE_APPENDER=console
ENV CACHE_DIR=/storage
ENV LISTING_CACHE_SECONDS=300

RUN mkdir -p /opt/lucee/server/lucee-server/deploy \
             /opt/lucee/server/lucee-server/context \
             /var/www/logs \
             /storage \
 && wget -nv https://ext.lucee.org/image-extension-2.0.0.29.lex -O /opt/lucee/server/lucee-server/deploy/image-extension-2.0.0.29.lex \
 && wget -nv https://ext.lucee.org/esapi-extension-2.2.4.18.lex -O /opt/lucee/server/lucee-server/deploy/esapi-extension-2.2.4.18.lex \
 && wget -nv https://ext.lucee.org/compress-extension-1.0.0.15.lex -O /opt/lucee/server/lucee-server/deploy/compress-extension-1.0.0.15.lex \
 && ln -sf /proc/1/fd/1 /opt/lucee/server/lucee-server/context/logs/application.log \
 && ln -sf /proc/1/fd/1 /opt/lucee/server/lucee-server/context/logs/exception.log \
 && ln -sf /proc/1/fd/1 /opt/lucee/server/lucee-server/context/logs/rest.log \
 && ln -sf /proc/1/fd/1 /opt/lucee/server/lucee-server/context/logs/update-provider.log \
 && ln -sf /proc/1/fd/1 /opt/lucee/server/lucee-server/context/logs/deploy.log

COPY apps/updateserver-maven /var/www
COPY devops/.CFconfig-update.json5 /opt/lucee/server/lucee-server/context/.CFConfig.json

COPY apps/updateserver-maven/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

EXPOSE 8080

# /healthcheck/ is a separate Lucee application and answers immediately
# (it does not load Maven metadata). Tomcat itself still needs a short
# start period.
HEALTHCHECK --interval=10s --timeout=5s --start-period=30s --retries=12 \
  CMD sh -c 'curl -fsS "http://127.0.0.1:${PORT:-8080}/healthcheck/" || exit 1'

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
