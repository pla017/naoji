#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT_DIR"

if [ ! -f "index.html" ]; then
  echo "未找到 index.html，请确认脚本和 index.html 在同一个目录。"
  exit 1
fi

if [ ! -f "ssvep_server.py" ]; then
  echo "未找到 ssvep_server.py，请确认脚本和 index.html 在同一个目录。"
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

START_PORT="${PORT:-8000}"
PORT="$("$PYTHON_BIN" - "$START_PORT" <<'PY'
import socket
import sys

start = int(sys.argv[1])
for port in range(start, start + 100):
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        try:
            sock.bind(("127.0.0.1", port))
        except OSError:
            continue
        print(port)
        break
else:
    raise SystemExit("8000-8099 没有可用端口")
PY
)"

URL="http://127.0.0.1:${PORT}/index.html"

echo ""
echo "气动手套 SSVEP 控制台已准备启动"
echo "访问地址：${URL}"
echo "算法接口：http://127.0.0.1:${PORT}/api/recognize"
echo ""
echo "提示：Web Bluetooth 建议使用 Chrome 或 Edge 打开。"
echo "停止服务：在这个窗口按 Ctrl+C"
echo ""

if command -v open >/dev/null 2>&1; then
  open "$URL" >/dev/null 2>&1 || true
fi

"$PYTHON_BIN" ssvep_server.py --port "$PORT"
