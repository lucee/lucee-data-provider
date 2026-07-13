FROM --platform=linux/amd64 lucee/lucee:8.0.0.171-SNAPSHOT-light

ENV LUCEE_ADMIN_ENABLED=false

RUN mkdir -p /var/www
COPY www/ /var/www/

COPY lucee-config.json /opt/lucee/server/lucee-server/context/.CFConfig.json
COPY Server.cfc /opt/lucee/server/lucee-server/context/context/Server.cfc

# Route the whole Maven repo tree through Lucee: /org/* and /io/* cover every file type
# (maven-metadata.xml, .lex, .pom, core jars incl. classifiers, .lco, checksums, ...).
# Keep in sync with isMavenRepoPath() in www/Application.cfc.
RUN sed -i '/<url-pattern>\*\.cfml<\/url-pattern>/a\        <url-pattern>*.xml</url-pattern>\n        <url-pattern>*.lex</url-pattern>\n        <url-pattern>*.pom</url-pattern>\n        <url-pattern>/org/*</url-pattern>\n        <url-pattern>/io/*</url-pattern>' /usr/local/tomcat/conf/web.xml

RUN mkdir -p /var/www/logs \
 && ln -sf /proc/1/fd/1 /opt/lucee/server/lucee-server/context/logs/application.log \
 && ln -sf /proc/1/fd/1 /opt/lucee/server/lucee-server/context/logs/exception.log

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=30s --start-period=30s --retries=3 \
  CMD sh -c 'curl -fsS "http://127.0.0.1:${PORT:-8080}/health.cfm" || exit 1'

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]

# docker build -t lucee-maven-bridge .
# docker run -d -p 8856:8080 \
#   -e EXTENSION_PROVIDERS='https://www.forgebox.io|io.forgebox,https://extension.lucee.org|org.lucee|https://cdn.lucee.org/' \
#   lucee-maven-bridge
