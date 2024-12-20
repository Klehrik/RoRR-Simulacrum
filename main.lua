-- Simulacrum
-- Klehrik

mods["MGReturns-ENVY"].auto()
mods["RoRRModdingToolkit-RoRR_Modding_Toolkit"].auto(true)

PATH = _ENV["!plugins_mod_folder_path"].."/"

require("./void_fog")

local diff, spawned_rewards, tp, director
void_actor = nil
local boss_objs = {
    [gm.constants.oBoss1]       = true,
    [gm.constants.oBoss3]       = true,
    [gm.constants.oBoss4]       = true,
    [gm.constants.oWurmHead]    = true
}

-- Parameters
required_waves          = 7
radius                  = 1000  -- Radius of safe zone (in pixels)
void_circle_radius      = 250
void_color              = Color(0x802E99)
void_death_time         = 18    -- Time (in seconds) before guaranteed death outside the safe zone
void_death_time_enemy   = 27
charge_time             = 20    -- Teleporter charge time (in seconds)
diff_scale              = 0.12
damage_tweak            = 0.7   -- Multiplies all enemy damage by this value
damage_tweak_tweak      = 0.95  -- damage_tweak is multiplied by this value after every stage (heavier damage reduction late game)
provi_damage_tweak      = 1.25  -- Multiplies Providence's (and his Wurms') damage by this value (applied after damage_tweak)
health_multiplier       = 0.55
chest_cost_tweak        = 1.8

banned_items            = {
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

    diff:set_scaling(
        diff_scale,
        0,
        0
    )
    diff:set_monsoon_or_higher(false)
    diff:set_allow_blight_spawns(false)

    -- Add void actor
    local obj = Object.new("klehrik", "simulacrumVoid", Object.PARENT.actor)
    obj.obj_sprite = Resources.sprite_load("klehrik", "simulacrumVoid", PATH.."simulacrum.png", 5, 13, 10)

    -- diff:onActive(function()
    --     -- Toggle item ban
    --     for nsid, v in pairs(banned_items) do
    --         local item = Item.find(nsid)
    --         banned_items[nsid] = item:is_loot()
    --         item:toggle_loot(false)
    --     end
    -- end)

    -- diff:onInactive(function()
    --     log.info("onInactive")

    --     -- Untoggle item ban
    --     for nsid, v in pairs(banned_items) do
    --         local item = Item.find(nsid)
    --         item:toggle_loot(banned_items[nsid])
    --     end
    -- end)
end)


Callback.add("onStageStart", "simulacrum-onStageStart", function(self, other, result, args)
    if not diff:is_active() then return end
    
    Alarm.create(function()
        if not tp:exists() then return end

        spawned_rewards = false

        -- Teleport local player to teleporter
        local player = Player.get_client()
        player.x, player.ghost_x = tp.x, tp.x
        player.y, player.ghost_y = tp.y - 12, tp.y - 12

        -- Set camera pan
        local pan = Instance.find(gm.constants.oPodCameraPan)
        if pan:exists() then
            pan.x = tp.x
            pan.y = tp.y
            pan.target_y = tp.y
        end

        -- Create void actor
        void_actor = Object.find("klehrik-simulacrumVoid"):create(-64, -64)
        void_actor.invincible = 1000000

        if not director:exists() then return end

        -- Replace Divine Teleporters with standard ones until the required number of waves have been cleared
        local tpe = Instance.find(gm.constants.oTeleporterEpic)
        if  director.stages_passed < (required_waves - 1)
        and tpe:exists() then
            Object.find(gm.constants.oTeleporter):create(tpe.x, tpe.y)
            tpe:destroy()
        end
    end, 1)
end)


Callback.add("preStep", "simulacrum-preStep", function(self, other, result, args)
    if not diff:is_active() then return end
    
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

    -- Spawn rewards on wave completion
    if (not spawned_rewards)
    and tp.active >= 3
    and (not Net.is_client()) then
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
            table.insert(contents, item)
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
        -- The director gains 700 every time the teleporter is hit
        director.boss_spawn_points = director.boss_spawn_points - 350

        -- Damage tweak tweak
        damage_tweak = damage_tweak * damage_tweak_tweak
    end
end)


Callback.add("postHUDDraw", "simulacrum-postHUDDraw", function(self, other, result, args)
    if not diff:is_active() then return end
    if not tp:exists() then return end

    -- Draw void fog
    draw_void_fog(tp.x, tp.y)
    
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


Actor:onPreStep("simulacrum-onPreStep", function(actor)
    if not diff:is_active() then return end
    if not tp:exists() then return end
    
    -- Deal void fog damage to all actors
    take_void_damage(actor, tp.x, tp.y)
end)


Actor:onPostStatRecalc("simulacrum-onPostStatRecalc", function(actor)
    if not diff:is_active() then return end
    if actor.team ~= 2 then return end

    -- Reduce enemy attack damage and health
    actor.damage = actor.damage * damage_tweak
    actor.maxhp = actor.maxhp * health_multiplier
    actor.maxbarrier = actor.maxbarrier * health_multiplier
    actor.hp = math.min(actor.hp, actor.maxhp)

    -- Manually set oHUD boss maxhp (??)
    local hud = Instance.find(gm.constants.oHUD)
    if hud:exists() and hud.boss_party_active then
        hud.boss_party_active.hp_total_max = actor.maxhp
    end

    -- Provi fight damage multiplier
    if boss_objs[actor.object_index] then
        actor.damage = actor.damage * provi_damage_tweak
    end
end)


gm.pre_code_execute("gml_Object_oDirectorControl_Alarm_1", function(self, other)
    -- Prevent enemies from spawning before the teleporter is hit, as well as on the ship
    if not diff:is_active() then return end
    if not tp:exists() then return end
    if tp.time > 0 then return end

    self:alarm_set(1, 60)
    return false
end)


gm.post_script_hook(gm.constants.cost_get_base_gold_price_scale, function(self, other, result, args)
    -- Scale up natural interactable costs
    if not diff:is_active() then return end
    result.value = result.value * chest_cost_tweak
end)