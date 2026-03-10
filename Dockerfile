# ─────────────────────────────────────────────────────────────
#  MineLua — Minecraft Bedrock Server in Lua
#  Koyeb-ready Dockerfile
# ─────────────────────────────────────────────────────────────

FROM ubuntu:22.04

LABEL org.opencontainers.image.title="MineLua"
LABEL org.opencontainers.image.description="Minecraft Bedrock Edition server in Lua"

ENV DEBIAN_FRONTEND=noninteractive

# ── 1. Install sistem packages ────────────────────────────────
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
        wget \
    && rm -rf /var/lib/apt/lists/*

# ── 2. Install luarocks versi yang support lua5.4 ────────────
# Ubuntu 22.04 luarocks defaultnya lua5.1, kita install ulang luarocks 3.x
RUN wget -q https://luarocks.org/releases/luarocks-3.11.1.tar.gz \
    && tar xzf luarocks-3.11.1.tar.gz \
    && cd luarocks-3.11.1 \
    && ./configure --with-lua-version=5.4 --with-lua-bin=/usr/bin/lua5.4 \
                   --with-lua-include=/usr/include/lua5.4 \
    && make && make install \
    && cd .. && rm -rf luarocks-3.11.1 luarocks-3.11.1.tar.gz

# ── 3. Install Lua libraries untuk lua5.4 ────────────────────
RUN luarocks install luasocket \
 && luarocks install lua-zlib 2>/dev/null || true \
 && luarocks install luazip   2>/dev/null || true

# ── 4. Verifikasi socket terinstall ──────────────────────────
RUN lua5.4 -e "local s = require('socket'); print('socket OK: ' .. s._VERSION)"

WORKDIR /minelua

COPY src/     ./src/
COPY config/  ./config/
COPY plugins/ ./plugins/
COPY worlds/  ./worlds/

RUN mkdir -p logs worlds/world/db worlds/world/players

ENV LUA_PATH="./src/?.lua;./src/?/init.lua;/usr/local/share/lua/5.4/?.lua;/usr/local/share/lua/5.4/?/init.lua;/usr/share/lua/5.4/?.lua;;"
ENV LUA_CPATH="/usr/local/lib/lua/5.4/?.so;/usr/lib/x86_64-linux-gnu/lua/5.4/?.so;/usr/lib/lua/5.4/?.so;;"

EXPOSE 19132/udp
EXPOSE 19133/udp

HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD pgrep -f "lua.*main.lua" > /dev/null || exit 1

CMD ["lua5.4", "src/main.lua"]
