FROM lucee/lucee:7.0.0.224-SNAPSHOT

RUN mkdir -p /var/www
COPY www/ /var/www/

COPY lucee-config.json /opt/lucee/server/lucee-server/context/.CFConfig.json

# Route artifact downloads through Lucee; metadata is served as static files from www/
RUN sed -i '/<url-pattern>\*\.cfml<\/url-pattern>/a\        <url-pattern>*.lex</url-pattern>\n        <url-pattern>*.pom</url-pattern>' /usr/local/tomcat/conf/web.xml

# docker build -t lucee-maven-bridge .
# docker run -d -p 8056:80 -e EXTENSION_PROVIDER=https://extension.lucee.org lucee-maven-bridge
