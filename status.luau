--!nonstrict
-- Read-only status for the user's existing Rclone Mounts & Tasks backend.
local backend = noctalia.pluginDir() .. "/backend.py"
local busy = false

local function refresh()
    if busy then return end
    busy = true
    local ok = noctalia.runAsync({ "/usr/bin/python3", backend, "snapshot" }, function(result)
        busy = false
        if result.exitCode ~= 0 then
            barWidget.setGlyph("cloud-off")
            barWidget.setGlyphColor("error")
            barWidget.setText("")
            barWidget.setTooltip("Rclone status unavailable; check the local Rclone Mounts & Tasks setup.")
            return
        end

        local data = noctalia.json.decode(result.stdout)
        if type(data) ~= "table" then
            barWidget.setGlyph("cloud-off")
            barWidget.setGlyphColor("error")
            barWidget.setTooltip("Could not read Rclone status.")
            return
        end

        local mounted, totalMounts, running, totalTasks = 0, 0, 0, 0
        local lines = {}
        for _, mount in ipairs(data.mounts or {}) do
            totalMounts += 1
            if mount.mounted then mounted += 1 end
            table.insert(lines, string.format("%s: %s", mount.label, mount.status))
        end
        for _, task in ipairs(data.tasks or {}) do
            totalTasks += 1
            if task.running then
                running += 1
                table.insert(lines, string.format("Sync: %s (%d/%d)", task.name, task.destination or 0, task.total or 0))
            end
        end

        barWidget.setGlyph(running > 0 and "cloud-up" or "cloud")
        barWidget.setGlyphColor(running > 0 and "primary" or "")
        barWidget.setColor("")
        barWidget.setText(string.format("%d/%d", mounted, totalMounts))
        if #lines == 0 then table.insert(lines, "No rclone mounts or tasks configured.") end
        barWidget.setTooltip(table.concat(lines, "\n") .. string.format("\n\n%d of %d mounts · %d of %d tasks running", mounted, totalMounts, running, totalTasks))
    end)
    if not ok then busy = false end
end

noctalia.setUpdateInterval(30000)
function update() refresh() end
function onClick()
    noctalia.togglePanel("psark007/rclone-status:details")
end
refresh()
