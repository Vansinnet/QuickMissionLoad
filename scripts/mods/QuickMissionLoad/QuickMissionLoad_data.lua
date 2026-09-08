local mod = get_mod("QuickMissionLoad")

return {
    name = mod:localize("mod_name"),
    description = mod:localize("mod_description"),
    is_togglable = true,
    options = {
        widgets = {
            {
                setting_id = "preload_missions",
                type = "checkbox",
                default_value = true,
            },
            {
                setting_id = "skip_mission_briefing",
                type = "checkbox",
                default_value = true,
            },
        },
    },
}
