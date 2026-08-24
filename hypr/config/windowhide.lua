hl.bind("SUPER + M", function()
    if hl.get_workspace("special:minimized") then
        hl.dispatch(hl.dsp.window.move({
            workspace = hl.get_active_workspace(),
            window = "tag:minimized",
        }))
        hl.dispatch(hl.dsp.window.clear_tags({ window = "tag:minimized" }))
    else
        local window = hl.get_active_window()

        if not window then
            return
        end

        hl.dispatch(hl.dsp.window.tag({ tag = "minimized", window = window }))
        hl.dispatch(hl.dsp.window.move({ workspace = "special:minimized", follow = false }))
    end
end)
