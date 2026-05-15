#!/usr/bin/env python3
import argparse
import hashlib
import os
import socket
import subprocess
import sys
import threading
import time
import webbrowser
from pathlib import Path


ROOT = Path(__file__).resolve().parent
VENV_DIR = ROOT / ".venv"
REQUIREMENTS_FILE = ROOT / "requirements.txt"
REQUIREMENTS_STAMP = VENV_DIR / ".requirements.sha256"
MIN_PYTHON = (3, 10)


def info(message):
    print(message, flush=True)


def fail(message, code=1):
    info(message)
    raise SystemExit(code)


def check_python_version():
    if sys.version_info < MIN_PYTHON:
        fail(
            f"需要 Python {MIN_PYTHON[0]}.{MIN_PYTHON[1]} 或更高版本，"
            f"当前版本是 {sys.version.split()[0]}"
        )


def get_venv_python():
    if os.name == "nt":
        return VENV_DIR / "Scripts" / "python.exe"
    return VENV_DIR / "bin" / "python"


def ensure_venv():
    python_bin = get_venv_python()
    if python_bin.exists():
        return python_bin

    info("首次启动，正在创建虚拟环境 .venv ...")
    subprocess.check_call([sys.executable, "-m", "venv", str(VENV_DIR)], cwd=ROOT)
    if not python_bin.exists():
        fail("虚拟环境创建失败，未找到 venv 里的 Python。")
    return python_bin


def relaunch_in_venv():
    python_bin = ensure_venv()
    current_python = Path(sys.executable).resolve()
    target_python = python_bin.resolve()
    if current_python == target_python:
        return

    info(f"切换到虚拟环境 Python: {target_python}")
    command = [str(target_python), str(Path(__file__).resolve()), *sys.argv[1:]]
    raise SystemExit(subprocess.call(command, cwd=ROOT))


def read_effective_requirements():
    if not REQUIREMENTS_FILE.exists():
        return "", []

    content = REQUIREMENTS_FILE.read_text(encoding="utf-8")
    effective = []
    for raw_line in content.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        effective.append(line)
    return content, effective


def ensure_pip():
    subprocess.check_call([sys.executable, "-m", "ensurepip", "--upgrade"], cwd=ROOT)


def install_requirements_if_needed():
    content, effective = read_effective_requirements()
    if not REQUIREMENTS_FILE.exists():
        info("未找到 requirements.txt，跳过依赖安装。")
        return

    if not effective:
        info("requirements.txt 当前没有额外依赖，跳过安装。")
        return

    digest = hashlib.sha256(content.encode("utf-8")).hexdigest()
    if REQUIREMENTS_STAMP.exists():
        saved = REQUIREMENTS_STAMP.read_text(encoding="utf-8").strip()
        if saved == digest:
            info("依赖已是最新，跳过安装。")
            return

    info("正在检查并安装 Python 依赖 ...")
    ensure_pip()
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-r", str(REQUIREMENTS_FILE)], cwd=ROOT)
    REQUIREMENTS_STAMP.write_text(digest, encoding="utf-8")
    info("依赖安装完成。")


def find_free_port(start_port, span=100, host="127.0.0.1"):
    bind_host = "0.0.0.0" if host == "::" else host
    for port in range(start_port, start_port + span):
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
            try:
                sock.bind((bind_host, port))
            except OSError:
                continue
            return port
    fail(f"{start_port}-{start_port + span - 1} 没有可用端口。")


def detect_matlab():
    try:
        from ssvep_server import resolve_matlab_bin
    except Exception as error:
        info(f"MATLAB 检测模块加载失败: {error}")
        return None
    return resolve_matlab_bin(required=False)


def detect_lan_ips():
    try:
        from ssvep_server import get_lan_ips
    except Exception:
        return []
    return get_lan_ips()


def open_browser(url):
    def _worker():
        time.sleep(1.0)
        try:
            opened = webbrowser.open(url, new=2)
            if not opened and os.name == "nt":
                os.startfile(url)
        except Exception as error:
            info(f"自动打开浏览器失败，请手动打开：{url}")
            info(f"浏览器错误：{error}")

    threading.Thread(target=_worker, daemon=True).start()


def run_server(host, port, matlab_bin=None):
    command = [sys.executable, str(ROOT / "ssvep_server.py"), "--host", host, "--port", str(port)]
    env = os.environ.copy()
    if matlab_bin:
        env["MATLAB_BIN"] = matlab_bin
        command.extend(["--matlab", matlab_bin])
    subprocess.check_call(command, cwd=ROOT, env=env)


def parse_args():
    parser = argparse.ArgumentParser(description="SSVEP 控制台一键启动器")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8000, help="起始端口；若被占用会自动顺延")
    parser.add_argument("--no-browser", action="store_true", help="仅启动服务，不自动打开浏览器")
    parser.add_argument("--matlab", help="手动指定 MATLAB 可执行文件路径")
    return parser.parse_args()


def main():
    args = parse_args()
    check_python_version()
    relaunch_in_venv()
    install_requirements_if_needed()
    matlab_bin = args.matlab or detect_matlab()
    port = find_free_port(args.port, host=args.host)
    browser_host = "127.0.0.1" if args.host in {"0.0.0.0", "::"} else args.host
    url = f"http://{browser_host}:{port}/index.html"
    stimulus_url = f"http://{browser_host}:{port}/stimulus.html"
    lan_ips = detect_lan_ips()

    info("")
    info("气动手套 SSVEP 控制台准备启动")
    info(f"工作目录：{ROOT}")
    info(f"控制页：{url}")
    info(f"被试页：{stimulus_url}")
    if args.host in {"0.0.0.0", "::"} and lan_ips:
        for ip in lan_ips:
            info(f"局域网控制页：http://{ip}:{port}/index.html")
            info(f"局域网被试页：http://{ip}:{port}/stimulus.html")
            info(f"MATLAB 上报地址：http://{ip}:{port}/api/eeg_result")
    else:
        info(f"MATLAB 本机上报地址：http://{browser_host}:{port}/api/eeg_result")
    info(f"离线测试接口：http://{browser_host}:{port}/api/recognize")
    info(f"健康检查：http://{browser_host}:{port}/api/health")
    if matlab_bin:
        info(f"MATLAB：{matlab_bin}")
    else:
        info("MATLAB：未检测到。识别接口启动后会报错，请先安装 MATLAB 或设置 MATLAB_BIN。")
    info("提示：Web Bluetooth 建议使用 Chrome 或 Edge 打开。")
    info("停止服务：在当前窗口按 Ctrl+C")
    info("")

    if not args.no_browser:
        open_browser(url)

    run_server(args.host, port, matlab_bin=matlab_bin)


if __name__ == "__main__":
    main()
