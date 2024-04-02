-- Helper v2

local self = {}


--[[
    find_active_instance(index) -> instance or nil

    index           The object_index of the instance

    Returns the first active instance of the specified
    object_index, or nil if none can be found.
]]
self.find_active_instance = function(index)
    for i = 1, #gm.CInstance.instances_active do
        local inst = gm.CInstance.instances_active[i]
        if inst.object_index == index then
            return inst
        end
    end
    return nil
end


--[[
    find_active_instance_all(index) -> table or nil

    index           The object_index of the instance

    Returns a table of all active instances of the
    specified object_index, or nil if none can be found.
]]
self.find_active_instance_all = function(index)
    local objs = {}
    for i = 1, #gm.CInstance.instances_active do
        local inst = gm.CInstance.instances_active[i]
        if inst.object_index == index then
            table.insert(objs, inst)
        end
    end
    if #objs > 0 then return objs end
    return nil
end


--[[
    does_instance_exists(inst) -> bool

    inst            The instance to check

    Returns true if the instance is not
    lua nil, and if the instance is "valid".
]]
self.does_instance_exist = function(inst)
    return inst and gm._mod_instance_valid(inst) == 1.0
end


--[[
    get_client_player() -> instance or nil

    Returns the player instance belonging to
    this client, or nil if none can be found.
]]
self.get_client_player = function()
    -- Using pref_name to identify which player is this client
    -- TODO: Find a better way of checking instead
    local pref_name = ""
    local init = self.find_active_instance(gm.constants.oInit)
    if init then pref_name = init.pref_name end

    -- Get the player that belongs to this client
    local players = self.find_active_instance_all(gm.constants.oP)
    if players then
        for i = 1, #players do
            if players[i] then
                if players[i].user_name == pref_name then
                    return players[i]
                end
            end
        end
    end

    return nil
end


--[[
    get_teleporter() -> instance or nil

    Returns the stage teleporter,
    or nil if there isn't one.

    If there is more than one, the first one
    found is returned, and standard teleporters
    take precedence over the Divine Teleporter.
]]
self.get_teleporter = function()
    local tp = self.find_active_instance(gm.constants.oTeleporter)
    local tpe = self.find_active_instance(gm.constants.oTeleporterEpic)

    if self.does_instance_exist(tp) then return tp end
    if self.does_instance_exist(tpe) then return tpe end
    return nil
end


--[[
    get_multishops() -> table or nil

    Returns a table of all multishops on
    the stage, or nil if there are none.
]]
self.get_multishops = function()
    local shops = {}
    local shops1 = self.find_active_instance_all(gm.constants.oShop1)
    local shops2 = self.find_active_instance_all(gm.constants.oShop2)

    if shops1 then
        for i = 1, #shops1 do table.insert(shops, shops1[i]) end
    end
    if shops2 then
        for i = 1, #shops2 do table.insert(shops, shops2[i]) end
    end
    
    if #shops <= 0 then return nil end
    return shops
end


--[[
    ease_in(x, n) -> float

    x               The input value
    n               The easing power (default quadratic)

    Returns an ease in value for
    a given value x between 0 and 1.
]]
self.ease_in = function(x, n)
    n = n or 2
    return gm.power(x, n)
end


--[[
    ease_out(x, n) -> float

    x               The input value
    n               The easing power (default quadratic)

    Returns an ease out value for
    a given value x between 0 and 1.
]]
self.ease_out = function(x, n)
    n = n or 2
    return 1 - gm.power(1 - x, n)
end


return self