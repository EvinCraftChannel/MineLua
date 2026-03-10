-- MineLua Logger
local Logger = {}
Logger.LEVELS = {DEBUG=0, INFO=1, WARN=2, ERROR=3}
Logger.level = 1
Logger.file = nil

local colors = {
    DEBUG = "\27[36m",
    INFO  = "\27[32m",
    WARN  = "\27[33m",
    ERROR = "\27[31m",
    RESET = "\27[0m"
}

function Logger.init(level_str, log_file)
    Logger.level = Logger.LEVELS[level_str:upper()] or 1
    if log_file then
        os.execute("mkdir -p " .. (log_file:match("(.+)/[^/]+$") or "."))
        Logger.file = io.open(log_file, "a")
    end
end

function Logger._log(level_str, msg)
    if (Logger.LEVELS[level_str] or 0) < Logger.level then return end
    local timestamp = os.date("[%H:%M:%S]")
    local line = string.format("%s [%s] %s", timestamp, level_str, msg)
    local colored = string.format("%s%s%s [%s] %s%s",
        colors[level_str] or "", timestamp, colors.RESET, level_str, msg, colors.RESET)
    io.write(colored .. "\n")
    if Logger.file then
        Logger.file:write(line .. "\n")
        Logger.file:flush()
    end
end

function Logger.debug(msg) Logger._log("DEBUG", tostring(msg)) end
function Logger.info(msg)  Logger._log("INFO",  tostring(msg)) end
function Logger.warn(msg)  Logger._log("WARN",  tostring(msg)) end
function Logger.error(msg) Logger._log("ERROR", tostring(msg)) end

return Logger
