FROM node:20-alpine
WORKDIR /app

COPY package*.json ./
RUN npm install --omit=dev && npm cache clean --force

COPY src ./src

USER node
EXPOSE 2525
HEALTHCHECK --interval=30s --timeout=10s --start-period=10s --retries=3 CMD node src/cli.js test --config /app/config.json
CMD ["node", "src/cli.js", "start", "--config", "/app/config.json"]
