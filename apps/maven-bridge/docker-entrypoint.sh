#!/bin/sh
set -e

PORT="${PORT:-8080}"
sed -i "s/listen 0.0.0.0:8080 default_server/listen 0.0.0.0:${PORT} default_server/" /etc/nginx/conf.d/default.conf

nginx -t

exec supervisord -c /etc/supervisor/supervisord.conf
