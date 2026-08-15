-- Hyprland default apps

TERMINAL     = "kitty"
FILE_MANAGER = "dolphin"
BROWSER      = "firefox"
EDITOR       = "gnome-text-editor --new-window"
CALCULATOR   = "gnome-calculator"

-- Detect current machine
local hostname_file = io.open("/etc/hostname", "r")
local hostname = hostname_file and hostname_file:read("*l") or "unknown"

if hostname_file then
    hostname_file:close()
end

-- Load machine-specific profile
local ok, host = pcall(require, "hosts." .. hostname)

if not ok then
    error(
        "No Hyprland host profile found for '" ..
        hostname ..
        "': " ..
        tostring(host)
    )
end

-- Monitors
MONITOR1 = host.monitor1 or ""
MONITOR2 = host.monitor2 or ""
MONITOR3 = host.monitor3 or ""
PRIMARY_MONITOR = host.primary_monitor or MONITOR1

-- Workspaces
NUM_WPM = host.workspaces or 6

-- Machine metadata
GPU_VENDOR = host.gpu or "unknown"
