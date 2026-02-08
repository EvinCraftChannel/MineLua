FROM alpine:latest

# Install Lua dan build dependencies
RUN apk add --no-cache \
    lua5.3 \
    lua5.3-dev \
    gcc \
    musl-dev \
    make \
    luarocks \
    zlib-dev

# Install dependensi library yang dibutuhkan kode Anda
RUN luarocks-5.3 install luasocket
RUN luarocks-5.3 install luafilesystem
RUN luarocks-5.3 install lua-cjson
RUN luarocks-5.3 install lua-zlib

# Set working directory
WORKDIR /app

# Copy semua file dari repo ke dalam image
COPY . .

# Expose port UDP Minecraft
EXPOSE 19132/udp

# Jalankan server
CMD ["lua5.3", "src/Core.lua"]
