-- Simulacrum
-- Klehrik

mods["MGReturns-ENVY"].auto()
mods["RoRRModdingToolkit-RoRR_Modding_Toolkit"].auto(true)

PATH = _ENV["!plugins_mod_folder_path"].."/"

require("./void_fog")

local diff, spawned_rewards, teleported, tp, director, void_actor
local boss_objs = {
    [gm.constants.oBoss1]       = true,
    [gm.constants.oBoss3]       = true,
    [gm.constants.oBoss4]       = true,
    [gm.constants.oWurmHead]    = true
}

-- Parameters
required_waves          = 20
radius                  = 1000  -- Radius of safe zone (in pixels)
void_circle_radius      = 250
void_color              = Color(0x802E99)
void_death_time         = 18    -- Time (in seconds) before guaranteed death outside the safe zone
void_death_time_enemy   = 27
charge_time             = 25    -- Teleporter charge time (in seconds)
enemy_buff_base         = 0.6   -- Starting enemy_buff
enemy_buff_scale        = 0.25  -- enemy_buff linear scaling per stage
enemy_buff_exp          = 1.02  -- enemy_buff exponential multiplier per stage
chest_cost_tweak        = 1.8

local ban_applied = false
local banned_items = {
    ["ror-infusion"]    = false,
    ["ror-umbrella"]    = false
}



-- ========== Main ==========

Initialize(function()
    tp = Instance.wrap_invalid()
    director = Instance.wrap_invalid()
    void_actor = Instance.wrap_invalid()

    -- Add difficulty
    diff = Difficulty.new("klehrik", "simulacrum")
    diff:set_sprite(
        Resources.sprite_load("klehrik", "simulacrumIcon", PATH.."simulacrum.png", 5, 12, 9),
        Resources.sprite_load("klehrik", "simulacrumIcon2x", PATH.."simulacrum2x.png", 4, 25, 19)
    )
    diff:set_primary_color(void_color)
    diff:set_sound(Resources.sfx_load("klehrik", "simulacrumSfx", PATH.."simulacrum.ogg"))

    diff:set_scaling(0, 0, 0)
    diff:set_monsoon_or_higher(false)
    diff:set_allow_blight_spawns(false)

    -- Add void objects
    add_void_actor()
    add_void_bg()
end)


Callback.add(Callback.TYPE.onStageStart, "simulacrum-onStageStart", function()
    if not diff:is_active() then return end

    spawned_rewards = false
    teleported = false
    
    -- Find tp and director
    if not tp:exists() then
        tp = Instance.find(Instance.teleporters)
        if tp:exists() then tp.maxtime = charge_time * 60
        else
            tp = Instance.find(gm.constants.oCommand)
            if not tp:exists() then return end
        end
    end
    if not director:exists() then
        director = Instance.find(gm.constants.oDirectorControl)
        if not director:exists() then return end
    end

    -- Manually set enemy_buff
    director.enemy_buff = (enemy_buff_base + (enemy_buff_scale * director.stages_passed)) * gm.power(enemy_buff_exp, director.stages_passed)

    -- Create void objects
    if Net.is_client() then return end
    void_actor = Object.find("klehrik-simulacrumVoid"):create(tp.x, tp.y)
    void_actor.image_alpha = 0
    void_actor.invincible = 10000000
    void_actor.team = 1
    void_actor.is_targettable = false
    Object.find("klehrik-simulacrumBG"):create(0, 0)

    -- Replace Divine Teleporters with standard ones until the required number of waves have been cleared
    local tpe = Instance.find(gm.constants.oTeleporterEpic)
    if  director.stages_passed < (required_waves - 1)
    and tpe:exists() then
        tp = Object.find(gm.constants.oTeleporter):create(tpe.x, tpe.y)
        tp.maxtime = charge_time * 60
        tpe:destroy()
    end
end)


Callback.add(Callback.TYPE.preStep, "simulacrum-preStep", function()  
    if not diff:is_active() then return end
    if not tp:exists() then return end
    if not director:exists() then return end
    if Net.is_client() then return end

    -- Spawn rewards on wave completion
    if (not spawned_rewards)
    and tp.active >= 3 then
        spawned_rewards = true
        local wave = math.floor(director.stages_passed + 1)

        -- Spawn a green item every 3 waves, and a red item on TotE
        local crate_tier = Item.TIER.common
        if wave % 3 == 0 then crate_tier = Item.TIER.uncommon end
        if wave % 5 == 0 then crate_tier = Item.TIER.rare end

        -- Get random selection of items
        local contents = {}
        local items = Item.find_all(crate_tier, Item.ARRAY.tier)
        while #contents < 3 do
            local pos = gm.irandom_range(1, #items)
            local item = items[pos]
            if  item:is_unlocked()
            and item:is_loot() then
                table.insert(contents, item)
            end
            table.remove(items, pos)
        end

        -- Spawn items
        local count = #Instance.find_all(gm.constants.oP)
        local pos_x = -48
        for i = 1, count do
            Item.spawn_crate(tp.x + pos_x, tp.y, crate_tier, contents)
            if i % 2 == 0 then pos_x = pos_x + (44 * gm.sign(pos_x)) end
            pos_x = -pos_x
        end

        -- Lower "boss_spawn_points"
        -- The director gains 700 every time the teleporter is hit; this will effectively halve gain
        director.boss_spawn_points = director.boss_spawn_points - 350
    end

    -- Deal void fog damage to all actors
    local actors = Instance.find_all(gm.constants.pActor)
    for _, actor in ipairs(actors) do
        take_void_damage(actor, void_actor)
    end
end)


Callback.add(Callback.TYPE.postStep, "simulacrum-postStep", function()
    if teleported then return end
    if not diff:is_active() then return end
    if not tp:exists() then return end
    
    teleported = true

    -- Teleport players to teleporter
    local players = Instance.find_all(gm.constants.oP)
    for _, player in ipairs(players) do
        player.x, player.ghost_x = tp.x, tp.x
        player.y, player.ghost_y = tp.y - 12, tp.y - 12
    end

    -- Set camera pan
    local pan = Instance.find(gm.constants.oPodCameraPan)
    if pan:exists() then
        pan.x = tp.x
        pan.y = tp.y
        pan.target_y = tp.y
    end
end)


Callback.add(Callback.TYPE.postHUDDraw, "simulacrum-postHUDDraw", function()
    if not diff:is_active() then return end
    if not tp:exists() then return end
    if not director:exists() then return end

    -- Draw text under tp
    if tp.time then -- Do not draw for oCommand
        local tkey = "simulacrum.wave"
        if tp.time <= 0 then tkey = "simulacrum.begin"
        elseif tp.active >= 3 then tkey = "simulacrum.next"
        end
        local text = Language.translate_token(tkey)
        text = text:gsub("WAVE", math.floor(director.stages_passed + 1))
        local c = Color.WHITE
        gm.draw_text_color(tp.x, tp.y + 18, text, c, c, c, c, 1.0)
    end
end)


-- Actor:onPreStep("simulacrum-onPreStep", function(actor)
--     if not void_actor:exists() then return end
--     if Net.is_client() then return end
    
--     -- Deal void fog damage to all actors
--     take_void_damage(actor, void_actor)
-- end)


gm.pre_code_execute("gml_Object_oDirectorControl_Alarm_1", function(self, other)
    if not diff:is_active() then return end
    if not tp:exists() then return end
    if tp.time > 0 then return end
    
    -- Prevent enemies from spawning before the teleporter is hit, as well as on the ship
    self:alarm_set(1, 60)
    return false
end)


gm.post_script_hook(gm.constants.cost_get_base_gold_price_scale, function(self, other, result, args)
    if not diff:is_active() then return end

    -- Scale up natural interactable costs
    result.value = result.value * chest_cost_tweak
end)


gm.post_script_hook(gm.constants.run_create, function(self, other, result, args)
    if not diff:is_active() then return end
    if ban_applied then return end
    ban_applied = true

    -- Toggle item ban
    for nsid, v in pairs(banned_items) do
        local item = Item.find(nsid)
        banned_items[nsid] = item:is_loot()
        item:toggle_loot(false)
    end
end)


gm.post_script_hook(gm.constants.run_destroy, function(self, other, result, args)
    if not ban_applied then return end
    ban_applied = false

    -- Untoggle item ban
    for nsid, v in pairs(banned_items) do
        local item = Item.find(nsid)
        item:toggle_loot(banned_items[nsid])
    end
end)