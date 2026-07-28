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

is_supported_python() {
  "$1" -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 10) else 1)' >/dev/null 2>&1
}

PYTHON_BIN=""
for candidate in "$ROOT_DIR/.venv/bin/python" "$ROOT_DIR/.venv/bin/python3" python3 python; do
  if command -v "$candidate" >/dev/null 2>&1 || [ -x "$candidate" ]; then
    if is_supported_python "$candidate"; then
      PYTHON_BIN="$candidate"
      break
    fi
  fi
done

if [ -z "$PYTHON_BIN" ]; then
  echo "未找到 Python 3.10 或更高版本。"
  echo "当前 python3 可能是 Xcode 自带的 3.9，请先安装：brew install python@3.13"
  echo "安装后重新运行：./start.sh"
  exit 1
fi

echo "使用 Python：$PYTHON_BIN"

"$PYTHON_BIN" launcher.py "$@"
