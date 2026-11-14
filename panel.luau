--!nonstrict
-- Interactive UI backed by the user's Rclone Mounts & Tasks project.
local backend = noctalia.pluginDir() .. "/backend.py"
local busy = false
local mounts, tasks = {}, {}
local activeTab = "mounts"
local notice = ""
local pending = nil
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
    local ok = noctalia.runAsync({ "/usr/bin/python3", backend, "definitions" }, function(result)
        local data = decoded(result)
        if data then
            local mountById, taskById = {}, {}
            for _, item in ipairs(data.mounts or {}) do mountById[item.id] = item end
            for _, item in ipairs(data.tasks or {}) do taskById[item.id] = item end
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
                end
            end
        end
        mounts, tasks = snapshot.mounts or {}, snapshot.tasks or {}
        busy = false
        render()
    end)
    if not ok then
        mounts, tasks = snapshot.mounts or {}, snapshot.tasks or {}
        busy = false
        render()
    end
end

local function loadSnapshot(message)
    if busy then return end
    busy = true
    notice = message or "Refreshing…"
    render()
    local ok = noctalia.runAsync({ "/usr/bin/python3", backend, "snapshot" }, function(result)
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

local function runBackend(operation, argument)
    if busy then return end
    busy = true
    pending = nil
    notice = "Working…"
    render()
    local argv = { "/usr/bin/python3", backend, operation }
    if argument ~= nil then table.insert(argv, argument) end
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
    else
        form = { kind = kind, id = item and item.id, name = item and item.name or "",
            action = item and item.action or "copy", direction = item and item.direction or "upload",
            source = item and item.source or "", destinations = table.concat(item and item.destinationsList or {}, "\n") }
    end
    render()
end

local function cancelForm()
    form = nil
    render()
end

local function saveForm()
    if not form then return end
    local payload
    local operation
    if form.kind == "mount" then
        operation = "save-mount"
        payload = { id = form.id, label = form.label, remote = form.remote, path = form.path }
    else
        operation = "save-task"
        local destinations = {}
        for line in string.gmatch((form.destinations or "") .. "\n", "([^\n]*)\n") do
            local trimmed = string.gsub(line, "^%s*(.-)%s*$", "%1")
            if trimmed ~= "" then table.insert(destinations, trimmed) end
        end
        payload = { id = form.id, name = form.name, action = form.action, direction = form.direction,
            source = form.source, destinations = destinations }
    end
    runBackend(operation, noctalia.json.encode(payload))
    form = nil
end

local function askPending(kind, item)
    pending = { kind = kind, id = item.id, name = item.label or item.name, action = item.action }
    render()
end

local function cancelPending()
    pending = nil
    render()
end

local function confirmPending()
    if not pending then return end
    local action = pending
    if action.kind == "remove-mount" then
        runBackend("delete-mount", action.id)
    elseif action.kind == "remove-task" then
        runBackend("delete-task", action.id)
    else
        runBackend(action.kind, action.id)
    end
end

function refresh()
    pending = nil
    form = nil
    loadSnapshot("Refreshing…")
end

function render()
    local head = {
        ui.label({ text = "Rclone", fontSize = 20, fontWeight = "bold", color = "primary", flexGrow = 1 }),
        ui.button({ glyph = "refresh", tooltip = "Refresh status", variant = "ghost", enabled = not busy, onClick = "refresh" }),
    }
    local tabs = {
        ui.button({ text = string.format("Mounts · %d/%d", (function() local n=0; for _, m in ipairs(mounts) do if m.mounted then n += 1 end end; return n end)(), #mounts), variant = activeTab == "mounts" and "secondary" or "ghost", onClick = function() activeTab="mounts"; form=nil; pending=nil; render() end, flexGrow = 1 }),
        ui.button({ text = string.format("Tasks · %d", #tasks), variant = activeTab == "tasks" and "secondary" or "ghost", onClick = function() activeTab="tasks"; form=nil; pending=nil; render() end, flexGrow = 1 }),
        ui.button({ text = activeTab == "mounts" and "Add mount" or "Add task", glyph = "plus", variant = "primary", enabled = not busy, onClick = function() beginForm(activeTab == "mounts" and "mount" or "task") end }),
    }
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
        elseif pending.kind == "remove-mount" then
            warning = "Remove this saved mount definition? The cache and remote files are left untouched. It must be unmounted first."
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
        else
            table.insert(list, ui.label({ text = form.id and "Edit task" or "Add task", fontWeight = "bold" }))
            table.insert(list, ui.label({ text = "Destinations run sequentially. Copy preserves destination-only files; sync may delete them. Saving never starts a transfer.", color = "on_surface_variant", maxLines = 3 }))
            table.insert(list, ui.input({ key = "task-name", value = form.name, placeholder = "Task name", onChange = function(v) form.name = v end }))
            table.insert(list, ui.select({ options = { "Copy", "Sync" }, selectedIndex = form.action == "sync" and 1 or 0, onChange = function(v) form.action = tonumber(v) == 1 and "sync" or "copy" end }))
            table.insert(list, ui.select({ options = { "Local → remote (upload)", "Remote → local (download)" }, selectedIndex = form.direction == "download" and 1 or 0, onChange = function(v) form.direction = tonumber(v) == 1 and "download" or "upload" end }))
            table.insert(list, ui.input({ key = "task-source", value = form.source, placeholder = "Source (local path or remote:path)", onChange = function(v) form.source = v end }))
            table.insert(list, ui.label({ text = "Destinations · one per line", color = "on_surface_variant" }))
            table.insert(list, ui.input({ key = "task-destinations", value = form.destinations, placeholder = "One local path or remote:path per line", multiline = true, height = 110, onChange = function(v) form.destinations = v end }))
        end
        table.insert(list, ui.row({ gap = 8 }, {
            ui.button({ text = "Save", glyph = "device-floppy", variant = "primary", enabled = not busy, onClick = "saveForm" }),
            ui.button({ text = "Cancel", variant = "ghost", enabled = not busy, onClick = "cancelForm" }),
        }))
    elseif activeTab == "mounts" then
        table.insert(list, ui.label({ text = "Saved mounts · nothing mounts automatically", color = "on_surface_variant" }))
        if #mounts == 0 then table.insert(list, ui.label({ text = "No mounts yet. Use Add mount to create one." })) end
        for _, mount in ipairs(mounts) do
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
            table.insert(list, ui.column({ key = "mount-" .. mount.id, gap = 8, padding = 10, fill = "surface_variant/0.35", radius = 8 }, {
                ui.label({ text = mount.label, fontWeight = "bold", maxLines = 1 }),
                ui.label({ text = subtitle, color = "on_surface_variant", maxLines = 2 }),
                ui.row({ gap = 6, align = "center" }, controls),
            }))
        end
    else
        table.insert(list, ui.label({ text = "Saved manual tasks · review paths before running", color = "on_surface_variant" }))
        if #tasks == 0 then table.insert(list, ui.label({ text = "No tasks yet. Use Add task to create one." })) end
        for _, task in ipairs(tasks) do
            local state = task.running and "Running" or task.status
            local subtitle = string.format("%s · %s · %s", string.upper(task.action), task.direction, state)
            if task.running then subtitle = subtitle .. string.format(" · destination %d/%d", task.destination or 0, task.total or 0) end
            if task.source then subtitle = subtitle .. "\n" .. task.source .. " → " .. table.concat(task.destinationsList or {}, "; ") end
            local history = task.history or {}
            if #history > 0 then subtitle = subtitle .. "\nLast run: " .. (history[1].status or "unknown") end
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
            table.insert(list, ui.column({ key = "task-" .. task.id, gap = 8, padding = 10, fill = "surface_variant/0.35", radius = 8 }, {
                ui.label({ text = task.name, fontWeight = "bold", maxLines = 1 }),
                ui.label({ text = subtitle, color = task.running and "primary" or "on_surface_variant", maxLines = 3 }),
                ui.row({ gap = 6, align = "center" }, controls),
            }))
        end
    end

    panel.render(ui.column({ gap = 10, padding = 16, flexGrow = 1 }, {
        ui.row({ align = "center", justify = "space_between" }, head),
        ui.row({ gap = 6 }, tabs),
        ui.scroll({ flexGrow = 1, gap = 10 }, list),
    }))
end

function onOpen()
    loadSnapshot("Loading Rclone status…")
end

function update()
    if not busy and not form and not pending then
        loadSnapshot("Auto-refreshed")
    end
end
