-- CachyOS Hyprland Configuration

require("config.animations")
require("config.autostart")
require("config.colors")
require("config.decorations")
require("config.variables")
require("config.environment")
require("config.inputs")
require("config.binds")
require("config.misc")
require("config.monitors")
require("config.windowrules")
require("config.cheatsheet")
require("config.windowhide")
require("config.workspaces")

-- Apply Noctalia colors when the generated theme exists
local noctalia_ok, noctalia = pcall(require, "noctalia")

if noctalia_ok then
    noctalia.apply_theme()
end

-- For Noctalia Color templates
require("noctalia").apply_theme()
