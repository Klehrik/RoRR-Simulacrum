-- Void Fog

local void_circles = {}
local surf = -1
local frame = 0


function add_void_actor()
    local obj = Object.new("klehrik", "simulacrumVoid", Object.PARENT.enemyFlying)
    obj.obj_sprite = Resources.sprite_load("klehrik", "simulacrumVoid", PATH.."simulacrumVoid.png", 1, 20, 23)
    obj.obj_depth = -100

    obj:onDraw(function(inst)
        gm.draw_set_circle_precision(64)

        -- Create void fog surface
        local cam = gm.view_get_camera(0)
        if gm.surface_exists(surf) == 0.0 then surf = gm.surface_create(gm.camera_get_view_width(cam), gm.camera_get_view_height(cam)) end
        gm.surface_set_target(surf)
        gm.draw_clear_alpha(0, 0)

        -- Draw void fog base
        gm.draw_set_alpha(0.5)
        gm.draw_rectangle_colour(0, 0, gm.camera_get_view_width(cam), gm.camera_get_view_height(cam), void_color, void_color, void_color, void_color, false)
        gm.draw_set_alpha(1)

        -- Punch hole in void fog
        gm.gpu_set_blendmode(3) -- bm_subtract
        gm.draw_circle(inst.x - gm.camera_get_view_x(cam), inst.y - gm.camera_get_view_y(cam), radius, false)
        gm.gpu_set_blendmode(0) -- bm_normal

        -- Draw void fog surface
        gm.surface_reset_target()
        gm.draw_surface(surf, gm.camera_get_view_x(cam), gm.camera_get_view_y(cam))


        -- Add purple circles to draw
        frame = frame + 1
        if frame % 15 == 0 then table.insert(void_circles, void_circle_radius) end

        -- Draw purple circles
        for i = #void_circles, 1, -1 do
            local ease = Helper.ease_out(void_circles[i]/void_circle_radius, 3)
            gm.draw_set_alpha(1 - ease)
            local r = ease * void_circle_radius
            gm.draw_circle_colour(inst.x, inst.y, radius + r, void_color, void_color, true)
            gm.draw_set_alpha(1)

            void_circles[i] = void_circles[i] - 1
            if void_circles[i] <= 0 then table.remove(void_circles, i) end
        end

        -- Draw safe zone radius around teleporter
        gm.draw_set_alpha(0.3)
        gm.draw_circle(inst.x, inst.y, radius, true)
        gm.draw_set_alpha(1)

        gm.draw_set_circle_precision(24)
    end)
end


function take_void_damage(actor, void_actor)
    if not void_actor:exists() then return end

    -- While in the void fog, take damage equal to a gradually increasing portion of current health
    -- Guaranteed death after some time, but not fatal before that
    local actorData = actor:get_data()
    actorData.time_outside = actorData.time_outside or 0

    local dist = gm.point_distance(actor.x, actor.y, void_actor.x, void_actor.y)
    if dist > radius then
        if actor.invincible == false then actor.invincible = 0 end
        if actor.invincible <= 0 then
            actorData.time_outside = actorData.time_outside + 1
            if actorData.time_outside % 60 == 0 then
                local int = math.floor(actorData.time_outside / 60)
                local dtime = void_death_time
                if actor.team == 2 then dtime = void_death_time_enemy end
                
                local attack_info = void_actor:fire_direct(actor, actor.hp * Helper.ease_in(int/dtime)).attack_info
                attack_info:use_raw_damage()
                attack_info:set_color(void_color)
            end
        end
    else actorData.time_outside = 0
    end
end