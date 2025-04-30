Example:

- `disk-usage-check.sh`
- `cpu-high-usage-processes.sh`
- `network-ping-loss-check.sh`

---

## 🗂️ Script Categories

| Prefix        | Description                                       |
|---------------|----------------------------------------------------|
| `disk`        | Disk space usage, I/O, mount status, large files   |
| `memory`      | Swap usage, memory leaks, OOM detection            |
| `cpu`         | High CPU usage, system load issues                 |
| `network`     | Network connections, open ports, packet loss       |
| `process`     | Zombie processes, top resource-consuming ones      |
| `logs`        | Log explosion detection, log directory usage       |
| `filesystem`  | Filesystem errors, mount issues                    |
| `services`    | Service status, restart, recovery checks           |
| `deleted`     | Deleted-but-open files that still take up space    |
| `common`      | General tools (env summary, top10 usage, etc.)     |

---

## 🚀 Usage

Each script is executable and self-contained. Run them directly with bash:

```bash
chmod +x disk-usage-check.sh
./disk-usage-check.sh
