return {
    version = "1.0.1",
    run = function()
        fassert(rawget(_G, "new_mod"), "`QuickMissionLoad` failed loading DMF.")
        new_mod("QuickMissionLoad", {
            mod_script = "QuickMissionLoad/scripts/mods/QuickMissionLoad/QuickMissionLoad",
            mod_data = "QuickMissionLoad/scripts/mods/QuickMissionLoad/QuickMissionLoad_data",
            mod_localization = "QuickMissionLoad/scripts/mods/QuickMissionLoad/QuickMissionLoad_localization",
        })
    end,
    packages = {},
}
