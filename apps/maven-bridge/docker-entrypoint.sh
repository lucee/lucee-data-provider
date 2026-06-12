#!/bin/sh
set -e

PORT="${PORT:-8080}"

# Cloud Run requires listening on $PORT; the Lucee image defaults to 8888.
if [ "$PORT" != "8888" ]; then
  sed -i "s/port=\"8888\"/port=\"${PORT}\"/" /usr/local/tomcat/conf/server.xml
fi

exec /usr/local/tomcat/bin/catalina.sh run
