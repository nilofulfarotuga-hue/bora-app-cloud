FROM node:22-alpine
RUN apk add --no-cache git openssh-client
# o container corre com --user 10000 (dono do brain); sem entrada em passwd o ssh do git push
# aborta com "No user exists for uid 10000". Damos-lhe um passwd + HOME gravável.
RUN echo 'cortexmcp:x:10000:10000:cortexmcp:/tmp:/bin/sh' >> /etc/passwd
ENV HOME=/tmp
WORKDIR /app
COPY server.mjs /app/server.mjs
ENV PORT=4870
# Brain montado como volume em runtime (-v /opt/data/cortex-brain:/brain).
# Escrita começa DESLIGADA (CORTEX_WRITE_ENABLED=false) — dial cauteloso.
EXPOSE 4870
USER node
CMD ["node", "/app/server.mjs"]
