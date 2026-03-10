local CacheStatusHandler = {}
function CacheStatusHandler:handle(player, buf)
    local supported = buf:readBool()
    player.cache_supported = supported
end
return CacheStatusHandler
