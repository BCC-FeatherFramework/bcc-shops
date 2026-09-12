-- Toolkit wrappers preserve BCC's world entity handles and cleanup methods.
ShopsToolkit = { Prompts = {}, Blips = {}, Ped = {} }
local toolkit = exports['feather-toolkit']
local function unwrap(r)
    if not r or not r.ok then error(r and r.code or 'toolkit_failed') end
    return r.value
end
function ShopsToolkit.Prompts:SetupPromptGroup()
    local group = { id = GetRandomIntInRange(0, 0xffffff) }
    function group:RegisterPrompt(label, control, _, _, enabled, mode)
        local value = unwrap(toolkit:CreatePrompt({ label = label, control = control, groupId = self.id, enabled = enabled, mode = mode }))
        return { HasCompleted = function() local r = toolkit:IsPromptCompleted(value.id); return r and r.ok and r.value.completed == true end }
    end
    function group:ShowGroup(label) toolkit:ShowPromptGroup(self.id, label) end
    return group
end
function ShopsToolkit.Blips:SetBlip(name, sprite, _, x, y, z)
    local value = unwrap(toolkit:CreateBlip({ name = name, sprite = sprite, x = x, y = y, z = z }))
    return { Remove = function() toolkit:RemoveBlip(value.id) end }
end
function ShopsToolkit.Ped:Create(model, x, y, z, heading)
    local value = unwrap(toolkit:CreatePed({ model = model, x = x, y = y, z = z, heading = heading, networked = false }))
    local ped = value.entity
    return {
        Freeze = function() FreezeEntityPosition(ped, true) end,
        SetHeading = function(_, h) SetEntityHeading(ped, h) end,
        Invincible = function() SetEntityInvincible(ped, true) end,
        SetBlockingOfNonTemporaryEvents = function(_, enabled) SetBlockingOfNonTemporaryEvents(ped, enabled) end,
        Remove = function() toolkit:RemoveEntity(value.id) end,
        GetPed = function() return ped end
    }
end
