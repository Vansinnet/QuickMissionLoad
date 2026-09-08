---@class QuickMissionLoadMod: DMFMod
local mod = get_mod("QuickMissionLoad")
local Warmup = mod:io_dofile("QuickMissionLoad/scripts/mods/QuickMissionLoad/mission_warmup")
local enabled = false
local preload_missions = mod:get("preload_missions")
local skip_mission_briefing = mod:get("skip_mission_briefing")
local event_manager

local function unregister_events()
    if event_manager then
        event_manager:unregister(mod, "event_loading_resources_started")
        event_manager:unregister(mod, "event_loading_finished")
        event_manager = nil
    end
end

local function register_events()
    if event_manager == Managers.event then
        return
    end
    unregister_events()
    event_manager = Managers.event
    if event_manager then
        event_manager:register(mod, "event_loading_resources_started", "event_loading_resources_started")
        event_manager:register(mod, "event_loading_finished", "event_loading_finished")
    end
end

mod.event_loading_resources_started = function(_, mission_name)
    if enabled and preload_missions then
        Warmup.stop(mission_name)
    end
end

mod.event_loading_finished = function()
    Warmup.clear()
end

mod.update = function()
    if enabled and preload_missions then
        register_events()
        Warmup.update()
    end
end

mod.on_enabled = function()
    preload_missions = mod:get("preload_missions")
    skip_mission_briefing = mod:get("skip_mission_briefing")
    enabled = not DEDICATED_SERVER
    if enabled and preload_missions then
        register_events()
        Warmup.enable()
    end
end

mod.on_setting_changed = function(setting_id)
    if setting_id == "preload_missions" then
        preload_missions = mod:get(setting_id)
        if enabled and preload_missions then
            register_events()
            Warmup.enable()
        elseif not preload_missions then
            unregister_events()
            Warmup.clear()
        end
    elseif setting_id == "skip_mission_briefing" then
        skip_mission_briefing = mod:get(setting_id)
    end
end

mod.on_disabled = function()
    enabled = false
    unregister_events()
    Warmup.clear()
end

mod.on_game_state_changed = function(status, name)
    if status == "exit" and name == "StateGame" then
        enabled = false
        unregister_events()
        Warmup.clear()
    elseif status == "enter" then
        if name == "StateTitle" or name == "StateMainMenu" or name == "StateExitToMainMenu" or name == "StateError" then
            Warmup.clear()
        end
        if mod:is_enabled() and not DEDICATED_SERVER then
            enabled = true
            if preload_missions then
                register_events()
            end
        end
    end
end

mod.on_unload = function(exit_game)
    enabled = false
    if exit_game then
        event_manager = nil
    else
        unregister_events()
    end
    Warmup.clear()
end

mod:hook("MissionIntroView", "_play_mission_brief_vo", function(func, self, mission_name, mission_giver_vo, circumstance_name)
    if enabled and skip_mission_briefing then
        self.mission_briefing_done = true
        self.done_at = nil
        return
    end
    return func(self, mission_name, mission_giver_vo, circumstance_name)
end)

mod:hook("LocalWaitForMissionBriefingDoneState", "update", function(func, self, dt)
    local ui = Managers.ui
    if enabled and skip_mission_briefing and ui and not ui:view_active("lobby_view") then
        local intro = ui:view_active("mission_intro_view") and ui:view_instance("mission_intro_view")
        -- Enabling mid-briefing must not advance while its existing VO is still playing.
        if not intro or intro.mission_briefing_done then
            return "mission_briefing_done"
        end
    end
    return func(self, dt)
end)

mod:hook_safe("PartyImmateriumManager", "_handle_party_vote_update_event", function(_, event)
    if enabled and preload_missions then
        Warmup.vote(event)
    end
end)

mod:hook_safe("PartyImmateriumManager", "_handle_party_game_state_update_event", function(party, _)
    if enabled and preload_missions then
        Warmup.party_state(party:party_game_state())
    end
end)

mod:hook("MechanismManager", "wanted_transition", function(func, self)
    local next_state, context = func(self)
    if enabled and preload_missions then
        Warmup.transition(next_state, context)
    end
    return next_state, context
end)

return mod
