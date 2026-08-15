-- Workspace rules wiki https://wiki.hypr.land/Configuring/Basics/Workspace-Rules/
-- Add your workspace rules here. Increment the workspace number as you go. Do not have duplicate workspaces.

hl.workspace_rule({
    workspace = "1",
    monitor = MONITOR1,
    default = true,
    persistent = true,
    default_name = "DEV",
})

hl.workspace_rule({
    workspace = "2",
    monitor = MONITOR1,
    persistent = true,
    default_name = "SERVER",
})

hl.workspace_rule({
    workspace = "3",
    monitor = MONITOR1,
    persistent = true,
    default_name = "NOT_PORN",
})

hl.workspace_rule({
    workspace = "4",
    monitor = MONITOR1,
    persistent = true,
    default_name = "GAMING",
})

hl.workspace_rule({
    workspace = "5",
    monitor = MONITOR1,
    persistent = true,
    default_name = "BRAIN_ROT",
})
