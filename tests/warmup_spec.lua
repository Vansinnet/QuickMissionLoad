-- Standalone behavioral harness, not loaded by DMF. Run from the workspace root.
local root = "mods/active/QuickMissionLoad/scripts/mods/QuickMissionLoad/"
local state, live, history, hooks, events = {}, {}, {}, {}, {}
local next_id, submissions, releases, clock = 0, 0, 0, 0
local current_vote = {}
local game_state = { status = "" }
local enabled = true
local items_ready = true
local loading_state = {}
local missions = {
    a = { level = "a", game_mode_name = "coop" },
    b = { level = "b", game_mode_name = "coop" },
    missing = { level = "missing", game_mode_name = "coop" },
    hub_ship = { level = "hub", is_hub = true },
    tg_shooting_range = { level = "range" },
    expedition = { level = "expedition", game_mode_name = "coop", expedition_template = "layout" },
}
local manager = {}
function manager:load(name, reference, callback, priority, resident)
    assert(reference == "QuickMissionLoad" and priority == false and resident == false)
    next_id = next_id + 1
    submissions = submissions + 1
    local call = { id = next_id, name = name, callback = callback }
    live[next_id], history[next_id] = call, call
    return next_id
end
function manager:release(id)
    assert(live[id], "unknown or double-released ID")
    live[id] = nil
    releases = releases + 1
end
function manager:package_is_known()
    return false
end
function manager:is_anything_loading_now()
    error("scheduler must not wait behind its own package loads")
end
local mod = {}
local preload_missions = true
local skip_briefing = true
local setting_reads = 0
function mod:get(setting_id)
    setting_reads = setting_reads + 1
    if setting_id == "preload_missions" then
        return preload_missions
    end
    assert(setting_id == "skip_mission_briefing")
    return skip_briefing
end
function mod:localize(key)
    return key
end
function mod:persistent_table()
    return state
end
function mod:is_enabled()
    return enabled
end
function mod:hook(class, method, handler)
    hooks[class .. "." .. method] = handler
end
mod.hook_safe = mod.hook
local managers = {
    package = manager,
    presence = { _current_game_state_name = "StateGameplay" },
    party_immaterium = {
        party_vote_state = function() return current_vote end,
        party_game_state = function() return game_state end,
    },
    event = {
        register = function(_, _, name, method) events[name] = method end,
        unregister = function(_, _, name) events[name] = nil end,
    },
}
local definitions = {}
local function source(path, value)
    definitions["scripts/" .. path] = value
end
source("game_states/game/state_loading", loading_state)
source("settings/mission/mission_templates", missions)
source("settings/circumstance/circumstance_templates", { storm = { theme_tag = "storm", mutators = { "storm" } } })
source("utilities/havoc", { parse_data = function() return { theme = "storm", circumstances = { "storm" } } end })
source("utilities/breed_resource_dependencies", { generate = function() return {} end })
source("settings/game_mode/game_mode_settings", { coop = { packages = { "shared" } } })
source("foundation/managers/package/utilities/item_package", {
    level_resource_dependency_packages = function(_, level)
        local call
        for _, candidate in pairs(live) do
            if candidate.name == level then call = candidate end
        end
        assert(call and call.done, "dependencies resolved before level completion")
        return { [level .. ":items"] = true, shared = true }
    end,
})
source("backend/master_items", { get_cached = function() return items_ready and {} or nil end })
source("ui/views/mission_intro_view/mission_intro_view_settings", { intro_levels_by_zone_id = { default = { level_name = "intro" } } })
source("settings/mutator/mutator_mininion_visual_overrides_settings", {})
source("settings/mutator/mutator_templates", { storm = { asset_package = "storm_asset" } })
source("foundation/managers/package/utilities/theme_package", {
    level_resource_dependency_packages = function(_, theme)
        assert(theme, "nil theme was not resolved to default")
        return { "theme:" .. theme }
    end,
})
source("ui/views/views", { mission_intro_view = { preload_in_mission = "always", package = "intro_ui" } })
source("ui/hud/hud_elements_player", { { class_name = "hud", package = "hud" } })
source("ui/hud/hud_elements_spectator", { { class_name = "hud", package = "must_not_load" } })
local payloads = {}
local env = setmetatable({
    Managers = managers,
    GameParameters = {},
    DEDICATED_SERVER = false,
    Application = { can_get_resource = function(_, name) return name ~= "missing" end },
    cjson = { decode = function(value) return assert(payloads[value]) end },
    os = { clock = function() return clock end },
    get_mod = function() return mod end,
    require = function(path) return assert(definitions[path], path) end,
}, { __index = _G })
function mod:io_dofile(path)
    return assert(loadfile("mods/active/" .. path .. ".lua", "t", env))()
end
local warmup = assert(loadfile(root .. "mission_warmup.lua", "t", env))()
local function by_name(name)
    for id, call in pairs(live) do
        if call.name == name then return id, call end
    end
end
local function tick()
    clock = clock + 0.05
    local before = submissions
    warmup.update()
    assert(submissions - before <= 2, "per-frame bound exceeded")
    assert(state.in_flight >= 0 and state.in_flight <= 4, "in-flight accounting corrupted")
end
local function finish_except(exceptions)
    for id, call in pairs(live) do
        if not call.done and not (exceptions and exceptions[call.name]) then
            call.done = true
            call.callback(id)
        end
    end
end
local function drain(exceptions)
    for _ = 1, 40 do
        tick()
        finish_except(exceptions)
    end
end
local function vote(mission, theme)
    local token = mission .. (theme or "")
    payloads[token] = { mission = { map = mission, circumstance = theme } }
    current_vote = {
        state = "ONGOING",
        params = { template_name = "mission_vote_matchmaking_immaterium", backend_mission_id = token, mission_data = token },
    }
    warmup.vote(current_vote)
end

vote("a")
drain({ shared = true, ["theme:default"] = true })
local shared_id, shared_call = by_name("shared")
local default_id, default_call = by_name("theme:default")
local intro_id = by_name("intro")
assert(shared_id and default_id and intro_id)
assert(not by_name("must_not_load"))
local before = releases
vote("b", "storm")
assert(releases == before, "references dropped before replacement dependencies were known")
tick()
assert(by_name("shared") == shared_id and by_name("intro") == intro_id)
shared_call.done = true
shared_call.callback(shared_id)
shared_call.callback(shared_id)
assert(state.in_flight >= 0, "duplicate completion was accepted")
drain({ ["theme:default"] = true })
assert(by_name("shared") == shared_id and by_name("intro") == intro_id)
assert(not live[default_id] and not by_name("a") and not by_name("a:items"))
before = state.in_flight
default_call.callback(default_id)
assert(state.in_flight == before, "released callback changed the new target")

local b_id = by_name("b")
vote("b")
drain()
assert(by_name("b") == b_id and by_name("shared") == shared_id)
before = releases
vote("b")
drain()
assert(releases == before, "same target churned references")
warmup.stop("b")
before = submissions
warmup.transition(loading_state, { mission_name = "a" })
drain()
assert(submissions == before and next(live), "stop must retain IDs without submitting")
warmup.clear()
assert(not next(live))
shared_call.callback(shared_id)
assert(state.in_flight == 0)

current_vote = {
    state = "ONGOING",
    params = { template_name = "mission_vote_matchmaking_immaterium", backend_mission_id = "qp", qp = "true" },
}
warmup.vote(current_vote)
drain()
assert(not next(live), "quickplay guessed a mission")
warmup.transition(loading_state, { mission_name = "a", havoc_data = "encoded" })
current_vote.state = "COMPLETED_APPROVED"
warmup.vote(current_vote)
drain()
assert(by_name("a") and by_name("theme:storm") and by_name("storm_asset"))
warmup.party_state({ status = "MATCHMAKING_IN_PROGRESS" })
warmup.party_state({ status = "" })
assert(not next(live), "matchmaking cancellation retained IDs")

vote("a")
tick()
current_vote = {}
drain()
assert(not next(live), "lost vote did not clean up")
vote("a")
tick()
warmup = assert(loadfile(root .. "mission_warmup.lua", "t", env))()
assert(not next(live), "module reload leaked IDs")
items_ready = false
vote("a")
drain()
items_ready = true
drain()
assert(by_name("shared"), "delayed master items never resumed")
warmup.clear()
vote("missing")
drain()
assert(not by_name("missing") and not by_name("missing:items"))
warmup.clear()

local layout = {
    { levels_data = { { level_name = "prior_drop" }, { level_name = "prior_keep", delayed_despawn = true } } },
    { levels_data = { { level_name = "location", is_location = true }, { level_name = "connector" } } },
    { levels_data = { { level_name = "future" } } },
}
local mechanism = {
    mechanism_data = function() return { mission_name = "expedition" } end,
    current_location_index = function() return 2 end,
    levels_spawner = function() return { expedition = function() return layout end } end,
}
managers.mechanism = {
    mechanism_name = function() return "expedition" end,
    current_mechanism = function() return mechanism end,
}
vote("expedition")
drain()
assert(by_name("prior_keep") and by_name("location") and by_name("connector"))
assert(not by_name("prior_drop") and not by_name("future"))
assert(layout[1].levels_data[2].delayed_despawn, "snapshot mutated the layout")
local location_id = by_name("location")
layout[2].theme_tag = "storm"
drain()
assert(by_name("location") == location_id and by_name("theme:storm"))
warmup.clear()
managers.mechanism = nil

assert(loadfile(root .. "QuickMissionLoad.lua", "t", env))()
mod.on_enabled()
local hook = hooks["MechanismManager.wanted_transition"]
local context = { mission_name = "a" }
local result, returned = hook(function() return loading_state, context end, {})
assert(result == loading_state and returned == context, "transition returns changed")
mod.update()
mod.event_loading_resources_started(mod, "a")
assert(next(live) and state.stopped)
mod.event_loading_finished()
assert(not next(live))
for _, edge in ipairs({ "disable", "unload", "title", "error", "exit" }) do
    mod.on_enabled()
    hook(function() return loading_state, context end, {})
    mod.update()
    assert(next(live))
    if edge == "disable" then
        enabled = false
        mod.on_disabled()
    elseif edge == "unload" then
        mod.on_unload(false)
    elseif edge == "exit" then
        mod.on_game_state_changed("exit", "StateGame")
    else
        mod.on_game_state_changed("enter", edge == "title" and "StateTitle" or "StateError")
    end
    assert(not next(live), edge .. " leaked IDs")
    enabled = true
end
mod.on_disabled()
assert(not next(events))
assert(submissions == releases, "not all owned IDs were released exactly once")

local data = assert(loadfile(root .. "QuickMissionLoad_data.lua", "t", env))()
local preload_widget, briefing_widget = data.options.widgets[1], data.options.widgets[2]
assert(preload_widget.setting_id == "preload_missions" and preload_widget.default_value == true)
assert(briefing_widget.setting_id == "skip_mission_briefing" and briefing_widget.default_value == true)
local localization = assert(loadfile(root .. "QuickMissionLoad_localization.lua", "t", env))()
local widget = briefing_widget
assert(localization[widget.setting_id].en and localization[widget.setting_id .. "_description"].en)
assert(localization[preload_widget.setting_id].en and localization[preload_widget.setting_id .. "_description"].en)
local intro_hook = hooks["MissionIntroView._play_mission_brief_vo"]
local wait_hook = hooks["LocalWaitForMissionBriefingDoneState.update"]
local view = { mission_briefing_done = false, done_at = 100 }
local wait_state, lobby, intro_active = {}, false, true
local original_calls = 0
local function original_intro(self, mission, giver, circumstance)
    assert(self == view and mission == "a" and giver == "none" and circumstance == nil)
    original_calls = original_calls + 1
    return nil, "intro", nil
end
local function original_wait(self, dt)
    assert(self == wait_state and dt == 0.1)
    original_calls = original_calls + 1
    return nil, "wait", nil
end
local function check_original(handler, original, ...)
    local calls = original_calls
    local values = table.pack(handler(original, ...))
    assert(original_calls == calls + 1 and values.n == 3 and values[1] == nil and values[3] == nil)
    assert(values[2] == (original == original_intro and "intro" or "wait"), "original returns changed")
end
managers.ui = {
    view_active = function(_, name)
        return name == "lobby_view" and lobby or name == "mission_intro_view" and intro_active
    end,
    view_instance = function(_, name)
        assert(name == "mission_intro_view")
        return view
    end,
}
check_original(intro_hook, original_intro, view, "a", "none", nil)
check_original(wait_hook, original_wait, wait_state, 0.1)
assert(not view.mission_briefing_done and view.done_at == 100, "disabled hook mutated intro")
mod.on_enabled()
local reads = setting_reads
intro_hook(function() error("skipped intro called original") end, view, "a", "none", nil)
assert(view.mission_briefing_done and view.done_at == nil)
assert(wait_hook(original_wait, wait_state, 0.1) == "mission_briefing_done")
assert(setting_reads == reads, "hooks read settings instead of cache")
lobby = true
check_original(wait_hook, original_wait, wait_state, 0.1)
lobby = false
local ui = managers.ui
managers.ui = nil
check_original(wait_hook, original_wait, wait_state, 0.1)
managers.ui = ui
skip_briefing = false
mod.on_setting_changed("skip_mission_briefing")
check_original(intro_hook, original_intro, view, "a", "none", nil)
check_original(wait_hook, original_wait, wait_state, 0.1)
view.mission_briefing_done, view.done_at = false, 100
skip_briefing = true
mod.on_setting_changed("skip_mission_briefing")
check_original(wait_hook, original_wait, wait_state, 0.1)
assert(not view.mission_briefing_done and view.done_at == 100, "mid-VO enable changed existing playback")
view.mission_briefing_done = true
assert(wait_hook(original_wait, wait_state, 0.1) == "mission_briefing_done", "remaining timer not bypassed")
intro_active = false
assert(wait_hook(original_wait, wait_state, 0.1) == "mission_briefing_done")
intro_active, view = true, nil
assert(wait_hook(original_wait, wait_state, 0.1) == "mission_briefing_done")
reads = setting_reads
mod.on_setting_changed("unrelated")
assert(setting_reads == reads)
mod.on_disabled()
skip_briefing = false
mod.on_enabled()
check_original(wait_hook, original_wait, wait_state, 0.1)
env.DEDICATED_SERVER = true
skip_briefing = true
mod.on_enabled()
check_original(wait_hook, original_wait, wait_state, 0.1)
check_original(intro_hook, original_intro, view, "a", "none", nil)
mod.on_disabled()
assert(not next(events) and not next(live))
print("QuickMissionLoad briefing checks passed: defaults, cache, toggles, lobby/UI gates, active VO, timer, returns and dedicated-server guard.")
print("QuickMissionLoad behavioral checks passed: reconciliation, callbacks, bounds, handoff, votes, quickplay/Havoc, reload and cleanup.")
