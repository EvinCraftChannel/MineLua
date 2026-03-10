# ─────────────────────────────────────────────────────────────
#  MineLua — Minecraft Bedrock Server in Lua
#  Koyeb-ready Dockerfile (built directly from GitHub repo)
# ─────────────────────────────────────────────────────────────

FROM ubuntu:22.04

LABEL org.opencontainers.image.title="MineLua"
LABEL org.opencontainers.image.description="Minecraft Bedrock Edition server in Lua"
LABEL org.opencontainers.image.source="https://github.com/YOUR_USERNAME/MineLua"

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        lua5.4 \
        liblua5.4-dev \
        luarocks \
        libssl-dev \
        zlib1g-dev \
        libzip-dev \
        build-essential \
        unzip \
        ca-certificates \
        curl \
    && rm -rf /var/lib/apt/lists/*

RUN luarocks install luasocket \
 && luarocks install lua-zlib \
 && luarocks install luazip 2>/dev/null || true

WORKDIR /minelua

COPY src/     ./src/
COPY config/  ./config/
COPY plugins/ ./plugins/
COPY worlds/  ./worlds/

RUN mkdir -p logs worlds/world/db worlds/world/players

ENV LUA_PATH="./src/?.lua;./src/?/init.lua;/usr/share/lua/5.4/?.lua;/usr/local/share/lua/5.4/?.lua;;"
ENV LUA_CPATH="/usr/lib/x86_64-linux-gnu/lua/5.4/?.so;/usr/local/lib/lua/5.4/?.so;;"

EXPOSE 19132/udp
EXPOSE 19133/udp

HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD pgrep -f "lua.*main.lua" > /dev/null || exit 1

CMD ["lua5.4", "src/main.lua"]
