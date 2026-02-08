# Menggunakan Alpine 3.18 yang stabil untuk Lua 5.3
FROM alpine:3.18

# 1. Install dependensi sistem secara spesifik
RUN apk add --no-cache \
    lua5.3 \
    lua5.3-dev \
    gcc \
    musl-dev \
    make \
    luarocks \
    zlib-dev \
    git \
    unzip

# 2. Pastikan LuaRocks menggunakan Lua 5.3
RUN luarocks --lua-version 5.3 install luasocket && \
    luarocks --lua-version 5.3 install luafilesystem && \
    luarocks --lua-version 5.3 install lua-cjson && \
    luarocks --lua-version 5.3 install lua-zlib

# 3. Setup folder aplikasi
WORKDIR /app

# 4. Copy file (pastikan file main.lua ada di root folder GitHub kamu)
COPY . .

# 5. Ekspos port UDP Minecraft
EXPOSE 19132/udp

# 6. Jalankan dengan binary yang jelas
CMD ["lua5.3", "main.lua"]
