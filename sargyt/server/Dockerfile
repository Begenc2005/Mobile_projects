FROM node:22-alpine
WORKDIR /app/server
COPY server/package*.json ./
RUN npm ci --omit=dev
COPY server/ ./
COPY panel/ /app/panel/
ENV NODE_ENV=production
CMD ["sh", "-c", "node src/migrate.js && node src/server.js"]
