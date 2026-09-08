return {
    mod_name = { en = "Quick Mission Load" },
    mod_description = {
        en = "Preloads packages for the selected or assigned mission while waiting to enter it. Uses a fixed, bounded package warmup and optionally skips mission briefing VO and its minimum wait. Does not bypass resource or network readiness. May increase memory use.",
    },
    preload_missions = { en = "Preload missions" },
    preload_missions_description = {
        en = "Request packages for the selected or assigned mission before normal loading begins. Enabled by default. Turn this off to skip package warmup and release any packages it currently holds.",
    },
    skip_mission_briefing = { en = "Skip briefing" },
    skip_mission_briefing_description = {
        en = "Skip briefing VO and its minimum wait for fastest local entry once normal loading is ready. Enabled by default; turn off to keep warmup only. VO changes apply to the next intro: a briefing already playing finishes naturally, then any remaining minimum wait is skipped. Disabling does not restart skipped VO. The lobby gate is preserved.",
    },
}
