--!nonstrict
-- Interactive UI backed by the user's Rclone Mounts & Tasks project.
local backend = noctalia.pluginDir() .. "/backend.py"
local function backendArgs(operation, ...)
    local args = { "/usr/bin/python3", backend, "--config-dir", noctalia.expandPath(noctalia.getConfig("config_dir")), operation }
    for _, value in ipairs({ ... }) do table.insert(args, value) end
    return args
end
local busy = false
local mounts, tasks, bisyncs = {}, {}, {}
local activeTab = "mounts"
local notice = ""
local pending = nil
local loggingEnabled = false
noctalia.setUpdateInterval(15000)
local form = nil

local function decoded(result)
    local data = noctalia.json.decode(result.stdout or "")
    if result.exitCode ~= 0 or type(data) ~= "table" or data.ok == false then
        return nil, (type(data) == "table" and data.error) or "Rclone operation failed."
    end
    return data
end

local function mergeDefinitions(snapshot)
    local ok = noctalia.runAsync(backendArgs("definitions"), function(result)
        local data = decoded(result)
        if data then
            loggingEnabled = data.logging == true
            local mountById, taskById, bisyncById = {}, {}, {}
            for _, item in ipairs(data.mounts or {}) do mountById[item.id] = item end
            for _, item in ipairs(data.tasks or {}) do taskById[item.id] = item end
            for _, item in ipairs(data.bisyncs or {}) do bisyncById[item.id] = item end
            for _, item in ipairs(snapshot.mounts or {}) do
                local definition = mountById[item.id]
                if definition then
                    item.remote = definition.remote
                    item.path = definition.path
                end
            end
            for _, item in ipairs(snapshot.tasks or {}) do
                local definition = taskById[item.id]
                if definition then
                    item.source = definition.source
                    item.destinationsList = definition.destinations or {}
                    item.action = definition.action
                    item.direction = definition.direction
                    item.schedule = definition.schedule
                end
            end
            for _, item in ipairs(snapshot.bisyncs or {}) do
                local definition = bisyncById[item.id]
                if definition then
                    item.resyncMode = definition.resyncMode
                    item.schedule = definition.schedule
                end
            end
        end
        mounts, tasks, bisyncs = snapshot.mounts or {}, snapshot.tasks or {}, snapshot.bisyncs or {}
        busy = false
        render()
    end)
    if not ok then
        mounts, tasks, bisyncs = snapshot.mounts or {}, snapshot.tasks or {}, snapshot.bisyncs or {}
        busy = false
        render()
    end
end

local function loadSnapshot(message)
    if busy then return end
    busy = true
    notice = message or "Refreshing…"
    render()
    local ok = noctalia.runAsync(backendArgs("snapshot"), function(result)
        local data, err = decoded(result)
        if not data then
            busy = false
            notice = err
            render()
            return
        end
        notice = message or "Status updated"
        mergeDefinitions(data)
    end)
    if not ok then
        busy = false
        notice = "Could not start the Rclone status check."
        render()
    end
end

local function runBackend(operation, ...)
    if busy then return end
    busy = true
    pending = nil
    notice = "Working…"
    render()
    local argv = backendArgs(operation)
    for _, argument in ipairs({ ... }) do table.insert(argv, argument) end
    local ok = noctalia.runAsync(argv, function(result)
        busy = false
        local data, err = decoded(result)
        if not data then
            notice = err
            render()
        else
            notice = data.message or "Done"
            loadSnapshot(notice)
        end
    end)
    if not ok then
        busy = false
        notice = "Could not start the Rclone operation."
        render()
    end
end

local function beginForm(kind, item)
    pending = nil
    notice = ""
    if kind == "mount" then
        form = { kind = kind, id = item and item.id, label = item and item.label or "",
            remote = item and item.remote or "", path = item and item.path or "" }
    elseif kind == "task" then
        local schedule = item and item.schedule or nil
        form = { kind = kind, id = item and item.id, name = item and item.name or "",
            action = item and item.action or "copy", direction = item and item.direction or "upload",
            source = item and item.source or "", destinations = table.concat(item and item.destinationsList or {}, "\n"),
            scheduleFrequency = schedule and schedule.frequency or "off",
            scheduleTime = schedule and schedule.time or "09:00",
            scheduleWeekday = schedule and schedule.weekday or "monday" }
    else
        local schedule = item and item.schedule or nil
        form = { kind = kind, id = item and item.id, name = item and item.name or "",
            path1 = item and item.path1 or "", path2 = item and item.path2 or "",
            resyncMode = item and item.resyncMode or "path1",
            scheduleFrequency = schedule and schedule.frequency or "off",
            scheduleTime = schedule and schedule.time or "09:00",
            scheduleWeekday = schedule and schedule.weekday or "monday" }
    end
    render()
end

function cancelForm()
    form = nil
    render()
end

local function scheduleForForm()
    if form.scheduleFrequency == "off" then return nil end
    local schedule = { frequency = form.scheduleFrequency, time = form.scheduleTime }
    if form.scheduleFrequency == "weekly" then schedule.weekday = form.scheduleWeekday end
    return schedule
end

function saveForm()
    if not form then return end
    local payload
    local operation
    if form.kind == "mount" then
        operation = "save-mount"
        payload = { id = form.id, label = form.label, remote = form.remote, path = form.path }
    elseif form.kind == "task" then
        operation = "save-task"
        local destinations = {}
        for line in string.gmatch((form.destinations or "") .. "\n", "([^\n]*)\n") do
            local trimmed = string.gsub(line, "^%s*(.-)%s*$", "%1")
            if trimmed ~= "" then table.insert(destinations, trimmed) end
        end
        payload = { id = form.id, name = form.name, action = form.action, direction = form.direction,
            source = form.source, destinations = destinations, schedule = scheduleForForm() }
    else
        operation = "save-bisync"
        payload = { id = form.id, name = form.name, path1 = form.path1, path2 = form.path2,
            resyncMode = form.resyncMode, schedule = scheduleForForm() }
    end
    runBackend(operation, noctalia.json.encode(payload))
    form = nil
end

local function askPending(kind, item)
    pending = { kind = kind, id = item.id, name = item.label or item.name,
        action = item.action, resyncMode = item.resyncMode }
    render()
end

function cancelPending()
    pending = nil
    render()
end

function confirmPending()
    if not pending then return end
    local action = pending
    if action.kind == "remove-mount" then
        runBackend("delete-mount", action.id)
    elseif action.kind == "remove-task" then
        runBackend("delete-task", action.id)
    elseif action.kind == "remove-bisync" then
        runBackend("delete-bisync", action.id)
    else
        runBackend(action.kind, action.id)
    end
end

function refresh()
    pending = nil
    form = nil
    loadSnapshot("Refreshing…")
end

local function addReorderControls(controls, collection, entries, index)
    local entry = entries[index]
    if index > 1 then
        table.insert(controls, ui.button({ text = "↑", tooltip = "Move up", variant = "ghost", enabled = not busy,
            onClick = function() runBackend("reorder-entry", collection, entry.id, entries[index - 1].id, "before") end }))
    end
    if index < #entries then
        table.insert(controls, ui.button({ text = "↓", tooltip = "Move down", variant = "ghost", enabled = not busy,
            onClick = function() runBackend("reorder-entry", collection, entry.id, entries[index + 1].id, "after") end }))
    end
end

function render()
    local head = {
        ui.label({ text = "Rclone", fontSize = 20, fontWeight = "bold", color = "primary", flexGrow = 1 }),
        ui.button({ glyph = "settings", tooltip = "Rclone settings", variant = "ghost", onClick = "openSettings" }),
        ui.button({ glyph = "refresh", tooltip = "Refresh status", variant = "ghost", enabled = not busy, onClick = "refresh" }),
    }
    local tabs = {
        ui.button({ text = string.format("Mounts · %d/%d", (function() local n=0; for _, m in ipairs(mounts) do if m.mounted then n += 1 end end; return n end)(), #mounts), variant = activeTab == "mounts" and "secondary" or "ghost", onClick = function() activeTab="mounts"; form=nil; pending=nil; render() end, flexGrow = 1 }),
        ui.button({ text = string.format("Tasks · %d", #tasks + #bisyncs), variant = activeTab == "tasks" and "secondary" or "ghost", onClick = function() activeTab="tasks"; form=nil; pending=nil; render() end, flexGrow = 1 }),
        ui.button({ text = "Settings", variant = activeTab == "settings" and "secondary" or "ghost", onClick = function() activeTab="settings"; form=nil; pending=nil; render() end, flexGrow = 1 }),
    }
    local addActions = {}
    if activeTab == "mounts" then
        table.insert(addActions, ui.button({ text = "Add mount", glyph = "plus", variant = "primary", enabled = not busy,
            onClick = function() beginForm("mount") end }))
    elseif activeTab == "tasks" then
        table.insert(addActions, ui.button({ text = "Add task", glyph = "plus", variant = "primary", enabled = not busy,
            onClick = function() beginForm("task") end }))
        table.insert(addActions, ui.button({ text = "Add Bisync", variant = "outline", enabled = not busy,
            onClick = function() beginForm("bisync") end }))
    end
    local list = {}
    if notice ~= "" then table.insert(list, ui.label({ text = notice, color = "on_surface_variant", maxLines = 2 })) end

    if pending then
        local warning
        if pending.kind == "stop" then
            warning = "Stop this task? Incomplete transfers may remain."
        elseif pending.kind == "run" then
            warning = pending.action == "sync"
                and "Sync can delete destination-only files. Check the saved source and destination paths before confirming."
                or "Start this saved copy task now?"
        elseif pending.kind == "reverse" then
            warning = "Reverse swaps the source and destination for this run. " .. (pending.action == "sync" and "Sync can delete destination-only files." or "")
        elseif pending.kind == "run-bisync" then
            warning = "Run Bisync using its saved baseline? Changes and deletions may propagate in both directions. Use Resync for first-time setup."
        elseif pending.kind == "resync-bisync" then
            warning = "Resync resets the Bisync baseline and may overwrite same-named files. " .. (pending.resyncMode or "path1") .. " wins for conflicts. Review both folders first."
        elseif pending.kind == "stop-bisync" then
            warning = "Stop Bisync gracefully? The latest run may be incomplete."
        elseif pending.kind == "remove-mount" then
            warning = "Remove this saved mount definition? The cache and remote files are left untouched. It must be unmounted first."
        elseif pending.kind == "remove-bisync" then
            warning = "Remove this Bisync definition? Both folders and Rclone's saved baseline are left untouched."
        else
            warning = "Remove this saved task and its run history? No files are changed."
        end
        table.insert(list, ui.column({ gap = 8, padding = 10, fill = "error/0.12", radius = 8 }, {
            ui.label({ text = warning, color = "error", maxLines = 3 }),
            ui.row({ gap = 8 }, {
                ui.button({ text = "Cancel", variant = "ghost", onClick = "cancelPending" }),
                ui.button({ text = "Confirm", variant = "destructive", enabled = not busy, onClick = "confirmPending" }),
            }),
        }))
    elseif form then
        if form.kind == "mount" then
            table.insert(list, ui.label({ text = form.id and "Edit mount" or "Add mount", fontWeight = "bold" }))
            table.insert(list, ui.label({ text = "Use remote:path and an existing empty local folder. Saving never starts a mount.", color = "on_surface_variant", maxLines = 2 }))
            table.insert(list, ui.input({ key = "mount-label", value = form.label, placeholder = "Display name", onChange = function(v) form.label = v end }))
            table.insert(list, ui.input({ key = "mount-remote", value = form.remote, placeholder = "Remote path (e.g. drive:folder)", onChange = function(v) form.remote = v end }))
            table.insert(list, ui.input({ key = "mount-path", value = form.path, placeholder = "Local mountpoint (absolute or ~/...)", onChange = function(v) form.path = v end }))
        elseif form.kind == "task" then
            table.insert(list, ui.label({ text = form.id and "Edit task" or "Add task", fontWeight = "bold" }))
            table.insert(list, ui.label({ text = "Destinations run sequentially. Copy preserves destination-only files; sync may delete them. Saving never starts a transfer.", color = "on_surface_variant", maxLines = 3 }))
            table.insert(list, ui.input({ key = "task-name", value = form.name, placeholder = "Task name", onChange = function(v) form.name = v end }))
            table.insert(list, ui.select({ options = { "Copy", "Sync" }, selectedIndex = form.action == "sync" and 1 or 0, onChange = function(v) form.action = tonumber(v) == 1 and "sync" or "copy" end }))
            table.insert(list, ui.select({ options = { "Local → remote (upload)", "Remote → local (download)" }, selectedIndex = form.direction == "download" and 1 or 0, onChange = function(v) form.direction = tonumber(v) == 1 and "download" or "upload" end }))
            table.insert(list, ui.input({ key = "task-source", value = form.source, placeholder = "Source (local path or remote:path)", onChange = function(v) form.source = v end }))
            table.insert(list, ui.label({ text = "Destinations · one per line", color = "on_surface_variant" }))
            table.insert(list, ui.input({ key = "task-destinations", value = form.destinations, placeholder = "One local path or remote:path per line", multiline = true, height = 110, onChange = function(v) form.destinations = v end }))
            table.insert(list, ui.select({ options = { "Automatic schedule · Off", "Daily", "Weekly" },
                selectedIndex = form.scheduleFrequency == "daily" and 1 or form.scheduleFrequency == "weekly" and 2 or 0,
                onChange = function(v)
                    form.scheduleFrequency = tonumber(v) == 1 and "daily" or tonumber(v) == 2 and "weekly" or "off"
                    render()
                end }))
            if form.scheduleFrequency ~= "off" then
                table.insert(list, ui.input({ key = "task-schedule-time", value = form.scheduleTime,
                    placeholder = "Time (24-hour local time, HH:MM)", onChange = function(v) form.scheduleTime = v end }))
                if form.scheduleFrequency == "weekly" then
                    local weekdays = { "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday" }
                    local selected = 0
                    for index, day in ipairs(weekdays) do
                        if string.lower(day) == form.scheduleWeekday then selected = index - 1 end
                    end
                    table.insert(list, ui.select({ options = weekdays, selectedIndex = selected,
                        onChange = function(v) form.scheduleWeekday = string.lower(weekdays[tonumber(v) + 1]) end }))
                end
            end
        else
            table.insert(list, ui.label({ text = form.id and "Edit Bisync pair" or "Add Bisync pair", fontWeight = "bold" }))
            table.insert(list, ui.label({ text = "Both folders must exist and must not overlap. Initialize the baseline with Resync before scheduling normal runs.", color = "on_surface_variant", maxLines = 3 }))
            table.insert(list, ui.input({ key = "bisync-name", value = form.name, placeholder = "Display name", onChange = function(v) form.name = v end }))
            table.insert(list, ui.input({ key = "bisync-path1", value = form.path1, placeholder = "Path 1 (absolute local folder or remote:path)", onChange = function(v) form.path1 = v end }))
            table.insert(list, ui.input({ key = "bisync-path2", value = form.path2, placeholder = "Path 2 (absolute local folder or remote:path)", onChange = function(v) form.path2 = v end }))
            local modes = { "Path 1", "Path 2", "Newer", "Older", "Larger", "Smaller" }
            local modeValues = { "path1", "path2", "newer", "older", "larger", "smaller" }
            local modeIndex = 0
            for index, value in ipairs(modeValues) do
                if value == form.resyncMode then modeIndex = index - 1 end
            end
            table.insert(list, ui.select({ options = modes, selectedIndex = modeIndex,
                onChange = function(v) form.resyncMode = modeValues[tonumber(v) + 1] end }))
            table.insert(list, ui.select({ options = { "Automatic schedule · Off", "Daily", "Weekly" },
                selectedIndex = form.scheduleFrequency == "daily" and 1 or form.scheduleFrequency == "weekly" and 2 or 0,
                onChange = function(v)
                    form.scheduleFrequency = tonumber(v) == 1 and "daily" or tonumber(v) == 2 and "weekly" or "off"
                    render()
                end }))
            if form.scheduleFrequency ~= "off" then
                table.insert(list, ui.input({ key = "bisync-schedule-time", value = form.scheduleTime,
                    placeholder = "Time (24-hour local time, HH:MM)", onChange = function(v) form.scheduleTime = v end }))
                if form.scheduleFrequency == "weekly" then
                    local weekdays = { "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday" }
                    local selected = 0
                    for index, day in ipairs(weekdays) do
                        if string.lower(day) == form.scheduleWeekday then selected = index - 1 end
                    end
                    table.insert(list, ui.select({ options = weekdays, selectedIndex = selected,
                        onChange = function(v) form.scheduleWeekday = string.lower(weekdays[tonumber(v) + 1]) end }))
                end
            end
        end
        table.insert(list, ui.row({ gap = 8 }, {
            ui.button({ text = "Save", glyph = "device-floppy", variant = "primary", enabled = not busy, onClick = "saveForm" }),
            ui.button({ text = "Cancel", variant = "ghost", enabled = not busy, onClick = "cancelForm" }),
        }))
    elseif activeTab == "settings" then
        table.insert(list, ui.label({ text = "Diagnostics · logs may contain filenames, paths, and provider errors", color = "on_surface_variant", maxLines = 2 }))
        table.insert(list, ui.row({ gap = 8, align = "center" }, {
            ui.button({ text = loggingEnabled and "Disable logging" or "Enable logging",
                variant = loggingEnabled and "outline" or "secondary", enabled = not busy,
                onClick = function() runBackend("save-diagnostics", noctalia.json.encode({logging = not loggingEnabled})) end }),
            ui.button({ text = "Open logs folder", glyph = "folder-open", variant = "ghost", enabled = not busy,
                onClick = function() runBackend("open-logs") end }),
        }))
        for _, mount in ipairs(mounts) do
            if mount.log then
                table.insert(list, ui.row({ gap = 8, align = "center" }, {
                    ui.label({ text = "Mount · " .. mount.label, flexGrow = 1, maxLines = 1 }),
                    ui.button({ text = "Open log", glyph = "document", variant = "ghost", enabled = not busy,
                        onClick = function() runBackend("open-mount-log", mount.id) end }),
                }))
            end
        end
        for _, task in ipairs(tasks) do
            if task.log then
                table.insert(list, ui.row({ gap = 8, align = "center" }, {
                    ui.label({ text = "Task · " .. task.name, flexGrow = 1, maxLines = 1 }),
                    ui.button({ text = "Open log", glyph = "document", variant = "ghost", enabled = not busy,
                        onClick = function() runBackend("open-task-log", task.id) end }),
                }))
            end
        end
        for _, item in ipairs(bisyncs) do
            if item.log then
                table.insert(list, ui.row({ gap = 8, align = "center" }, {
                    ui.label({ text = "Bisync · " .. item.name, flexGrow = 1, maxLines = 1 }),
                    ui.button({ text = "Open log", glyph = "document", variant = "ghost", enabled = not busy,
                        onClick = function() runBackend("open-bisync-log", item.id) end }),
                }))
            end
        end
        if #mounts == 0 and #tasks == 0 and #bisyncs == 0 then
            table.insert(list, ui.label({ text = "No saved entries or logs yet.", color = "on_surface_variant" }))
        end
        table.insert(list, ui.button({ text = "Data directory settings", glyph = "settings", variant = "ghost",
            onClick = "openSettings" }))
    elseif activeTab == "mounts" then
        table.insert(list, ui.label({ text = "Saved mounts · nothing mounts automatically", color = "on_surface_variant" }))
        if #mounts == 0 then table.insert(list, ui.label({ text = "No mounts yet. Use Add mount to create one." })) end
        for index, mount in ipairs(mounts) do
            local uploadState = mount.uploads and mount.uploads.state or "unknown"
            local subtitle = (mount.remote or "") .. " → " .. (mount.path or "") .. "\n" .. mount.status
            if mount.mounted then subtitle = subtitle .. " · uploads " .. uploadState end
            local controls = {}
            if mount.mounted then
                table.insert(controls, ui.button({ text = "Open", glyph = "folder-open", variant = "ghost", enabled = not busy, onClick = function() runBackend("open", mount.id) end }))
                table.insert(controls, ui.button({ text = "Unmount", glyph = "player-stop", variant = "outline", enabled = not busy and uploadState == "clear", tooltip = uploadState == "clear" and "Unmount after two clear upload checks" or "Pending or unknown uploads block unmount", onClick = function() runBackend("unmount", mount.id) end }))
            else
                table.insert(controls, ui.button({ text = "Mount", glyph = "player-play", variant = "secondary", enabled = not busy and mount.status == "Off", onClick = function() runBackend("mount", mount.id) end }))
                table.insert(controls, ui.button({ text = "Edit", variant = "ghost", enabled = not busy, onClick = function() beginForm("mount", mount) end }))
                table.insert(controls, ui.button({ text = "Remove", variant = "ghost", enabled = not busy and mount.status == "Off", onClick = function() askPending("remove-mount", mount) end }))
            end
            addReorderControls(controls, "mounts", mounts, index)
            table.insert(list, ui.column({ key = "mount-" .. mount.id, gap = 8, padding = 10, fill = "surface_variant/0.35", radius = 8 }, {
                ui.label({ text = mount.label, fontWeight = "bold", maxLines = 1 }),
                ui.label({ text = subtitle, color = "on_surface_variant", maxLines = 2 }),
                ui.row({ gap = 6, align = "center" }, controls),
            }))
        end
    else
        table.insert(list, ui.label({ text = "Saved tasks · review paths before running", color = "on_surface_variant" }))
        if #tasks == 0 and #bisyncs == 0 then table.insert(list, ui.label({ text = "No tasks yet. Use Add task or Add Bisync to create one." })) end
        for index, task in ipairs(tasks) do
            local state = task.running and "Running" or task.status
            local direction = task.direction == "upload" and "Upload" or "Download"
            local subtitle = string.format("%s · %s · %s", string.upper(task.action), direction, state)
            if task.running then subtitle = subtitle .. string.format(" · destination %d/%d", task.destination or 0, task.total or 0) end
            if task.source then subtitle = subtitle .. "\n" .. task.source .. " → " .. table.concat(task.destinationsList or {}, "; ") end
            if task.schedule then
                local when = task.schedule.frequency == "daily" and "Daily" or "Weekly " .. (task.schedule.weekday or "monday")
                subtitle = subtitle .. "\nScheduled · " .. when .. " at " .. task.schedule.time .. " local time"
            end
            local history = task.history or {}
            if #history > 0 then
                subtitle = subtitle .. "\nLast: " .. (history[1].status or "unknown")
                if history[1].startedAt and history[1].startedAt ~= "" then subtitle = subtitle .. " · " .. string.sub(history[1].startedAt, 1, 16):gsub("T", " ") end
                if #history > 1 then subtitle = subtitle .. " · Before: " .. (history[2].status or "unknown") end
            end
            local controls = {}
            if task.running then
                table.insert(controls, ui.button({ text = "Stop", glyph = "player-stop", variant = "destructive", enabled = not busy, onClick = function() askPending("stop", task) end }))
            else
                table.insert(controls, ui.button({ text = "Run", glyph = "player-play", variant = "secondary", enabled = not busy, onClick = function() askPending("run", task) end }))
                if task.destinations == 1 then
                    table.insert(controls, ui.button({ text = "Reverse", glyph = "arrows-exchange", variant = "ghost", enabled = not busy, onClick = function() askPending("reverse", task) end }))
                end
                table.insert(controls, ui.button({ text = "Edit", variant = "ghost", enabled = not busy, onClick = function() beginForm("task", task) end }))
                table.insert(controls, ui.button({ text = "Remove", variant = "ghost", enabled = not busy, onClick = function() askPending("remove-task", task) end }))
            end
            addReorderControls(controls, "tasks", tasks, index)
            table.insert(list, ui.column({ key = "task-" .. task.id, gap = 8, padding = 10, fill = "surface_variant/0.35", radius = 8 }, {
                ui.label({ text = task.name, fontWeight = "bold", maxLines = 1 }),
                ui.label({ text = subtitle, color = task.running and "primary" or "on_surface_variant", maxLines = 3 }),
                ui.row({ gap = 6, align = "center" }, controls),
            }))
        end
        if #bisyncs > 0 then
            table.insert(list, ui.label({ text = "Bisync pairs", fontWeight = "bold", color = "on_surface_variant" }))
        end
        for index, item in ipairs(bisyncs) do
            local state = item.running and "Running" or item.status
            local subtitle = "Path 1: " .. item.path1 .. "\nPath 2: " .. item.path2
            if item.schedule then
                local when = item.schedule.frequency == "daily" and "Daily" or "Weekly " .. (item.schedule.weekday or "monday")
                subtitle = subtitle .. "\nScheduled · " .. when .. " at " .. item.schedule.time .. " local time"
            end
            if item.running and item.stats then
                subtitle = subtitle .. string.format("\nRunning · %s/s · %s errors", tostring(item.stats.speed or "?"), tostring(item.stats.errors or "?"))
            end
            local history = item.history or {}
            if #history > 0 then
                subtitle = subtitle .. "\nLast: " .. (history[1].status or "unknown")
                if history[1].startedAt and history[1].startedAt ~= "" then subtitle = subtitle .. " · " .. string.sub(history[1].startedAt, 1, 16):gsub("T", " ") end
                if #history > 1 then subtitle = subtitle .. " · Before: " .. (history[2].status or "unknown") end
            else
                subtitle = subtitle .. "\nResync preference: " .. (item.resyncMode or "path1")
            end
            local controls = {}
            if item.running then
                table.insert(controls, ui.button({ text = "Stop", glyph = "player-stop", variant = "destructive", enabled = not busy,
                    onClick = function() askPending("stop-bisync", item) end }))
            else
                table.insert(controls, ui.button({ text = "Run", glyph = "player-play", variant = "secondary", enabled = not busy,
                    onClick = function() askPending("run-bisync", item) end }))
                table.insert(controls, ui.button({ text = "Resync", variant = "outline", enabled = not busy,
                    onClick = function() askPending("resync-bisync", item) end }))
                table.insert(controls, ui.button({ text = "Edit", variant = "ghost", enabled = not busy,
                    onClick = function() beginForm("bisync", item) end }))
                table.insert(controls, ui.button({ text = "Remove", variant = "ghost", enabled = not busy,
                    onClick = function() askPending("remove-bisync", item) end }))
            end
            addReorderControls(controls, "bisyncs", bisyncs, index)
            table.insert(list, ui.column({ key = "bisync-" .. item.id, gap = 8, padding = 10,
                fill = item.running and "primary/0.12" or "surface_variant/0.35", radius = 8 }, {
                ui.label({ text = item.name .. " · BISYNC · " .. state, fontWeight = "bold", maxLines = 1 }),
                ui.label({ text = subtitle, color = item.running and "primary" or "on_surface_variant", maxLines = 6 }),
                ui.row({ gap = 6, align = "center" }, controls),
            }))
        end
    end

    local content = {
        ui.row({ align = "center", justify = "space_between" }, head),
        ui.row({ gap = 6 }, tabs),
    }
    if #addActions > 0 then
        table.insert(content, ui.row({ gap = 6, justify = "end" }, addActions))
    end
    table.insert(content, ui.scroll({ flexGrow = 1, gap = 10 }, list))
    panel.render(ui.column({ gap = 10, padding = 16, flexGrow = 1 }, content))
end

function openSettings()
    noctalia.runAsync("noctalia msg settings-open-plugin psark007/rclone-status")
end

function onOpen()
    loadSnapshot("Loading Rclone status…")
end

function update()
    if not busy and not form and not pending then
        loadSnapshot("Auto-refreshed")
    end
end
