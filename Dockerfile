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

# 修复：创建 foliate-js/node_modules 符号链接，使 COPY 能够找到源路径
RUN mkdir -p /app/packages/foliate-js && \
    ln -sf /app/node_modules /app/packages/foliate-js/node_modules

FROM dependencies AS development-stage
COPY . .
WORKDIR /app/apps/readest-app
EXPOSE 3000
ENTRYPOINT ["pnpm", "dev-web", "-H", "0.0.0.0"]

FROM base AS build
ARG NEXT_PUBLIC_SUPABASE_URL
ARG NEXT_PUBLIC_SUPABASE_ANON_KEY
ARG NEXT_PUBLIC_APP_PLATFORM
ARG NEXT_PUBLIC_API_BASE_URL
ARG NEXT_PUBLIC_OBJECT_STORAGE_TYPE
ARG NEXT_PUBLIC_STORAGE_FIXED_QUOTA
ARG NEXT_PUBLIC_TRANSLATION_FIXED_QUOTA

# 从依赖阶段复制整个 node_modules
COPY --from=dependencies /app/node_modules /app/node_modules
COPY --from=dependencies /app/apps/readest-app/node_modules /app/apps/readest-app/node_modules
COPY --from=dependencies /app/apps/readest-app/public/vendor /app/apps/readest-app/public/vendor
COPY --from=dependencies /app/packages/foliate-js/node_modules /app/packages/foliate-js/node_modules

# 复制整个代码库
COPY . .

# 🚀 关键修改：在 `build` 阶段使用 `pnpm deploy` 创建独立的部署目录
# 这里的路径替换为你的子应用名称
# 使用 legacy 模式部署
RUN pnpm --filter=@readest/readest-app deploy pruned --legacy


# 切换工作目录到被剪枝后的独立应用目录
WORKDIR /app/pruned/apps/readest-app

# 执行构建命令
RUN pnpm build-web

FROM base AS runner
WORKDIR /app

# 从 builder 阶段复制构建好的 .next 文件夹和必要的文件
COPY --from=build /app/pruned/apps/readest-app/.next ./.next
COPY --from=build /app/pruned/apps/readest-app/public ./public
COPY --from=build /app/pruned/apps/readest-app/package.json ./package.json

# 从 builder 阶段的剪枝目录复制 node_modules（这会是一个处理好的副本）
COPY --from=build /app/pruned/node_modules ./node_modules

ENV NODE_ENV=production
ENV NEXT_TELEMETRY_DISABLED=1
ENV NEXT_PUBLIC_APP_PLATFORM=web
# ... 可选ARGS环境变量

EXPOSE 3000
CMD ["node", "server.js"]
