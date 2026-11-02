"""连续采样指定进程；CPU 的 100% 表示一个逻辑核。"""

import argparse
import json
import statistics
import subprocess
import time
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("pid", type=int)
parser.add_argument("--seconds", type=int, default=30)
parser.add_argument("--label", required=True)
parser.add_argument("--helper", required=True)
parser.add_argument("--output", required=True)
args = parser.parse_args()
if args.pid <= 0 or args.seconds <= 0:
    parser.error("pid and seconds must be positive")

rows = []
for index in range(args.seconds + 1):
    row = json.loads(subprocess.check_output([args.helper, str(args.pid)], text=True))
    row["at"] = time.monotonic()
    rows.append(row)
    if index < args.seconds:
        time.sleep(1)

first, last = rows[0], rows[-1]
elapsed = last["at"] - first["at"]
summary = {
    "label": args.label,
    "pid": args.pid,
    "seconds": elapsed,
    "cpu_percent_one_core": (last["cpu_ns"] - first["cpu_ns"]) / 1e9 / elapsed * 100,
    "exited_child_cpu_seconds": (last["child_cpu_ns"] - first["child_cpu_ns"]) / 1e9,
    "rss_mib_median": statistics.median(row["rss_bytes"] for row in rows) / 1048576,
    "footprint_mib_median": statistics.median(row["footprint_bytes"] for row in rows) / 1048576,
    "footprint_mib_peak_interval": max(row["footprint_bytes"] for row in rows) / 1048576,
    "disk_read_bytes": last["disk_read_bytes"] - first["disk_read_bytes"],
    "disk_write_bytes": last["disk_write_bytes"] - first["disk_write_bytes"],
    "logical_write_bytes": last["logical_write_bytes"] - first["logical_write_bytes"],
    "idle_wakeups_per_second": (last["idle_wakeups"] - first["idle_wakeups"]) / elapsed,
    "interrupt_wakeups_per_second": (last["interrupt_wakeups"] - first["interrupt_wakeups"]) / elapsed,
    "pageins": last["pageins"] - first["pageins"],
    "context_switches_per_second": (last["context_switches"] - first["context_switches"]) / elapsed,
    "threads_max": max(row["threads"] for row in rows),
}
Path(args.output).write_text(json.dumps({"summary": summary, "samples": rows}, indent=2) + "\n")
print(json.dumps(summary, indent=2))
