FROM docker.io/node:22-slim AS base
ENV PNPM_HOME="/pnpm"
ENV PATH="$PNPM_HOME:$PATH"
RUN corepack enable
RUN corepack prepare pnpm@10.29.3 --activate
WORKDIR /app
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
COPY apps/readest-app/package.json ./apps/readest-app/
COPY patches/ ./patches/
COPY packages/ ./packages/

FROM base AS dependencies
RUN --mount=type=cache,id=pnpm,target=/pnpm/store pnpm install --frozen-lockfile
RUN pnpm --filter @readest/readest-app setup-vendors
# 修复 foliate-js/node_modules 缺失（符号链接）
RUN mkdir -p /app/packages/foliate-js && \
    ln -sf /app/node_modules /app/packages/foliate-js/node_modules

FROM base AS build
ARG NEXT_PUBLIC_SUPABASE_URL
ARG NEXT_PUBLIC_SUPABASE_ANON_KEY
ARG NEXT_PUBLIC_APP_PLATFORM
ARG NEXT_PUBLIC_API_BASE_URL
ARG NEXT_PUBLIC_OBJECT_STORAGE_TYPE
ARG NEXT_PUBLIC_STORAGE_FIXED_QUOTA
ARG NEXT_PUBLIC_TRANSLATION_FIXED_QUOTA

COPY --from=dependencies /app/node_modules /app/node_modules
COPY --from=dependencies /app/apps/readest-app/node_modules /app/apps/readest-app/node_modules
COPY --from=dependencies /app/apps/readest-app/public/vendor /app/apps/readest-app/public/vendor
COPY --from=dependencies /app/packages/foliate-js/node_modules /app/packages/foliate-js/node_modules
COPY . .

WORKDIR /app/apps/readest-app
# 构建前确保 vendor 目录存在（虽然已复制，但再执行一次不会出错）
RUN pnpm build-web

# 使用 standalone 输出，并复制所有必要文件
FROM base AS runner
WORKDIR /app
COPY --from=build /app/apps/readest-app/.next/standalone ./
COPY --from=build /app/apps/readest-app/.next/static ./.next/static
COPY --from=build /app/apps/readest-app/public ./public

ENV NODE_ENV=production
ENV NEXT_TELEMETRY_DISABLED=1
ENV NEXT_PUBLIC_APP_PLATFORM=web
# 如果需要，可以传递其他环境变量

EXPOSE 3000
CMD ["node", "server.js"]
