local mod = get_mod("QuickMissionLoad")
local Circumstances = require("scripts/settings/circumstance/circumstance_templates")
local Havoc = require("scripts/utilities/havoc")
local Missions = require("scripts/settings/mission/mission_templates")
local StateLoading = require("scripts/game_states/game/state_loading")
local Manifest = mod:io_dofile("QuickMissionLoad/scripts/mods/QuickMissionLoad/mission_manifest")

local MAX_ATTEMPTS = 2
local MAX_IN_FLIGHT = 4
local POLL_INTERVAL = 0.25
local VOTE_TEMPLATE = "mission_vote_matchmaking_immaterium"
local Warmup = {}
local state = mod:persistent_table("warmup")
---@cast state -nil
state.entries = state.entries or {}
state.generation = state.generation or 0

local function release(entry)
    local id = entry.id
    entry.id = nil
    if entry.status == "submitted" then
        state.in_flight = state.in_flight - 1
    end
    entry.status = "released"
    if id and state.package_manager == Managers.package then
        state.package_manager:release(id)
    end
end

function Warmup.clear()
    state.generation = state.generation + 1
    for _, entry in pairs(state.entries) do
        release(entry)
    end
    state.entries = {}
    state.package_manager = nil
    state.in_flight = 0
    state.target = nil
    state.queue = nil
    state.levels = nil
    state.expanded = false
    state.stopped = false
    state.vote_pending = false
    state.matchmaking = false
    state.backend_id = nil
    state.waiting = false
    state.next_poll = 0
    state.next_resolve = 0
end

-- Persistent IDs are released before replacing callbacks on a module reload.
Warmup.clear()

local function reconcile(names, complete)
    local wanted, queue = {}, {}
    for _, name in ipairs(names) do
        wanted[name] = true
        local entry = state.entries[name]
        if not entry then
            entry = { name = name, status = "queued" }
            state.entries[name] = entry
        end
        if entry.status == "queued" then
            queue[#queue + 1] = entry
        end
    end
    for name, entry in pairs(state.entries) do
        if not wanted[name] and (complete or not entry.id) then
            release(entry)
            state.entries[name] = nil
        end
    end
    -- Until new levels resolve their dependencies, old held IDs may still intersect.
    -- Kept entries retain their callback identity; only full cleanup advances the epoch.
    state.queue = queue
    state.cursor = 1
end

local function expedition_snapshot(mission_name)
    local manager = Managers.mechanism
    if not manager or manager:mechanism_name() ~= "expedition" then
        return nil
    end
    local mechanism = manager:current_mechanism()
    if not mechanism or mechanism:mechanism_data().mission_name ~= mission_name then
        return nil
    end
    local spawner = mechanism:levels_spawner()
    local index = mechanism:current_location_index()
    local layout = spawner and spawner:expedition()
    if not index or not layout or not layout[index] then
        return nil
    end
    local levels = {}
    for section_index = math.max(1, index - 1), index do
        local section = layout[section_index]
        for _, level in ipairs(section and section.levels_data or {}) do
            if section_index == index or level.delayed_despawn then
                levels[#levels + 1] = {
                    level_name = level.level_name,
                    theme_tag = section.theme_tag or "default",
                    load_theme = level.is_location or level.is_safe_zone or false,
                }
            end
        end
    end
    return levels
end

local function set_target(mission_name, context)
    local mission = mission_name and Missions[mission_name]
    if not mission or mission.is_hub or mission_name == "tg_shooting_range" or type(mission.level) ~= "string" then
        Warmup.clear()
        return
    end
    local parsed
    if type(context.havoc_data) == "string" then
        local ok, value = pcall(Havoc.parse_data, context.havoc_data)
        if ok then
            parsed = value
        end
    end
    local circumstance = context.circumstance_name and Circumstances[context.circumstance_name]
    local target = {
        mission_name = mission_name,
        circumstance_name = context.circumstance_name,
        theme_tag = context.theme_override or parsed and parsed.theme or circumstance and circumstance.theme_tag or "default",
        circumstances = {},
        is_expedition = mission.expedition_template ~= nil or context.is_expedition == true,
    }
    local seen = {}
    local names = parsed and parsed.circumstances or context.circumstances
    if not names or #names == 0 then
        names = { context.circumstance_name }
    end
    for _, name in ipairs(names) do
        if Circumstances[name] and not seen[name] then
            seen[name] = true
            target.circumstances[#target.circumstances + 1] = name
        end
    end
    table.sort(target.circumstances)
    if target.is_expedition then
        target.expedition_levels = expedition_snapshot(mission_name)
    end
    local key = { mission_name, target.theme_tag, table.concat(target.circumstances, ",") }
    for _, level in ipairs(target.expedition_levels or {}) do
        key[#key + 1] = level.level_name
        key[#key + 1] = level.theme_tag
        key[#key + 1] = tostring(level.load_theme)
    end
    target.key = table.concat(key, "\0")
    state.waiting = false
    if state.target and state.target.key == target.key then
        return
    end
    state.target = target
    state.levels = Manifest.levels(target)
    state.expanded = false
    state.next_resolve = 0
    reconcile(state.levels, false)
end

local function assignment(params)
    state.backend_id = params.backend_mission_id
    local data
    if params.qp ~= "true" and type(params.mission_data) == "string" then
        local ok, decoded = pcall(cjson.decode, params.mission_data)
        if ok and type(decoded) == "table" and type(decoded.mission) == "table" then
            data = decoded.mission
        end
    end
    if not data or type(data.map) ~= "string" then
        local backend_id = state.backend_id
        Warmup.clear()
        state.backend_id = backend_id
        state.waiting = true
        return
    end
    local context = {
        circumstance_name = data.circumstance,
        circumstances = {},
        is_expedition = data.category == "expedition",
    }
    for flag in pairs(type(data.flags) == "table" and data.flags or {}) do
        if type(flag) == "string" then
            if flag:sub(1, 12) == "havoc-theme-" then
                context.theme_override = flag:sub(13)
            elseif flag:sub(1, 11) == "havoc-circ-" then
                context.circumstances[#context.circumstances + 1] = flag:sub(12)
            end
        end
    end
    set_target(data.map, context)
end

function Warmup.vote(event)
    if state.stopped then
        return
    end
    local params = event and event.params
    if not params or not (params.template_name == VOTE_TEMPLATE
        or state.backend_id and state.backend_id == params.backend_mission_id) then
        return
    end
    if event.state == "ONGOING" or event.state == "COMPLETED_APPROVED" then
        if event.state == "ONGOING" or not (state.target or state.waiting)
            or state.backend_id ~= params.backend_mission_id then
            assignment(params)
        end
        state.vote_pending = event.state == "ONGOING"
        state.matchmaking = event.state == "COMPLETED_APPROVED"
    else
        Warmup.clear()
    end
end

function Warmup.party_state(game_state)
    local status = game_state and game_state.status
    if status == "MATCHMAKING_IN_PROGRESS" then
        state.matchmaking = true
    elseif status == "GAME_SESSION_IN_PROGRESS" then
        state.matchmaking = false
    elseif status == "" and state.matchmaking then
        Warmup.clear()
    end
end

function Warmup.transition(next_state, context)
    if not next_state or type(context) ~= "table" then
        return
    end
    local name = context.mission_name
    if name and (name == "hub_ship" or name == "tg_shooting_range" or Missions[name] and Missions[name].is_hub) then
        Warmup.clear()
    elseif not state.stopped and next_state == StateLoading and type(name) == "string" then
        -- Confirmed StateLoading contexts work for quickplay, reconnects and party joiners.
        set_target(name, context)
        state.vote_pending = false
    end
end

function Warmup.stop(mission_name)
    if state.target and state.target.mission_name ~= mission_name then
        Warmup.clear()
    end
    state.stopped = true
    state.queue = nil
end

local function submit(entry, manager)
    if not manager:package_is_known(entry.name) and not Application.can_get_resource("package", entry.name) then
        entry.status = "unavailable"
        return
    end
    local generation = state.generation
    local function loaded(id)
        if generation ~= state.generation or state.entries[entry.name] ~= entry
            or entry.id ~= id or entry.status ~= "submitted" then
            return
        end
        entry.status = "loaded"
        state.in_flight = state.in_flight - 1
    end
    entry.id = manager:load(entry.name, "QuickMissionLoad", loaded, false, false)
    entry.status = "submitted"
    state.package_manager = manager
    state.in_flight = state.in_flight + 1
end

function Warmup.update()
    if state.stopped or not (state.target or state.vote_pending or state.waiting) then
        return
    end
    if not state.queue and not state.vote_pending and not (state.target and state.target.is_expedition) then
        return
    end
    local manager = Managers.package
    if not manager or state.package_manager and state.package_manager ~= manager then
        Warmup.clear()
        return
    end
    local now = os.clock()
    if now >= state.next_poll then
        state.next_poll = now + POLL_INTERVAL
        if state.vote_pending then
            local party = Managers.party_immaterium
            local vote = party and party:party_vote_state()
            local params = vote and vote.params
            if not params or params.backend_mission_id ~= state.backend_id then
                Warmup.clear()
                return
            elseif vote.state ~= "ONGOING" then
                if vote and vote.state == "COMPLETED_APPROVED" then
                    Warmup.vote(vote)
                else
                    Warmup.clear()
                end
                return
            end
        end
        local target = state.target
        if target and target.is_expedition then
            set_target(target.mission_name, {
                circumstance_name = target.circumstance_name,
                circumstances = target.circumstances,
                theme_override = target.theme_tag,
                is_expedition = true,
            })
        end
    end
    local queue = state.queue
    if not queue then
        return
    end
    local attempts = 0
    while state.cursor <= #queue and attempts < MAX_ATTEMPTS and state.in_flight < MAX_IN_FLIGHT do
        local entry = queue[state.cursor]
        state.cursor = state.cursor + 1
        if entry.status == "queued" then
            attempts = attempts + 1
            submit(entry, manager)
        end
    end
    if state.cursor <= #queue then
        return
    end
    if state.expanded then
        state.queue = nil
        return
    end
    if now < state.next_resolve then
        return
    end
    for _, name in ipairs(state.levels) do
        local entry = state.entries[name]
        if entry.status == "submitted" or entry.status == "queued" then
            return
        end
    end
    local loaded_levels = {}
    for _, name in ipairs(state.levels) do
        loaded_levels[name] = state.entries[name].status == "loaded"
    end
    local packages = Manifest.resolve(state.target, state.levels, loaded_levels)
    if packages then
        reconcile(packages, true)
        state.expanded = true
    else
        state.next_resolve = now + POLL_INTERVAL
    end
end

function Warmup.enable()
    Warmup.clear()
    local presence = Managers.presence
    if presence and presence._current_game_state_name == "StateLoading" then
        -- A reload cannot recover whether resources_started already fired.
        state.stopped = true
        return
    end
    local party = Managers.party_immaterium
    local game_state = party and party:party_game_state()
    if game_state and game_state.status ~= "GAME_SESSION_IN_PROGRESS" then
        Warmup.vote(party:party_vote_state())
        Warmup.party_state(game_state)
    end
end

return Warmup
