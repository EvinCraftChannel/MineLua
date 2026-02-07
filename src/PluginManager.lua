local lfs = require("lfs") -- Wajib terinstall
local PluginManager = {
    plugins = {},
    listeners = {}
}

-- Menambahkan folder plugins ke dalam path pencarian Lua
package.path = package.path .. ";./plugins/?.lua;./plugins/?/init.lua"

function PluginManager.loadPlugins()
    local path = "./plugins"
    
    -- 1. Pastikan folder plugins ada
    local attr = lfs.attributes(path)
    if not attr or attr.mode ~= "directory" then
        print("\27[33m[Plugin]\27[0m Folder 'plugins' tidak ditemukan, membuat baru...")
        lfs.mkdir(path)
        return
    end

    print("\27[34m[Plugin]\27[0m Scanning folder plugins...")

    -- 2. Iterasi semua file di folder plugins
    for file in lfs.dir(path) do
        if file ~= "." and file ~= ".." then
            -- Deteksi file .lua (Single file plugin) atau Folder (Package plugin)
            local isPlugin = false
            local pluginName = ""

            if file:match("%.lua$") then
                pluginName = file:sub(1, -5) -- Hapus ".lua"
                isPlugin = true
            else
                local subAttr = lfs.attributes(path .. "/" .. file)
                if subAttr.mode == "directory" then
                    pluginName = file
                    isPlugin = true
                end
            end

            if isPlugin then
                PluginManager.loadPlugin(pluginName)
            end
        end
    end
end

function PluginManager.loadPlugin(name)
    -- Hindari loading plugin yang sama dua kali
    if PluginManager.plugins[name] then return end

    -- Gunakan pcall agar jika satu plugin error, server tetap jalan
    local success, plugin = pcall(require, name)
    
    if success and type(plugin) == "table" then
        plugin.name = name
        PluginManager.plugins[name] = plugin
        
        -- Jalankan onEnable (Lifecycle seperti PMMP)
        if plugin.onEnable then
            local ok, err = pcall(plugin.onEnable, plugin)
            if not ok then 
                print("\27[31m[Plugin Error]\27[0m onEnable " .. name .. ": " .. err) 
            end
        end
        
        print("\27[32m[Plugin]\27[0m Loaded: " .. name)
    else
        print("\27[31m[Error]\27[0m Gagal memuat " .. name .. ": " .. tostring(plugin))
        -- Hapus cache require agar bisa dicoba lagi setelah fix tanpa restart
        package.loaded[name] = nil
    end
end

-- --- API EVENT ---

function PluginManager.registerEvent(eventName, callback)
    if not PluginManager.listeners[eventName] then
        PluginManager.listeners[eventName] = {}
    end
    table.insert(PluginManager.listeners[eventName], callback)
end

function PluginManager.callEvent(eventName, ...)
    -- 1. Panggil listeners statis
    if PluginManager.listeners[eventName] then
        for _, callback in ipairs(PluginManager.listeners[eventName]) do
            local success, err = pcall(callback, ...)
            if not success then print("\27[31m[Event Error]\27[0m " .. eventName .. ": " .. err) end
        end
    end

    -- 2. Panggil hooks otomatis di dalam tabel plugin
    for _, plugin in pairs(PluginManager.plugins) do
        if plugin[eventName] and type(plugin[eventName]) == "function" then
            local success, err = pcall(plugin[eventName], plugin, ...)
            if not success then print("\27[31m[Plugin Error]\27[0m " .. eventName .. " in " .. plugin.name .. ": " .. err) end
        end
    end
end

return PluginManager
