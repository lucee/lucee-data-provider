#!/bin/sh
set -e

PORT="${PORT:-8080}"

# Cloud Run requires listening on $PORT; the Lucee image defaults to 8888.
if [ "$PORT" != "8888" ]; then
  sed -i "s/port=\"8888\"/port=\"${PORT}\"/" /usr/local/tomcat/conf/server.xml
fi

# gzip the JSON listings (0.1-1MB) for clients that accept it. Only the HTTP/1.1 connector, only once.
SERVER_XML=/usr/local/tomcat/conf/server.xml
if ! grep -q 'compression="on"' "$SERVER_XML"; then
  sed -i 's#protocol="HTTP/1.1"#protocol="HTTP/1.1" compression="on" compressionMinSize="2048" compressibleMimeType="application/json,text/plain,text/html,text/xml,application/xml"#' "$SERVER_XML"
fi

exec /usr/local/tomcat/bin/catalina.sh run
