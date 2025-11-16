# Multi-stage: build a production-ready Next.js app (standalone)
FROM node:22-alpine AS base
WORKDIR /app

# deps stage: install dependencies
FROM base AS deps
RUN apk add --no-cache libc6-compat
COPY package.json package-lock.json ./
RUN npm i -f --production=false

# builder: copy deps and source, build
FROM base AS builder
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .
RUN npm run build

# runner: minimal runtime using Next.js standalone output
FROM node:22-alpine AS runner
WORKDIR /app
ENV NODE_ENV=production
# create a non-root user
RUN addgroup --system --gid 1001 nodejs \
 && adduser --system --uid 1001 nextjs

# copy public, standalone and static output (standalone includes package.json + server)
COPY --from=builder /app/public ./public
COPY --from=builder /app/.next/standalone ./
COPY --from=builder /app/.next/static ./.next/static

# ensure ownership for non-root user (optional but recommended)
RUN chown -R nextjs:nodejs /app

USER nextjs

EXPOSE 3000
ENV PORT=3000 HOST=0.0.0.0

# The standalone folder typically contains server.js (or uses node ./server.js)
CMD ["node", "server.js"]
