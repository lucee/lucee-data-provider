FROM lucee/lucee:7.0.0.224-SNAPSHOT

RUN mkdir -p /var/www
COPY www/ /var/www/

# copy a custom lucee config in place
COPY lucee-config.json /opt/lucee/server/lucee-server/context/.CFConfig.json

# Create directory for extensions and copy them
RUN mkdir -p /opt/lucee/extensions
COPY extensions/ /opt/lucee/extensions/

# how to build it
# docker build -t lucee-ai .

# how to run it (provides port for nginx and tomcat (optional); Lucee admin password)
# docker run -d \
#   -p 8054:80 \
#   -p 8854:8888 \
#   -e CLAUDE_API_KEY=xxx \
#   -e LUCEE_ADMIN_PASSWORD=sfjsaiofdsnadlfsa23 \
#   -e 'AI_ENDPOINT={"class": "lucee.runtime.ai.anthropic.ClaudeEngine","custom": {"model": "claude-3-7-sonnet-20250219","temperature": "0.1","apiKey": "${CLAUDE_API_KEY}","connectTimeout": "10000","socketTimeout": "20000","conversationSizeLimit": "10"}}' \
#   lucee-ai