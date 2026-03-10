local Logger = require("utils.Logger")
local PlayerActionHandler = {}
local ACTIONS = {
    [0]="StartBreak",[1]="AbortBreak",[2]="StopBreak",
    [5]="StartSprint",[6]="StopSprint",[7]="StartSneak",[8]="StopSneak",
    [9]="CreativeDestroyBlock",[11]="StartGlide",[12]="StopGlide",
    [22]="StartSwimming",[23]="StopSwimming",[36]="StartCrawling",[37]="StopCrawling",
}
function PlayerActionHandler:handle(player, buf)
    local action = buf:readVarInt()
    local x = buf:readZigZag()
    local y = buf:readVarInt()
    local z = buf:readZigZag()
    local face = buf:readVarInt()
    local name = ACTIONS[action] or ("Action"..action)
    if name == "StartSprint"  then player.sprinting = true
    elseif name == "StopSprint"   then player.sprinting = false
    elseif name == "StartSneak"   then player.sneaking = true
    elseif name == "StopSneak"    then player.sneaking = false
    elseif name == "StartSwimming" then player.swimming = true
    elseif name == "StopSwimming"  then player.swimming = false
    elseif name == "StopBreak" or name == "CreativeDestroyBlock" then
        player.server.events:fire("BlockBreak", {
            player=player, x=x, y=y, z=z, face=face
        })
        if player.game_mode == 1 then -- creative
            player.world:setBlock(x, y, z, 0, 0)
        end
    end
end
return PlayerActionHandler
