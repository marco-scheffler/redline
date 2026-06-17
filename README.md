# MacBook Stress Test

A native-styled macOS stress testing tool with a dark, Apple-inspired interface.
Push CPU, GPU, memory and disk to their limits and watch the system respond in
real time — useful for thermal testing, benchmarking stability, and burn-in.

![Platform](https://img.shields.io/badge/platform-macOS-black)
![Python](https://img.shields.io/badge/python-3.8%2B-blue)

## Features

- **CPU** — multi-core load across all logical cores, selectable workload
  (float / integer / mixed) and run duration.
- **GPU (Metal)** — a compute shader keeps the GPU busy via a small Swift helper,
  with a configurable buffer size.
- **Memory** — allocates and continuously touches a chosen amount of RAM.
- **Disk I/O** — sequential / random read and write throughput tests.
- **Live system monitor** — overall CPU, memory and swap usage plus a per-core
  utilisation grid, with an activity log.

## Requirements

- macOS
- Python 3.8+
- [`psutil`](https://pypi.org/project/psutil/) (installed automatically by setup)
- Optional: Xcode Command Line Tools (`xcode-select --install`) for the
  GPU/Metal test — the Swift helper is compiled on first use.

## Usage

The simplest way — creates a virtual environment, installs dependencies and
launches the app:

```bash
./setup.sh
```

Or run it manually:

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
python3 stress_test.py
```

## Notes

The tool deliberately drives your hardware hard. Keep an eye on temperatures and
stop the tests if the machine becomes unstable. Use **Stop All** (or close the
window) to end every running test and release allocated memory.
