# ---- build stage: compile TypeScript ----
FROM node:22-alpine AS build
WORKDIR /app
RUN apk add --no-cache openssl
COPY package*.json ./
RUN npm ci
COPY prisma ./prisma
RUN npx prisma generate
COPY tsconfig*.json nest-cli.json ./
COPY src ./src
RUN npm run build

# ---- runtime stage: prod deps + compiled output ----
FROM node:22-alpine AS runtime
WORKDIR /app
RUN apk add --no-cache openssl
ENV NODE_ENV=production
COPY package*.json ./
RUN npm ci --omit=dev
COPY prisma ./prisma
RUN npx prisma generate
COPY --from=build /app/dist ./dist
EXPOSE 3000
# Apply any pending migrations, then start the server.
CMD ["sh", "-c", "npx prisma migrate deploy && node dist/main.js"]
