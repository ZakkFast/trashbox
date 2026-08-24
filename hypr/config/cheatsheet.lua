local home = os.getenv("HOME")

hl.bind(
    "SUPER + H",
    hl.dsp.exec_cmd("bash " .. home .. "/.config/hypr/scripts/cheatsheet")
)

hl.window_rule({
    match = { class = "^(hypr-cheatsheet)$" },
    float = true,
    center = true,
    size = {
        "min(1200, monitor_w*0.75)",
        "min(900, monitor_h*0.82)",
    },
})
