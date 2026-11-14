# Rclone Mounts & Tasks for Noctalia

Manual Rclone mounts and copy/sync tasks for Noctalia. New installs start empty;
nothing mounts or transfers automatically. The plugin is standalone and does not
require GNOME Shell or the GNOME extension, but it intentionally shares the
same backend data with them.

## Use

- Add mounts and tasks in the Noctalia panel using explicit `remote:path` values.
  Mountpoints must already exist and be empty. Active mounts cannot be edited or
  removed.
- Tasks run on demand. Different tasks can run concurrently, but each task can
  run only once at a time. Multiple destinations run sequentially; a failed
  destination stops the task. Single-destination tasks can run in reverse.
- Run, Reverse, Stop, and Remove require confirmation.
- **Sync can delete destination-only files**, including local files when
  downloading or reversing an upload. Check paths before confirming.

The panel shows mounted (`M`) and running-task (`T`) counts. Work runs in
transient `systemd --user` services, so closing or reloading Noctalia does not
stop it: stop tasks and unmount explicitly.

## Mount caching

New mounts default to **Reads and writes** (`--vfs-cache-mode full`), **5G**
maximum size, **24h** maximum age since last access, and **10G** minimum free
space target. These are editable safeguards, not a claim that disk space is
currently low. Full mode caches only data accessed, uses local disk rather than
RAM, and cache files for crypt remotes contain decrypted data locally.

New mounts have their own cache root under
`$XDG_CACHE_HOME/gnome-shell-rclone/mounts/<mount-id>/` (or
`~/.cache/gnome-shell-rclone/mounts/<mount-id>/`). Existing mounts are not moved;
an absent `cacheDir` keeps Rclone's original default cache root. Cache files are
never deleted when definitions are removed. Changes to caching take effect on
the next mount, not an active mount. Check disk space, permissions, and backups.

Mounts and tasks use 8 transfers and 16 checkers. Caching does not affect tasks.

## Diagnostics and safety

The backend provides diagnostics including the installed Rclone version,
effective transfer and cache settings, upload status, and available
transfer/error statistics. Opt-in logging is off by default. Logs are kept under
`$XDG_STATE_HOME/gnome-shell-rclone/logs/` (normally
`~/.local/state/gnome-shell-rclone/logs/`), with private directory and file
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

Definitions, task history, diagnostics settings, logs, and caches stay outside
this repository under the user's XDG config, state, and cache directories. The
plugin uses the existing `gnome-shell-rclone` directories so definitions are
shared with the GNOME extension. Configure Rclone remotes separately; the plugin
does not discover or store their credentials. Do not commit `rclone.conf`, saved
definitions, logs, or task history.

## Transfer definitions between devices

There is no built-in import/export button. Mount and task definitions are stored
in `~/.config/gnome-shell-rclone/mounts.json` and
`~/.config/gnome-shell-rclone/tasks.json`. Stop active mounts and tasks, then
copy those files to the same directory on the other device. Do not copy
`~/.local/state/gnome-shell-rclone/runs.json` unless task history is wanted.

Before using the copied definitions, update device-specific absolute local paths
for mountpoints, task sources and destinations, and mount `cacheDir` values.
Mountpoints must already exist and be empty. Configure the same Rclone remote
names separately on the destination device; remote credentials are stored in
Rclone's separate `rclone.conf` and must be transferred or configured securely.
Review copied definitions before starting any mount or task.

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
