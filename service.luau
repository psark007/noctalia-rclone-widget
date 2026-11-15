--!nonstrict
-- Poll Rclone status once for the plugin and publish it to the widget/panel.

local backend = noctalia.pluginDir() .. "/backend.py"

local function refresh()
    local args = { "/usr/bin/python3", backend, "--config-dir", noctalia.expandPath(noctalia.getConfig("config_dir")), "snapshot" }
    noctalia.runAsync(args, function(result)
        if result.exitCode == 0 then
            local data = noctalia.json.decode(result.stdout or "")
            if type(data) == "table" then
                noctalia.state.set("rclone_status", data)
            end
        end
        noctalia.runAsync("sleep 2", refresh)
    end, 15000)
end

refresh()
