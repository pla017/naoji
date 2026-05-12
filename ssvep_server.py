#!/usr/bin/env python3
import argparse
import json
import os
import queue
import re
import shutil
import socket
import subprocess
import sys
import threading
import time
from glob import glob
from urllib.parse import parse_qs, urlparse
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


ROOT = Path(__file__).resolve().parent
TEST_SCRIPT = ROOT / "testCCA.m"
CONFIG_SCRIPT = ROOT / "write_ssvep_config.m"

DEFAULT_COMMANDS = [
    {"id": "open", "name": "手张开", "symbol": "开", "freq": 8.50, "hex": "A5 5A 02 0B 0F 00 00 00 00 00 E4"},
    {"id": "close", "name": "手握紧", "symbol": "握", "freq": 8.75, "hex": "A5 5A 02 0B 0F 01 01 01 01 01 DF"},
    {"id": "thumb", "name": "大拇指屈曲", "symbol": "拇", "freq": 9.00, "hex": "A5 5A 02 0B 0F 01 00 00 00 00 E3"},
    {"id": "index", "name": "食指屈曲", "symbol": "食", "freq": 9.25, "hex": "A5 5A 02 0B 0F 00 01 00 00 00 E3"},
    {"id": "middle", "name": "中指屈曲", "symbol": "中", "freq": 9.50, "hex": "A5 5A 02 0B 0F 00 00 01 00 00 E3"},
    {"id": "ring", "name": "无名指屈曲", "symbol": "名", "freq": 9.75, "hex": "A5 5A 02 0B 0F 00 00 00 01 00 E3"},
    {"id": "little", "name": "小拇指屈曲", "symbol": "小", "freq": 10.00, "hex": "A5 5A 02 0B 0F 00 00 00 00 01 E3"},
    {"id": "start", "name": "开始", "symbol": "启", "freq": 10.25, "hex": "A5 5A 02 07 0A 01 EC", "skipPrime": True},
    {"id": "pause", "name": "暂停", "symbol": "停", "freq": 10.50, "hex": "A5 5A 02 07 0A 00 ED", "skipPrime": True},
]

STATE_LOCK = threading.RLock()
EVENT_CLIENTS = set()
APP_STATE = {
    "session": {
        "active": False,
        "started_at": None,
        "stopped_at": None,
    },
    "config": {
        "commands": DEFAULT_COMMANDS,
    },
    "last_result": None,
    "last_stim_onset": None,
}


def iter_matlab_candidates():
    env_value = os.environ.get("MATLAB_BIN", "").strip()
    if env_value:
        yield env_value

    which_value = shutil.which("matlab")
    if which_value:
        yield which_value

    if sys.platform.startswith("win"):
        patterns = [
            r"C:\Program Files\MATLAB\R*\bin\matlab.exe",
            r"C:\Program Files\MATLAB\*\bin\matlab.exe",
        ]
    elif sys.platform == "darwin":
        patterns = [
            "/Applications/MATLAB_R*.app/bin/matlab",
            "/Applications/MATLAB_*.app/bin/matlab",
        ]
    else:
        patterns = [
            "/usr/local/MATLAB/R*/bin/matlab",
            "/usr/local/MATLAB/*/bin/matlab",
            "/opt/MATLAB/R*/bin/matlab",
        ]

    for pattern in patterns:
        for candidate in sorted(glob(pattern), reverse=True):
            yield candidate


def resolve_matlab_bin(required=True):
    checked = []
    for candidate in iter_matlab_candidates():
        path = Path(candidate).expanduser()
        checked.append(str(path))
        if path.exists():
            return str(path)
        which_value = shutil.which(str(path))
        if which_value:
            return which_value

    if required:
        hint = (
            "未找到 MATLAB。请先安装 MATLAB，并确保 `matlab` 已加入 PATH，"
            "或设置环境变量 MATLAB_BIN 指向 matlab 可执行文件。"
        )
        if checked:
            hint = f"{hint}\n已检查路径:\n- " + "\n- ".join(checked)
        raise RuntimeError(hint)
    return None


def now_ms():
    return int(time.time() * 1000)


def get_lan_ips():
    ips = []
    try:
        hostname = socket.gethostname()
        for item in socket.getaddrinfo(hostname, None, socket.AF_INET):
            ip = item[4][0]
            if ip not in ips and not ip.startswith("127."):
                ips.append(ip)
    except OSError:
        pass

    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
            sock.connect(("8.8.8.8", 80))
            ip = sock.getsockname()[0]
            if ip not in ips and not ip.startswith("127."):
                ips.append(ip)
    except OSError:
        pass
    return ips


def snapshot_state():
    with STATE_LOCK:
        return json.loads(json.dumps(APP_STATE, ensure_ascii=False))


def normalize_commands(commands):
    normalized = []
    if not isinstance(commands, list):
        raise ValueError("commands 必须是数组")

    for index, item in enumerate(commands):
        if not isinstance(item, dict):
            raise ValueError(f"commands[{index}] 必须是对象")
        name = str(item.get("name", "")).strip()
        freq = float(item.get("freq"))
        hex_value = str(item.get("hex", "")).strip()
        if not name or not hex_value or freq <= 0:
            raise ValueError(f"commands[{index}] 缺少 name/freq/hex")
        normalized.append({
            "id": str(item.get("id") or f"target_{index + 1}"),
            "name": name,
            "symbol": str(item.get("symbol") or name[:1]),
            "freq": freq,
            "hex": hex_value,
            "skipPrime": bool(item.get("skipPrime", False)),
        })
    return normalized


def normalize_eeg_result(payload):
    if not isinstance(payload, dict):
        raise ValueError("上报内容必须是 JSON 对象")

    result = dict(payload)
    if "result" in result and isinstance(result["result"], dict):
        result = dict(result["result"])

    freq = result.get("recognized_freq", result.get("freq"))
    if freq is not None:
        result["recognized_freq"] = float(freq)

    confidence = result.get("confidence_ratio", result.get("confidence"))
    if confidence is not None:
        result["confidence_ratio"] = float(confidence)

    target = result.get("target", result.get("target_id", result.get("id")))
    if target is not None:
        result["target"] = str(target)

    command_name = result.get("command_name", result.get("name"))
    if command_name is not None:
        result["command_name"] = str(command_name)

    command_hex = result.get("command_hex", result.get("hex"))
    if command_hex is not None:
        result["command_hex"] = str(command_hex)

    result.setdefault("source", "matlab")
    result.setdefault("timestamp_ms", now_ms())
    result.setdefault("type", "eeg_result")

    if "recognized_freq" not in result and "target" not in result and "command_hex" not in result:
        raise ValueError("eeg_result 至少需要 recognized_freq、target 或 command_hex 之一")
    return result


def encode_sse(event_name, data):
    payload = json.dumps(data, ensure_ascii=False, separators=(",", ":"))
    lines = [f"event: {event_name}", f"id: {now_ms()}"]
    lines.extend(f"data: {line}" for line in payload.splitlines() or [""])
    return ("\n".join(lines) + "\n\n").encode("utf-8")


def broadcast(event_name, data):
    event = {
        "event": event_name,
        "data": data,
        "timestamp_ms": now_ms(),
    }
    stale_clients = []
    with STATE_LOCK:
        clients = list(EVENT_CLIENTS)

    for client in clients:
        try:
            client.put_nowait(event)
        except queue.Full:
            stale_clients.append(client)

    if stale_clients:
        with STATE_LOCK:
            for client in stale_clients:
                EVENT_CLIENTS.discard(client)
    return len(clients) - len(stale_clients)


def parse_matlab_output(output):
    patterns = {
        "recognized_freq": r"recognized_freq:\s*([0-9.]+)",
        "command_name": r"command_name:\s*(.+)",
        "recognized_freq_index": r"recognized_freq_index:\s*(\d+)",
        "command_hex": r"command_hex:\s*([0-9A-Fa-f ]*)",
        "confidence_ratio": r"confidence_ratio:\s*([0-9.]+)",
    }
    result = {}
    for key, pattern in patterns.items():
        match = re.search(pattern, output)
        if match:
            result[key] = match.group(1).strip()

    if "recognized_freq" in result:
        result["recognized_freq"] = float(result["recognized_freq"])
    if "recognized_freq_index" in result:
        result["recognized_freq_index"] = int(result["recognized_freq_index"])
    if "confidence_ratio" in result:
        result["confidence_ratio"] = float(result["confidence_ratio"])

    missing = [key for key in patterns if key not in result]
    if missing:
        raise RuntimeError(f"MATLAB output missing fields: {', '.join(missing)}\n{output}")
    return result


def matlab_escape(value):
    return str(value).replace("'", "''")


def run_matlab_script(script_path, timeout=60):
    matlab_bin = resolve_matlab_bin(required=True)
    command = [matlab_bin, "-batch", f"run('{script_path.as_posix()}')"]
    completed = subprocess.run(
        command,
        cwd=ROOT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=timeout,
        check=False,
    )
    return matlab_bin, completed


def write_config(commands=None):
    if not commands:
        return
    names = ", ".join("'" + matlab_escape(item["name"]) + "'" for item in commands)
    freqs = ", ".join(f"{float(item['freq']):.8f}" for item in commands)
    hex_values = ", ".join("'" + matlab_escape(item["hex"]) + "'" for item in commands)
    script = f"""
commandTable = struct( ...
    'name', {{{names}}}, ...
    'targetIndex', num2cell(nan(1, {len(commands)})), ...
    'freq', {{{freqs}}}, ...
    'hex', {{{hex_values}}} ...
);
save(fullfile('{matlab_escape(ROOT.as_posix())}', 'ssvep_config.mat'), 'commandTable');
"""
    CONFIG_SCRIPT.write_text(script, encoding="utf-8")
    _, completed = run_matlab_script(CONFIG_SCRIPT, timeout=60)
    if completed.returncode != 0:
        raise RuntimeError(completed.stdout or f"MATLAB config exited with {completed.returncode}")


def run_cca(commands=None):
    write_config(commands)
    matlab_bin, completed = run_matlab_script(TEST_SCRIPT, timeout=60)
    if completed.returncode != 0:
        raise RuntimeError(completed.stdout or f"MATLAB exited with {completed.returncode}")
    result = parse_matlab_output(completed.stdout)
    result["matlab_bin"] = matlab_bin
    result["raw_output"] = completed.stdout.strip()
    return result


class Handler(SimpleHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(ROOT), **kwargs)

    def do_GET(self):
        if self.path.startswith("/api/recognize"):
            self.handle_recognize()
            return
        if self.path.startswith("/api/health"):
            self.handle_health()
            return
        if self.path.startswith("/api/state"):
            self.handle_state()
            return
        if self.path.startswith("/api/events"):
            self.handle_events()
            return
        super().do_GET()

    def do_POST(self):
        path = urlparse(self.path).path
        if path == "/api/eeg_result":
            self.handle_eeg_result()
            return
        if path == "/api/config":
            self.handle_config()
            return
        if path == "/api/session/start":
            self.handle_session_start()
            return
        if path == "/api/session/stop":
            self.handle_session_stop()
            return
        if path == "/api/stim_onset":
            self.handle_stim_onset()
            return
        if path == "/api/broadcast":
            self.handle_generic_broadcast()
            return
        self.send_json(404, {"ok": False, "error": "Unknown API endpoint"})

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.send_header("Content-Length", "0")
        self.end_headers()

    def read_json(self):
        length = int(self.headers.get("Content-Length", "0") or "0")
        if length <= 0:
            return {}
        body = self.rfile.read(length).decode("utf-8")
        return json.loads(body)

    def send_json(self, status, payload):
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def handle_recognize(self):
        try:
            query = parse_qs(urlparse(self.path).query)
            commands = json.loads(query["commands"][0]) if "commands" in query else None
            self.send_json(200, {"ok": True, "result": run_cca(commands)})
        except Exception as error:
            self.send_json(500, {"ok": False, "error": str(error)})

    def handle_health(self):
        matlab_bin = resolve_matlab_bin(required=False)
        self.send_json(200, {
            "ok": True,
            "root": str(ROOT),
            "matlab_found": bool(matlab_bin),
            "matlab_bin": matlab_bin,
            "lan_ips": get_lan_ips(),
            "clients": len(EVENT_CLIENTS),
        })

    def handle_state(self):
        self.send_json(200, {
            "ok": True,
            "state": snapshot_state(),
            "lan_ips": get_lan_ips(),
        })

    def handle_events(self):
        client = queue.Queue(maxsize=200)
        with STATE_LOCK:
            EVENT_CLIENTS.add(client)

        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream; charset=utf-8")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Connection", "keep-alive")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("X-Accel-Buffering", "no")
        self.end_headers()

        try:
            self.wfile.write(encode_sse("state", {
                "state": snapshot_state(),
                "lan_ips": get_lan_ips(),
            }))
            self.wfile.flush()

            while True:
                try:
                    event = client.get(timeout=15)
                    self.wfile.write(encode_sse(event["event"], event["data"]))
                except queue.Empty:
                    self.wfile.write(b": keep-alive\n\n")
                self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError, TimeoutError):
            pass
        finally:
            with STATE_LOCK:
                EVENT_CLIENTS.discard(client)

    def handle_config(self):
        try:
            payload = self.read_json()
            commands = normalize_commands(payload.get("commands", []))
            with STATE_LOCK:
                APP_STATE["config"] = {
                    **payload,
                    "commands": commands,
                    "updated_at": now_ms(),
                }
            subscribers = broadcast("config_update", APP_STATE["config"])
            self.send_json(200, {"ok": True, "subscribers": subscribers, "config": APP_STATE["config"]})
        except Exception as error:
            self.send_json(400, {"ok": False, "error": str(error)})

    def handle_session_start(self):
        try:
            payload = self.read_json()
            commands = payload.get("commands")
            with STATE_LOCK:
                if commands:
                    APP_STATE["config"] = {
                        **payload,
                        "commands": normalize_commands(commands),
                        "updated_at": now_ms(),
                    }
                APP_STATE["session"] = {
                    "active": True,
                    "started_at": now_ms(),
                    "stopped_at": None,
                    "trial": payload.get("trial"),
                }
                data = {
                    "session": APP_STATE["session"],
                    "config": APP_STATE["config"],
                }
            subscribers = broadcast("session_start", data)
            self.send_json(200, {"ok": True, "subscribers": subscribers, **data})
        except Exception as error:
            self.send_json(400, {"ok": False, "error": str(error)})

    def handle_session_stop(self):
        try:
            payload = self.read_json()
            with STATE_LOCK:
                APP_STATE["session"] = {
                    **APP_STATE["session"],
                    "active": False,
                    "stopped_at": now_ms(),
                    "reason": payload.get("reason", "manual"),
                }
                data = {
                    "session": APP_STATE["session"],
                    "config": APP_STATE["config"],
                }
            subscribers = broadcast("session_stop", data)
            self.send_json(200, {"ok": True, "subscribers": subscribers, **data})
        except Exception as error:
            self.send_json(400, {"ok": False, "error": str(error)})

    def handle_eeg_result(self):
        try:
            result = normalize_eeg_result(self.read_json())
            with STATE_LOCK:
                APP_STATE["last_result"] = result
            subscribers = broadcast("eeg_result", result)
            self.send_json(200, {"ok": True, "subscribers": subscribers, "result": result})
        except Exception as error:
            self.send_json(400, {"ok": False, "error": str(error)})

    def handle_stim_onset(self):
        try:
            payload = self.read_json()
            onset = {
                **payload,
                "type": "stim_onset",
                "server_timestamp_ms": now_ms(),
            }
            with STATE_LOCK:
                APP_STATE["last_stim_onset"] = onset
            subscribers = broadcast("stim_onset", onset)
            self.send_json(200, {"ok": True, "subscribers": subscribers, "onset": onset})
        except Exception as error:
            self.send_json(400, {"ok": False, "error": str(error)})

    def handle_generic_broadcast(self):
        try:
            payload = self.read_json()
            event = str(payload.get("event", "")).strip()
            data = payload.get("data", {})
            if not event:
                raise ValueError("event 不能为空")
            subscribers = broadcast(event, data)
            self.send_json(200, {"ok": True, "subscribers": subscribers})
        except Exception as error:
            self.send_json(400, {"ok": False, "error": str(error)})


class RealtimeHTTPServer(ThreadingHTTPServer):
    allow_reuse_address = True
    daemon_threads = True

    def handle_error(self, request, client_address):
        _, error, _ = sys.exc_info()
        if isinstance(error, (BrokenPipeError, ConnectionResetError, TimeoutError)):
            return
        super().handle_error(request, client_address)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=9000)
    parser.add_argument("--matlab", help="MATLAB 可执行文件路径，等价于设置 MATLAB_BIN")
    args = parser.parse_args()

    if args.matlab:
        os.environ["MATLAB_BIN"] = args.matlab

    server = RealtimeHTTPServer((args.host, args.port), Handler)
    print(f"SSVEP server running at http://{args.host}:{args.port}/index.html")
    if args.host in {"0.0.0.0", "::"}:
        for ip in get_lan_ips():
            print(f"LAN control page: http://{ip}:{args.port}/index.html")
            print(f"LAN stimulus page: http://{ip}:{args.port}/stimulus.html")
    print("Recognition API: /api/recognize")
    print("Realtime events: /api/events")
    print("MATLAB result POST: /api/eeg_result")
    print("Health API: /api/health")
    matlab_bin = resolve_matlab_bin(required=False)
    if matlab_bin:
        print(f"Detected MATLAB: {matlab_bin}")
    else:
        print("Detected MATLAB: NOT FOUND (set MATLAB_BIN or install MATLAB)")
    server.serve_forever()


if __name__ == "__main__":
    main()
