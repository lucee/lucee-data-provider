# Cloud Run image for the Maven-only REST update/extension provider
# (apps/updateserver-maven). Build from the repository root:
#   docker build -f apps/updateserver-maven/Dockerfile -t lucee-update-maven .
#
# This is a completely separate app from apps/updateserver (Pixl8). Do not
# point the Pixl8 deploy (devops/Dockerfile.update, ci.yml deploy-to-update)
# at this Dockerfile.
#
# Lucee 8 light (same tag as apps/download8) so this app can use
# LuceeVersionsList / LuceeVersionsDetail / LuceeExtension and share
# download8's on-disk cache. tomcat-only light tag (no nginx) so the
# listen port can follow $PORT. No S3 extension, no Sentry, no secrets.

FROM --platform=linux/amd64 lucee/lucee:8.0.0.294-RC-light

# Cloud Run memory is 2GiB. The base image defaults to -Xms64m -Xmx512m
# (LUCEE_JAVA_OPTS, copied into CATALINA_OPTS by Tomcat's setenv.sh).
# 1200m is a sensible heap for that size and leaves room for metaspace,
# thread stacks, direct buffers and the GCS FUSE mount at /download.
ENV LUCEE_JAVA_OPTS="-Xms256m -Xmx1200m"


ENV LUCEE_ADMIN_ENABLED=false
ENV LUCEE_SECURITY_LIMITEVALUATION=true
ENV LUCEE_LOGGING_FORCE_APPENDER=console
# Shared with download8: both services mount bucket lucee_downloads at
# /download and must set CACHE_DIRECTORY to that same folder.
ENV CACHE_DIRECTORY=/download
# App-specific caches (listings, extension meta, Jira) stay under this
# prefix so they cannot collide with download8's {key}.json files.
ENV CACHE_DIR=/download/provider
ENV LISTING_CACHE_SECONDS=300

RUN mkdir -p /opt/lucee/server/lucee-server/deploy \
             /opt/lucee/server/lucee-server/context \
             /var/www/logs \
             /download \
             /download/provider \
 && wget -nv https://ext.lucee.org/image-extension-2.0.0.29.lex -O /opt/lucee/server/lucee-server/deploy/image-extension-2.0.0.29.lex \
 && wget -nv https://maven.lucee-services.com/org/lucee/esapi-extension/3.1.0.7/esapi-extension-3.1.0.7.lex -O /opt/lucee/server/lucee-server/deploy/esapi-extension-3.1.0.7.lex \
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
