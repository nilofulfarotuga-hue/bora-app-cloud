FROM node:22-alpine
RUN apk add --no-cache git
WORKDIR /app
COPY server.mjs /app/server.mjs
ENV PORT=4870
# Brain montado como volume em runtime (-v /opt/data/cortex-brain:/brain).
# Escrita começa DESLIGADA (CORTEX_WRITE_ENABLED=false) — dial cauteloso.
EXPOSE 4870
USER node
CMD ["node", "/app/server.mjs"]
