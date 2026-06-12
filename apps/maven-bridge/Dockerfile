FROM lucee/lucee:7.0.3.12-SNAPSHOT

ENV LUCEE_ADMIN_ENABLED=false

RUN mkdir -p /var/www
COPY www/ /var/www/

COPY lucee-config.json /opt/lucee/server/lucee-server/context/.CFConfig.json

# Route .lex/.pom downloads through Lucee; metadata is served as static files from /var/www
RUN sed -i '/<url-pattern>\*\.cfml<\/url-pattern>/a\        <url-pattern>*.lex</url-pattern>\n        <url-pattern>*.pom</url-pattern>' /usr/local/tomcat/conf/web.xml

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
# docker run -d -p 8856:8080 -e EXTENSION_PROVIDER=https://extension.lucee.org lucee-maven-bridge
