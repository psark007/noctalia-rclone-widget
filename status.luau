--!nonstrict
-- Render shared Rclone status from the plugin service.

local function render(data)
    if type(data) ~= "table" then
        barWidget.setGlyph("cloud-off")
        barWidget.setGlyphColor("#9aa4b2")
        barWidget.setText("")
        barWidget.setTooltip("Rclone status unavailable; check the local Rclone setup.")
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

    local counts = {}
    if mounted > 0 then table.insert(counts, string.format("%dM", mounted)) end
    if running > 0 then table.insert(counts, string.format("%dT", running)) end
    local color = running > 0 and "#52e08a" or mounted > 0 and "#4da6ff" or "#9aa4b2"
    barWidget.setGlyph(running > 0 and "cloud-up" or "cloud")
    barWidget.setGlyphColor(color)
    barWidget.setColor((running > 0 or mounted > 0) and color or "")
    barWidget.setText(table.concat(counts, " "))
    if #lines == 0 then table.insert(lines, "No rclone mounts or tasks configured.") end
    barWidget.setTooltip(table.concat(lines, "\n") .. string.format("\n\n%d of %d mounts · %d of %d tasks running", mounted, totalMounts, running, totalTasks))
end

noctalia.state.watch("rclone_status", render)
render(noctalia.state.get("rclone_status"))

function onClick()
    noctalia.togglePanel("psark007/rclone-status:details")
end

function onRightClick()
    noctalia.togglePanel("psark007/rclone-status:details")
end
