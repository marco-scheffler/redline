#!/bin/bash
# MacBook Stress Test - Setup & Run
set -e

cd "$(dirname "$0")"

echo "=== MacBook Stress Test Setup ==="

# Check for Python 3
if ! command -v python3 &>/dev/null; then
    echo "ERROR: python3 not found. Install Python 3 first."
    exit 1
fi

# Check for swiftc (needed for GPU stress)
if command -v swiftc &>/dev/null; then
    echo "[OK] swiftc found - GPU stress available"
else
    echo "[WARN] swiftc not found - install Xcode CLI tools for GPU stress:"
    echo "       xcode-select --install"
fi

# Create venv if needed
if [ ! -d ".venv" ]; then
    echo "Creating virtual environment..."
    python3 -m venv .venv
fi

source .venv/bin/activate
echo "Installing dependencies..."
pip install -q -r requirements.txt

echo ""
echo "=== Starting Stress Test ==="
python3 stress_test.py
