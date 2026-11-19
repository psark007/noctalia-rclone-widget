--!nonstrict
-- Render shared Rclone status from the plugin service.

local function bytes(value)
    local amount = tonumber(value)
    if not amount then return "—" end
    local units = { "B", "KiB", "MiB", "GiB", "TiB" }
    local index = 1
    while amount >= 1024 and index < #units do
        amount /= 1024
        index += 1
    end
    return index == 1 and string.format("%.0f %s", amount, units[index])
        or string.format("%.1f %s", amount, units[index])
end

local function eta(value)
    local seconds = tonumber(value)
    if not seconds or seconds < 0 then return nil end
    seconds = math.floor(seconds)
    if seconds >= 3600 then
        return string.format("%dh %02dm", math.floor(seconds / 3600), math.floor(seconds % 3600 / 60))
    elseif seconds >= 60 then
        return string.format("%dm %02ds", math.floor(seconds / 60), seconds % 60)
    end
    return string.format("%ds", seconds)
end

local function transferSummary(stats)
    if type(stats) ~= "table" then return "Progress unavailable" end
    local transferred = tonumber(stats.bytes) or 0
    local total = tonumber(stats.totalBytes)
    local summary = total and total > 0
        and string.format("%s / %s", bytes(transferred), bytes(total))
        or ("Transferred " .. bytes(transferred))
    local speed = tonumber(stats.speed)
    if speed then summary = summary .. " · " .. bytes(speed) .. "/s" end
    local remaining = eta(stats.eta)
    if remaining then summary = summary .. " · ETA " .. remaining end
    if stats.errors ~= nil then summary = summary .. " · " .. tostring(stats.errors) .. " errors" end
    return summary
end

local function appendFileActivity(lines, stats)
    for index, transfer in ipairs(stats and stats.transferring or {}) do
        if index > 3 then break end
        local detail = bytes(transfer.bytes) .. " / " .. bytes(transfer.size)
        local percent = tonumber(transfer.percentage)
        if not percent then
            local size = tonumber(transfer.size)
            if size and size > 0 then
                percent = (tonumber(transfer.bytes) or 0) * 100 / size
            end
        end
        if percent then detail = detail .. string.format(" · %d%%", math.max(0, math.min(100, math.floor(percent)))) end
        local speed = tonumber(transfer.speedAvg) or tonumber(transfer.speed)
        if speed and speed > 0 then detail = detail .. " · " .. bytes(speed) .. "/s" end
        table.insert(lines, "  ↳ " .. tostring(transfer.name or "File") .. " · " .. detail)
    end
end

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
    local activity = {}
    for _, mount in ipairs(data.mounts or {}) do
        totalMounts += 1
        if mount.mounted then mounted += 1 end
        table.insert(lines, string.format("%s: %s", mount.label, mount.status))
        if mount.mounted and mount.stats then
            table.insert(lines, "  Transfer: " .. transferSummary(mount.stats))
            if #(mount.stats.transferring or {}) > 0 then
                table.insert(activity, "Mount · " .. mount.label .. " · " .. transferSummary(mount.stats))
                appendFileActivity(activity, mount.stats)
            end
        end
    end
    for _, task in ipairs(data.tasks or {}) do
        totalTasks += 1
        if task.running then
            running += 1
            local direction = task.direction == "upload" and "Upload" or "Download"
            local summary = string.format("%s · %d/%d · %s", direction, task.destination or 0, task.total or 0, transferSummary(task.stats))
            table.insert(lines, task.name .. ": " .. summary)
            table.insert(activity, task.name .. " · " .. summary)
            appendFileActivity(activity, task.stats)
        end
    end
    for _, item in ipairs(data.bisyncs or {}) do
        totalTasks += 1
        if item.running then
            running += 1
            local summary = "Bisync · " .. transferSummary(item.stats)
            table.insert(lines, item.name .. ": " .. summary)
            table.insert(activity, item.name .. " · " .. summary)
            appendFileActivity(activity, item.stats)
        end
    end
    if #activity > 0 then
        table.insert(lines, "")
        table.insert(lines, "Happening now:")
        for _, line in ipairs(activity) do table.insert(lines, line) end
    else
        table.insert(lines, "")
        table.insert(lines, "No active transfers.")
    end

    local counts = {}
    if mounted > 0 then table.insert(counts, string.format("%dM", mounted)) end
    if running > 0 then table.insert(counts, string.format("%dT", running)) end
    local color = running > 0 and "#52e08a" or mounted > 0 and "#4da6ff" or "#9aa4b2"
    barWidget.setGlyph(running > 0 and "cloud-up" or "cloud")
    barWidget.setGlyphColor(color)
    barWidget.setColor((running > 0 or mounted > 0) and color or "")
    barWidget.setText(table.concat(counts, " "))
    if #lines == 0 then table.insert(lines, "No rclone mounts, tasks, or Bisync pairs configured.") end
    barWidget.setTooltip(table.concat(lines, "\n") .. string.format("\n\n%d of %d mounts · %d of %d jobs running", mounted, totalMounts, running, totalTasks))
end

noctalia.state.watch("rclone_status", render)
render(noctalia.state.get("rclone_status"))

function onClick()
    noctalia.togglePanel("psark007/rclone-status:details")
end

function onRightClick()
    noctalia.togglePanel("psark007/rclone-status:details")
end
