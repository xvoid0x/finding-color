FROM oven/bun:1.3.8-alpine

WORKDIR /app

# Copy workspace manifests + lockfile for reproducible install
COPY package.json bun.lock ./
COPY packages/shared /app/packages/shared
COPY packages/phone /app/packages/phone

# Install all workspace deps
RUN bun install

WORKDIR /app/packages/phone

EXPOSE 5173

CMD ["bun", "run", "dev"]
