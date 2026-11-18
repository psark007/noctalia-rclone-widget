# Rclone Manager for Noctalia

Manage Rclone mounts, copy/sync tasks, and Bisync pairs from Noctalia. New
installs start empty; nothing mounts or transfers automatically. The plugin is
standalone and does not require GNOME Shell. Its default data directory is
`~/.config/noctalia-rclone`; change it in Noctalia plugin settings to share
definitions with another frontend.

## Use

- Add mounts, tasks, and Bisync pairs in the Noctalia panel using explicit `remote:path` values.
  Mountpoints must already exist and be empty. Active mounts cannot be edited or
  removed.
- Use the panel's **Settings** tab to enable or disable logging and open log files. The data
  directory itself is set in Noctalia plugin settings; it controls definitions,
  state, logs, and cache.
- Tasks run on demand or on a daily/weekly local-time schedule. Each task can
  have only one run at a time; separate tasks may run concurrently. Multiple
  destinations run sequentially; a failed destination stops the task.
  Single-destination tasks can run in reverse.
- Bisync pairs run on demand or on a daily/weekly schedule. Use **Resync** to
  establish the baseline before the first scheduled run. Normal Bisync propagates
  changes and deletions both ways; Resync remains manual. It is not a real-time watcher.
- Reorder mounts, tasks, and Bisync pairs with the up/down buttons in their rows.
- Run, Reverse, Resync, Stop, and Remove require confirmation.
- **Sync can delete destination-only files**, including local files when
  downloading or reversing an upload. Check paths before confirming.

The bar shows counts such as `2M 1T` for two mounts and one active job;
zero values are omitted. The cloud uses high-contrast blue for mounted-only
state and high-contrast green while transfers run. The panel shows mount, task,
and Bisync status and recent history. The bar status is refreshed by a shared
plugin service every two seconds. Work runs in transient `systemd --user`
services, so closing or reloading Noctalia does not stop it: stop transfers and
unmount explicitly.
Schedules use the user systemd manager. With lingering disabled, a missed timer
activation is picked up when the user session starts again.

## Mount caching

New mounts default to **Reads and writes** (`--vfs-cache-mode full`), **5G**
maximum size, **24h** maximum age since last access, and **10G** minimum free
space target. These are editable safeguards, not a claim that disk space is
currently low. Full mode caches only data accessed, uses local disk rather than
RAM, and cache files for crypt remotes contain decrypted data locally.

New mounts have their own cache root under
`.cache/mounts/<mount-id>/` in the selected data directory. Existing mounts are not moved;
an absent `cacheDir` keeps Rclone's original default cache root. Cache files are
never deleted when definitions are removed. Changes to caching take effect on
the next mount, not an active mount. Check disk space, permissions, and backups.

Mounts, tasks, and Bisync runs use 8 transfers and 16 checkers. Caching does not
affect transfers.

## Logs and safety

The panel's **Settings** tab provides log access and a logging toggle. Opt-in
logging is off by default. Logs are kept under
the selected data directory's `.state/logs/` directory, with private directory and file
permissions and bounded retention. Logs may contain filenames, paths, and
provider errors. **Review logs before sharing**; they are not automatically safe
to publish.

Unmount checks Rclone's VFS queue twice before detaching and does not force or
lazily detach a busy FUSE mount. An empty VFS queue is not proof that open files
are durable. Stop applications writing to the mount, close their files, and
verify important remote files independently. The loopback-only Rclone RC
interface is powerful user-level access; do not expose its ports to untrusted
processes or networks.

## Data and privacy

By default, definitions, task history, diagnostics settings, logs, and caches
stay outside this repository in the selected data directory. If you choose a
directory inside the repository, do not commit its private data. Configure
Rclone remotes separately; the plugin does not discover or store their
credentials. Do not commit `rclone.conf`, saved definitions, logs, or history.

## Transfer definitions between devices

There is no built-in import/export button. Mount, task, and Bisync definitions
are stored in the selected data directory as `mounts.json`, `tasks.json`, and
`bisyncs.json`. Stop active mounts, tasks, and Bisync runs, then copy these files
to the same directory on the other device. Do not copy `.state` unless run
history and logs should be transferred too.

Before using the copied definitions, update device-specific absolute local paths
for mountpoints, task sources and destinations, Bisync folders, and mount
`cacheDir` values.
Mountpoints must already exist and be empty. Configure the same Rclone remote
names separately on the destination device; remote credentials are stored in
Rclone's separate `rclone.conf` and must be transferred or configured securely.
Review copied definitions before starting any mount, task, or Bisync pair.

## Install and develop

Requirements:

- Noctalia with plugin API 24
- `python3` and `rclone`
- `systemd --user`
- FUSE (`fusermount3`)

Link this directory into Noctalia's plugin directory:

```sh
mkdir -p ~/.local/share/noctalia/plugins
ln -sfn ~/Projects/noctalia-rclone-widget ~/.local/share/noctalia/plugins/rclone-status
```

Noctalia watches plugin files and hot-reloads changes. Validate the plugin with:

```sh
noctalia plugins lint ~/Projects/noctalia-rclone-widget
```

## License

MIT; see [LICENSE](LICENSE).
