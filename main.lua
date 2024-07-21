-- Simulacrum v1.1.1
-- Klehrik

log.info("Successfully loaded ".._ENV["!guid"]..".")
mods.on_all_mods_loaded(function() for k, v in pairs(mods) do if type(v) == "table" and v.hfuncs then Helper = v end end end)

local diff_icon = gm.sprite_add(_ENV["!plugins_mod_folder_path"].."/simulacrum.png", 5, false, false, 12, 9)
local diff_icon2x = gm.sprite_add(_ENV["!plugins_mod_folder_path"].."/simulacrum2x.png", 4, false, false, 25, 19)
local diff_sfx = gm.audio_create_stream(_ENV["!plugins_mod_folder_path"].."/simulacrum.ogg")

local lang_map = nil
local very_easy_text = ""

local frame = 0

local init = false
local diff_id = -2

local void_circles = {}
local void_circle_radius = 250
local void_colour = 10038912
local surf = -1

local director = nil
local spawned_rewards = false

local teleporter = nil

local flag_new_run = false
local stage_id = -1


-- Parameters
local required_waves        = 20
local radius                = 1000  -- Radius of safe zone (in pixels)
local void_death_time       = 18    -- Time (in seconds) before guaranteed death outside the safe zone
local void_death_time_enemy = 27
local charge_time           = 20    -- Teleporter charge time (in seconds)
local diff_scale            = 0.12
local damage_tweak          = 0.7   -- Multiplies all enemy damage by this value
local damage_tweak_tweak    = 0.95  -- damage_tweak is multiplied by this value after every stage (heavier damage reduction late game)
local provi_damage_tweak    = 1.25  -- Multiplies Providence's (and his Wurms') damage by this value (applied after damage_tweak)
local health_multiplier     = 0.55
local chest_cost_tweak      = 1.8
local banned_items          = {"ror-infusion", "ror-umbrella"}



-- ========== Functions ==========

local function take_void_damage(actor, origin)
    -- While in the void fog, take damage equal to a gradually increasing portion of current health
    -- Guaranteed death after some time, but not fatal before that
    actor.time_outside = actor.time_outside or 0
    local dist = gm.point_distance(actor.x, actor.y, origin.x, origin.y)
    if dist > radius then
        if actor.invincible == false then actor.invincible = 0 end
        if actor.invincible <= 0 then
            actor.time_outside = actor.time_outside + 1
            if actor.time_outside % 60 == 0 then
                local int = math.floor(actor.time_outside / 60)
                local dtime = void_death_time
                if actor.team == 2.0 then dtime = void_death_time_enemy end
                gm.damage_inflict(actor, actor.hp * Helper.ease_in(int/dtime))
            end
        end
    else actor.time_outside = 0
    end
end


local function draw_void_fog(origin)
    gm.draw_set_circle_precision(64)

    -- Create void fog surface
    local cam = gm.view_get_camera(0)
    if gm.surface_exists(surf) == 0.0 then surf = gm.surface_create(gm.camera_get_view_width(cam), gm.camera_get_view_height(cam)) end
    gm.surface_set_target(surf)
    gm.draw_clear_alpha(0, 0)

    -- Draw void fog base
    gm.draw_set_alpha(0.5)
    gm.draw_rectangle_colour(0, 0, gm.camera_get_view_width(cam), gm.camera_get_view_height(cam), void_colour, void_colour, void_colour, void_colour, false)
    gm.draw_set_alpha(1)

    -- Punch hole in void fog
    gm.gpu_set_blendmode(3) -- bm_subtract
    gm.draw_circle(origin.x - gm.camera_get_view_x(cam), origin.y - gm.camera_get_view_y(cam), radius, false)
    gm.gpu_set_blendmode(0) -- bm_normal

    -- Draw void fog surface
    gm.surface_reset_target()
    gm.draw_surface(surf, gm.camera_get_view_x(cam), gm.camera_get_view_y(cam))


    -- Add purple circles to draw
    if frame % 15 == 0 then table.insert(void_circles, void_circle_radius) end

    -- Draw purple circles
    for i = #void_circles, 1, -1 do
        local ease = Helper.ease_out(void_circles[i]/void_circle_radius, 3)
        gm.draw_set_alpha(1 - ease)
        local r = ease * void_circle_radius
        gm.draw_circle_colour(origin.x, origin.y, radius + r, void_colour, void_colour, true)
        gm.draw_set_alpha(1)

        void_circles[i] = void_circles[i] - 1
        if void_circles[i] <= 0 then table.remove(void_circles, i) end
    end

    -- Draw safe zone radius around teleporter
    gm.draw_set_alpha(0.3)
    gm.draw_circle(origin.x, origin.y, radius, true)
    gm.draw_set_alpha(1)

    gm.draw_set_circle_precision(24)
end


local function get_crate_items(crate_type)
    local rarity_items = Helper.get_all_items(crate_type)

    -- Remove banned items
    for n, i in ipairs(rarity_items) do
        local name = i.namespace.."-"..i.identifier
        for _, b in ipairs(banned_items) do
            if name == b then
                table.remove(rarity_items, n)
                break
            end
        end
    end

    return rarity_items
end



-- ========== Hooks ==========

gm.pre_script_hook(gm.constants.__input_system_tick, function()
    frame = frame + 1

    -- Initialize
    if not init then
        init = true

        -- Initialize difficulty
        diff_id = gm.difficulty_create("klehrik", "simulacrum")   -- Namespace, Identifier
        local class_diff = gm.variable_global_get("class_difficulty")[diff_id + 1]
        local values = {
            "Simulacrum",   -- Name
            "Fight your way through waves of teleporter events.\nBeat Wave "..required_waves.." to reach Providence.",  -- Description
            diff_icon,      -- Sprite ID
            diff_icon2x,    -- Sprite Loadout ID
            void_colour,    -- Primary Color
            diff_sfx,       -- Sound ID
            diff_scale,     -- diff_scale
            0.0,            -- general_scale
            0.0,            -- point_scale
            false,          -- is_monsoon_or_higher
            false           -- allow_blight_spawns  -- Unbalanced for this mode
        }
        for i = 2, 12 do gm.array_set(class_diff, i, values[i - 1]) end
    end


    -- Simulacrum
    if gm._mod_game_getDifficulty() == diff_id then

        -- Teleporter
        if not Helper.instance_exists(teleporter) then
            teleporter = Helper.get_teleporter()
            if Helper.instance_exists(teleporter) then teleporter.maxtime = charge_time *60     -- Set charge time to a lower amount
            else teleporter = Helper.find_active_instance(gm.constants.oCommand)
            end
        end


        -- Director
        if Helper.instance_exists(director) then
            
            -- Init new run variables
            if flag_new_run then
                frame = 0
                stage_id = -1

                local base = Helper.find_active_instance(gm.constants.oBase)
                local pan = Helper.find_active_instance(gm.constants.oPodCameraPan)
                if Helper.instance_exists(base) and Helper.instance_exists(pan) and Helper.instance_exists(teleporter) then
                    base.x = teleporter.x
                    base.y = teleporter.y
                    pan.x = teleporter.x
                    pan.y = teleporter.y
                    pan.target_y = teleporter.y

                    flag_new_run = false
                end
            end


            -- Run stage enter stuff
            if stage_id ~= gm.variable_global_get("stage_id") then
                spawned_rewards = false

                -- Warp players to teleporter
                local players, exist = Helper.find_active_instance_all(gm.constants.oP)
                if exist and Helper.instance_exists(teleporter) then
                    for _, player in ipairs(players) do
                        player.x = teleporter.x
                        player.y = teleporter.y - 12
                    end
                    stage_id = gm.variable_global_get("stage_id")
                end
            end

            -- Replace Divine Teleporters with standard ones until the required number of waves have been cleared
            local tpe = Helper.find_active_instance(gm.constants.oTeleporterEpic)
            if director.stages_passed < (required_waves - 1) and Helper.instance_exists(tpe) then
                gm.instance_create_depth(tpe.x, tpe.y, 2, gm.constants.oTeleporter)
                gm.instance_destroy(tpe)
            end

            -- Spawn crates after wave completion
            if (not spawned_rewards) and Helper.is_singleplayer_or_host() then
                if Helper.instance_exists(teleporter) then
                    if teleporter.active >= 3.0 then
                        spawned_rewards = true

                        local wave = math.floor(director.stages_passed + 1)

                        -- Spawn a green item every 3 waves, and a red item on TotE
                        local crate_type = Helper.rarities.white
                        if wave % 3 == 0 then crate_type = Helper.rarities.green end
                        if wave % 5 == 0 then crate_type = Helper.rarities.red end

                        -- Get random selection of items
                        local contents = {}
                        local rarity_items = get_crate_items(crate_type)
                        for i = 1, 3 do
                            local n = gm.irandom_range(1, #rarity_items)
                            table.insert(contents, rarity_items[n].class_id)
                            table.remove(rarity_items, n)
                        end

                        -- Spawn items
                        local count = #Helper.find_active_instance_all(gm.constants.oP)
                        local pos_x = -48
                        for i = 1, count do
                            Helper.spawn_crate(teleporter.x + pos_x, teleporter.y - 32, crate_type, contents)
                            if i % 2 == 0 then pos_x = pos_x + (44 * gm.sign(pos_x)) end
                            pos_x = -pos_x
                        end


                        -- Lower "boss_spawn_points"
                        -- The director gains 700 every time the teleporter is hit
                        director.boss_spawn_points = director.boss_spawn_points - 350

                        -- Damage tweak tweak
                        damage_tweak = damage_tweak * damage_tweak_tweak
                    end
                end
            end

        else director = Helper.find_active_instance(gm.constants.oDirectorControl)
        end


        -- Replace all banned items
        for _, b in ipairs(banned_items) do
            local item = Helper.find_item(b)
            local items = Helper.find_active_instance_all(item.id)

            for _, i in ipairs(items) do
                if Helper.is_singleplayer_or_host() then
                    local rarity_items = get_crate_items(item.rarity)
                    gm.instance_create_depth(i.x, i.y, 0, rarity_items[gm.irandom_range(1, #rarity_items)].id)
                end
                gm.instance_destroy(i)
            end
        end

    end
end)


gm.post_script_hook(gm.constants.step_actor, function(self, other, result, args)
    if gm._mod_game_getDifficulty() == diff_id then
        -- Reduce enemy attack damage
        if self.team == 2.0 and self.simulacrum_damage_tweak == nil then
            self.simulacrum_damage_tweak = true
    
            if self.damage ~= nil then
                self.damage = self.damage * damage_tweak
                self.damage_base = self.damage_base * damage_tweak

                -- Provi fight damage multiplier
                if self.object_index == gm.constants.oBoss1
                or self.object_index == gm.constants.oBoss3
                or self.object_index == gm.constants.oBoss4
                or self.object_index == gm.constants.oWurmHead then
                    self.damage = self.damage * provi_damage_tweak
                    self.damage_base = self.damage_base * provi_damage_tweak
                end
            end
        end

        -- Deal void fog damage to all actors
        if Helper.instance_exists(teleporter) then take_void_damage(self, teleporter) end
    end
end)


gm.pre_code_execute(function(self, other, code, result, flags)
    -- Prevent enemies from spawning before the teleporter is hit, as well as on the ship
    if code.name:match("oDirectorControl_Alarm_1") then
        if Helper.instance_exists(teleporter) and (teleporter.time == nil or teleporter.time <= 0) then
            self:alarm_set(1, 60)
            return false
        end
    end
end)


gm.post_script_hook(gm.constants.cost_get_base_gold_price_scale, function(self, other, result, args)
    -- Scale up natural interactable costs
    if gm._mod_game_getDifficulty() == diff_id then
        result.value = result.value * chest_cost_tweak
    end
end)


gm.post_code_execute(function(self, other, code, result, flags)
    if code.name:match("oInit_Draw_7") then
        if gm._mod_game_getDifficulty() == diff_id then

            -- Teleporter draw
            if Helper.instance_exists(teleporter) then

                -- Wave count
                if director and teleporter.time ~= nil then
                    local text = "Wave "..(math.floor(director.stages_passed + 1))
                    if teleporter.time <= 0 then text = "Begin wave?"
                    elseif teleporter.active >= 3.0 then text = "Proceed to next wave"
                    end
                    gm.draw_text(teleporter.x, teleporter.y + 18, text)
                end

                draw_void_fog(teleporter)

            end

        end
    end
end)


gm.post_script_hook(gm.constants.run_create, function(self, other, result, args)
    if gm._mod_game_getDifficulty() == diff_id then
        flag_new_run = true

        -- Replace "Very Easy" localization text temporarily
        -- Can't seem to change the oHUD one directly so
        lang_map = gm.variable_global_get("_language_map")
        very_easy_text = gm.ds_map_find_value(lang_map, "hud.difficulty[0]")
        gm.ds_map_set(lang_map, "hud.difficulty[0]", "--")
    end
end)


gm.pre_script_hook(gm.constants.run_destroy, function(self, other, result, args)
    if gm._mod_game_getDifficulty() == diff_id then
        -- Put "Very Easy" localization text back
        gm.ds_map_set(lang_map, "hud.difficulty[0]", very_easy_text)
    end
end)


gm.pre_script_hook(gm.constants.step_actor, function(self, other, result, args)
    -- Health multiplier
    if self.team == 2.0 and self.simulacrum_health_multiplier == nil then
        self.simulacrum_health_multiplier = true

        if self.maxhp then
            self.maxhp = self.maxhp * health_multiplier
            self.maxhp_base = self.maxhp
            self.hp = self.maxhp
            self.maxbarrier = self.maxhp
        end
    end
end)