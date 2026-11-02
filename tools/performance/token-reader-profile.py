"""Run one token-reader benchmark while sampling macOS process counters."""

import argparse
import json
import subprocess
import time
from pathlib import Path


def sample(helper: str, pid: int) -> dict:
    return json.loads(subprocess.check_output([helper, str(pid)], text=True))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--helper", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("program")
    parser.add_argument("args", nargs=argparse.REMAINDER)
    options = parser.parse_args()

    output = Path(options.output)
    started = time.monotonic()
    with output.open("w") as result_file:
        process = subprocess.Popen([options.program, *options.args], stdout=result_file)
        first = sample(options.helper, process.pid)
        samples = [first]
        while process.poll() is None:
            time.sleep(0.1)
            try:
                samples.append(sample(options.helper, process.pid))
            except subprocess.CalledProcessError:
                break
        return_code = process.wait()
    elapsed = time.monotonic() - started
    if return_code != 0:
        raise subprocess.CalledProcessError(return_code, [options.program, *options.args])

    last = samples[-1]
    summary = {
        "return_code": return_code,
        "wall_seconds": elapsed,
        "sample_count": len(samples),
        "sampled_cpu_percent_one_core": (last["cpu_ns"] - first["cpu_ns"]) / 1e9 / elapsed * 100,
        "sampled_rss_peak_bytes": max(item["rss_bytes"] for item in samples),
        "sampled_footprint_peak_bytes": max(item["footprint_bytes"] for item in samples),
        "kernel_peak_footprint_bytes": max(item["peak_footprint_bytes"] for item in samples),
        "kernel_disk_read_bytes": last["disk_read_bytes"] - first["disk_read_bytes"],
        "kernel_pageins": last["pageins"] - first["pageins"],
        "benchmark_output": json.loads(output.read_text()),
    }
    print(json.dumps(summary, sort_keys=True))


if __name__ == "__main__":
    main()
