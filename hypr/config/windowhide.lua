local home = os.getenv("HOME")

hl.bind(
    "SUPER + M",
    hl.dsp.exec_cmd("bash " .. home .. "/.config/hypr/scripts/window-hide-toggle")
)
