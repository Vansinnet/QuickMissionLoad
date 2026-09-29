local BreedResourceDependencies = require("scripts/utilities/breed_resource_dependencies")
local Circumstances = require("scripts/settings/circumstance/circumstance_templates")
local GameModes = require("scripts/settings/game_mode/game_mode_settings")
local ItemPackage = require("scripts/foundation/managers/package/utilities/item_package")
local MasterItems = require("scripts/backend/master_items")
local Missions = require("scripts/settings/mission/mission_templates")
local IntroSettings = require("scripts/ui/views/mission_intro_view/mission_intro_view_settings")
local VisualOverrides = require("scripts/settings/mutator/mutator_minion_visual_overrides_settings")
local Mutators = require("scripts/settings/mutator/mutator_templates")
local ThemePackage = require("scripts/foundation/managers/package/utilities/theme_package")
local Views = require("scripts/ui/views/views")

local Manifest = {}

local function add(list, seen, name)
    if type(name) == "string" and name ~= "" and not seen[name] then
        seen[name] = true
        list[#list + 1] = name
    end
end

local function add_array(list, seen, values)
    for _, name in pairs(values or {}) do
        add(list, seen, name)
    end
end

local function add_map(list, seen, values)
    for name in pairs(values or {}) do
        add(list, seen, name)
    end
end

local function mission_views()
    -- DMF is a PC mod; these are ViewLoader's PC preload policies.
    local preload = not GameParameters.disable_view_preload
    local policies = {
        always_even_with_debug = true,
        always = preload,
        not_ps5 = preload,
        not_ps5_nor_lockhart = preload,
    }
    local views = {}
    for name, settings in pairs(Views) do
        if policies[settings.preload_in_mission] then
            views[#views + 1] = name
        end
    end
    table.sort(views)
    return views
end

function Manifest.levels(target)
    local mission = Missions[target.mission_name]
    local levels, seen = {}, {}
    add(levels, seen, mission.level)
    for _, name in ipairs(mission_views()) do
        add_array(levels, seen, Views[name].levels)
        if name == "mission_intro_view" then
            local intro = IntroSettings.intro_levels_by_zone_id[mission.zone_id]
                or IntroSettings.intro_levels_by_zone_id.default
            add(levels, seen, intro and intro.level_name)
        end
    end
    for _, level in ipairs(target.expedition_levels or {}) do
        add(levels, seen, level.level_name)
    end
    return levels
end

local function spawner_packages(packages, seen, nodes)
    for _, node in ipairs(nodes or {}) do
        local template = node.template
        if template then
            add(packages, seen, template.asset_package)
            spawner_packages(packages, seen, template.spawners)
        end
    end
end

function Manifest.resolve(target, levels, loaded)
    local items = MasterItems.get_cached()
    if not items then
        return nil
    end

    local packages, seen = {}, {}
    local mission = Missions[target.mission_name]
    add_array(packages, seen, levels)
    for _, name in ipairs(levels) do
        if loaded[name] then
            add_map(packages, seen, ItemPackage.level_resource_dependency_packages(items, name))
        end
    end
    if loaded[mission.level] then
        -- LevelLoader also resolves a nil theme through ThemePackage's default fallback.
        add_array(packages, seen, ThemePackage.level_resource_dependency_packages(mission.level, target.theme_tag))
    end
    for _, level in ipairs(target.expedition_levels or {}) do
        if level.load_theme and loaded[level.level_name] then
            add_array(packages, seen, ThemePackage.level_resource_dependency_packages(level.level_name, level.theme_tag))
        end
    end

    local game_mode = GameModes[mission.game_mode_name]
    add_array(packages, seen, game_mode and game_mode.packages)
    local hud = mission.hud_elements and require(mission.hud_elements)
    local classes = {}
    local function add_hud(definitions)
        for _, definition in ipairs(definitions or {}) do
            if not classes[definition.class_name] then
                classes[definition.class_name] = true
                add(packages, seen, definition.package)
            end
        end
    end
    if hud then
        add_hud(hud)
    else
        add_hud(require("scripts/ui/hud/hud_elements_player"))
        add_hud(require("scripts/ui/hud/hud_elements_spectator"))
    end

    for _, name in ipairs(mission_views()) do
        local view = Views[name]
        if type(view.package) == "table" then
            add_array(packages, seen, view.package)
        else
            add(packages, seen, view.package)
        end
        if name == "loading_view" then
            local background = view.backgrounds and view.backgrounds[1]
            add(packages, seen, background and view.dynamic_package_folder .. background)
        end
    end

    local mutators = {}
    for _, name in ipairs(target.circumstances) do
        local circumstance = Circumstances[name]
        for _, mutator_name in ipairs(circumstance and circumstance.mutators or {}) do
            mutators[mutator_name] = true
        end
    end
    for name in pairs(mutators) do
        local mutator = Mutators[name]
        if mutator then
            add(packages, seen, mutator.asset_package)
            spawner_packages(packages, seen, mutator.spawners)
            if mutator.class == "scripts/managers/mutator/mutators/mutator_minion_visual_override" then
                local override_items = {}
                for _, entry in pairs(VisualOverrides[mutator.template_name] or {}) do
                    for _, slot in pairs(entry.item_slot_data or {}) do
                        for _, item in ipairs(slot.items or {}) do
                            override_items[#override_items + 1] = item
                        end
                    end
                    for _, item in pairs(entry.has_gib_override or {}) do
                        override_items[#override_items + 1] = item
                    end
                end
                add_map(packages, seen, BreedResourceDependencies.generate({ items = override_items }, items))
            end
        end
    end
    table.sort(packages)
    return packages
end

return Manifest
