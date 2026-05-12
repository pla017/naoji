#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT_DIR"

if [ ! -f "launcher.py" ]; then
  echo "未找到 launcher.py，请确认脚本和启动器在同一个目录。"
  exit 1
fi

if [ ! -f "ssvep_server.py" ]; then
  echo "未找到 ssvep_server.py，请确认脚本和服务端文件在同一个目录。"
  exit 1
fi

if command -v python3 >/dev/null 2>&1; then
  PYTHON_BIN="python3"
elif command -v python >/dev/null 2>&1; then
  PYTHON_BIN="python"
else
  echo "未找到 Python。请先安装 Python 3，或使用系统自带的 python3。"
  exit 1
fi

"$PYTHON_BIN" launcher.py "$@"
