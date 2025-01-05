# syntax = docker/dockerfile:1.4

ARG NODE_VERSION=22

FROM --platform=$TARGETPLATFORM node:${NODE_VERSION}-slim AS base

ARG UID="991"
ARG GID="991"

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
 ca-certificates libjemalloc-dev libjemalloc2 tini \
 && ln -s /usr/lib/$(uname -m)-linux-gnu/libjemalloc.so.2 /usr/local/lib/libjemalloc.so \
 && groupadd -g "${GID}" ai \
 && useradd -l -u "${UID}" -g "${GID}" -m -d /app ai \
 && find / -type d -path /sys -prune -o -type d -path /proc -prune -o -type f -perm /u+s -ignore_readdir_race -exec chmod u-s {} \; \
 && find / -type d -path /sys -prune -o -type d -path /proc -prune -o -type f -perm /g+s -ignore_readdir_race -exec chmod g-s {} \; \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists \
 && npm install -g pnpm

FROM base AS build

WORKDIR /app
COPY . ./
RUN pnpm i --frozen-lockfile --aggregate-output \
 && NODE_ENV=production pnpm run build || test -f ./built/index.js

FROM base AS runtime

ARG enable_mecab=1

RUN if [ $enable_mecab -ne 0 ]; then \
    apt-get update \
 && apt-get install -y --no-install-recommends \
 curl file git libmecab-dev make mecab mecab-ipadic-utf8 patch xz-utils \
 && git clone --depth 1 https://github.com/yokomotod/mecab-ipadic-neologd.git /opt/mecab-ipadic-neologd \
 && cd /opt/mecab-ipadic-neologd && ./bin/install-mecab-ipadic-neologd -n -u -y && cd / && rm -rf /opt/mecab-ipadic-neologd \
 && echo "dicdir = /usr/lib/x86_64-linux-gnu/mecab/dic/mecab-ipadic-neologd/" > /etc/mecabrc \
 && apt-get purge -y curl file git make patch xz-utils \
 && apt-get autoremove --purge -y \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists; \
 fi

USER ai
WORKDIR /app
COPY --chown=ai:ai . ./
COPY --from=build --chown=ai:ai /app/built ./built

ENV NODE_ENV=production
RUN pnpm i --frozen-lockfile --aggregate-output

ENV LD_PRELOAD=/usr/local/lib/libjemalloc.so
ENV MALLOC_CONF=background_thread:true,metadata_thp:auto,dirty_decay_ms:30000,muzzy_decay_ms:30000
ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["pnpm", "run", "start"]
