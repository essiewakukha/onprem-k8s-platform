# syntax=docker/dockerfile:1
# Small, non-root, read-only-rootfs-friendly image.
FROM node:22-alpine AS test
WORKDIR /app
COPY package.json ./
COPY src ./src
COPY test ./test
RUN npm test

FROM node:22-alpine
ENV NODE_ENV=production \
    PORT=8080 \
    DATA_DIR=/data
WORKDIR /app
COPY --from=test /app/package.json ./
COPY --from=test /app/src ./src
# UID/GID 10001 matches securityContext in the Helm chart
RUN addgroup -g 10001 app && adduser -D -u 10001 -G app app \
 && mkdir -p /data && chown app:app /data
USER 10001:10001
EXPOSE 8080
# Exec form so node is PID 1 and receives SIGTERM directly
CMD ["node", "src/server.js"]