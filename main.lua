-- Simulacrum v1.0.1
-- Klehrik

log.info("Successfully loaded ".._ENV["!guid"]..".")
Helper = require("./helper")

local diff_icon = gm.sprite_add(_ENV["!plugins_mod_folder_path"].."/simulacrum.png", 5, false, false, 12, 9)
local diff_icon2x = gm.sprite_add(_ENV["!plugins_mod_folder_path"].."/simulacrum2x.png", 4, false, false, 25, 19)
local diff_sfx = gm.audio_create_stream(_ENV["!plugins_mod_folder_path"].."/simulacrum.ogg")

local frame = 0

local init = false
local diff_id = -2

local radius = 1000
local void_circles = {}
local void_circle_radius = 250
local void_colour = 10038912
local void_death_time = 18      -- Time (in seconds) before guaranteed death outside the safe zone
local void_death_time_enemy = 27
local surf = -1

local run_start_init = false
local director = nil
local stages_passed = -1
local spawned_rewards = false
local required_waves = 15

local teleporter = nil
local command = nil
local player = nil



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
            0.1,            -- diff_scale           -- Lower leveled on average than on a normal run -> less health
            -1.5,           -- general_scale        -- Stage/loop scaling is insane
            0.0,            -- point_scale
            false,          -- is_monsoon_or_higher
            false           -- allow_blight_spawns  -- Unbalanced for this mode (mfw one-shotted on Wave 9)
        }
        for i = 2, 12 do gm.array_set(class_diff, i, values[i - 1]) end
    end


    -- Simulacrum
    if gm._mod_game_getDifficulty() == diff_id then

        -- Teleporter
        if not Helper.does_instance_exist(teleporter) then
            teleporter = Helper.get_teleporter()
            if Helper.does_instance_exist(teleporter) then teleporter.maxtime = 30 *60 end     -- Set charge time to 30 seconds
        end
        if not Helper.does_instance_exist(command) then command = Helper.find_active_instance(gm.constants.oCommand) end


        -- Director
        if Helper.does_instance_exist(director) then
            
            -- Reset variables when starting a new run
            if director.time_start <= 0 then
                if not run_start_init then
                    run_start_init = true
                    frame = 0
                    stages_passed = -1

                    local base = Helper.find_active_instance(gm.constants.oBase)
                    local pan = Helper.find_active_instance(gm.constants.oPodCameraPan)
                    if Helper.does_instance_exist(base) and Helper.does_instance_exist(pan) and Helper.does_instance_exist(teleporter) then
                        base.x = teleporter.x
                        base.y = teleporter.y
                        pan.x = teleporter.x
                        pan.y = teleporter.y
                        pan.target_y = teleporter.y
                    end
                end
            else run_start_init = false
            end


            -- Run stage enter stuff
            if stages_passed < director.stages_passed then
                stages_passed = director.stages_passed
                spawned_rewards = false

                -- Warp player to teleporter
                local player = Helper.get_client_player()
                if Helper.does_instance_exist(player) then
                    if Helper.does_instance_exist(teleporter) then
                        player.x = teleporter.x
                        player.y = teleporter.y - 12
                    elseif Helper.does_instance_exist(command) then
                        player.x = command.x
                        player.y = command.y - 12
                    end
                end
            end

            -- Replace Divine Teleporters with standard ones until the required number of waves have been cleared
            local tpe = Helper.find_active_instance(gm.constants.oTeleporterEpic)
            if stages_passed < (required_waves - 1) and Helper.does_instance_exist(tpe) then
                gm.instance_create_depth(tpe.x, tpe.y, 2, gm.constants.oTeleporter)
                gm.instance_destroy(tpe)
            end

            -- Spawn multishop terminals after wave completion
            if not spawned_rewards then
                if Helper.does_instance_exist(teleporter) then
                    if teleporter.active >= 3.0 then
                        spawned_rewards = true

                        local wave = math.floor(stages_passed + 1)

                        -- Spawn green items every 3 waves
                        local shop_type = gm.constants.oShop1
                        if wave % 3 == 0 then shop_type = gm.constants.oShop2 end

                        for i = -1, 1, 2 do
                            -- Replace a multishop with a red item every 5 waves (i.e., on TotE)
                            if i == 1 and wave % 5 == 0 then
                                local chest = gm.instance_create_depth(teleporter.x + 80, teleporter.y, 1, gm.constants.oChest5)
                                chest.cost = 0
                            else gm.instance_create_depth(teleporter.x + (i * 128), teleporter.y, 1, shop_type)
                            end
                        end
                    end
                end
            end

            -- Make reward multishops free
            if Helper.does_instance_exist(teleporter) then
                if teleporter.active >= 3.0 then
                    local shops = Helper.get_multishops()
                    if shops then
                        for i = 1, #shops do
                            if shops[i].ff <= 1.0 then shops[i].cost = 0 end
                        end
                    end
                end
            end

        else director = Helper.find_active_instance(gm.constants.oDirectorControl)
        end

    end
end)


gm.post_script_hook(gm.constants.step_actor, function(self, other, result, args)
    -- Deal void fog damage to all actors
    if gm._mod_game_getDifficulty() == diff_id then
        if Helper.does_instance_exist(teleporter) then take_void_damage(self, teleporter)
        elseif Helper.does_instance_exist(command) then take_void_damage(self, command)
        end
    end
end)


gm.pre_code_execute(function(self, other, code, result, flags)
    -- Prevent enemies from spawning before the teleporter is hit, as well as on the ship
    if code.name:match("oDirectorControl_Alarm_1") then
        if (Helper.does_instance_exist(teleporter) and teleporter.time <= 0) or Helper.does_instance_exist(command) then
            self:alarm_set(1, 60)
            return false
        end
    end
end)


gm.post_script_hook(gm.constants.cost_get_base_gold_price_scale, function(self, other, result, args)
    -- Multiply natural interactable costs by 2.3x
    if gm._mod_game_getDifficulty() == diff_id then
        result.value = result.value * 2.3
    end
end)


gm.post_code_execute(function(self, other, code, result, flags)
    if code.name:match("oInit_Draw_7") then
        if gm._mod_game_getDifficulty() == diff_id then

            -- Teleporter draw
            if Helper.does_instance_exist(teleporter) then

                -- Wave count
                text = "Wave "..(math.floor(stages_passed + 1))
                if teleporter.time <= 0 then text = "Begin wave?"
                elseif teleporter.active >= 3.0 then text = "Proceed to next wave"
                end
                gm.draw_text(teleporter.x, teleporter.y + 18, text)

                draw_void_fog(teleporter)

            elseif Helper.does_instance_exist(command) then
                draw_void_fog(command)

            end

        end
    end
end)