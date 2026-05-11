#!/usr/bin/env python3
import argparse
import json
import re
import subprocess
from urllib.parse import parse_qs, urlparse
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


ROOT = Path(__file__).resolve().parent
MATLAB = "/Applications/MATLAB_R2026a.app/bin/matlab"
TEST_SCRIPT = ROOT / "testCCA.m"
CONFIG_SCRIPT = ROOT / "write_ssvep_config.m"


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
    command = [MATLAB, "-batch", f"run('{CONFIG_SCRIPT.as_posix()}')"]
    completed = subprocess.run(
        command,
        cwd=ROOT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=60,
        check=False,
    )
    if completed.returncode != 0:
        raise RuntimeError(completed.stdout or f"MATLAB config exited with {completed.returncode}")


def run_cca(commands=None):
    write_config(commands)
    command = [MATLAB, "-batch", f"run('{TEST_SCRIPT.as_posix()}')"]
    completed = subprocess.run(
        command,
        cwd=ROOT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=60,
        check=False,
    )
    if completed.returncode != 0:
        raise RuntimeError(completed.stdout or f"MATLAB exited with {completed.returncode}")
    result = parse_matlab_output(completed.stdout)
    result["raw_output"] = completed.stdout.strip()
    return result


class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(ROOT), **kwargs)

    def do_GET(self):
        if self.path.startswith("/api/recognize"):
            self.handle_recognize()
            return
        super().do_GET()

    def send_json(self, status, payload):
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
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


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=9000)
    args = parser.parse_args()

    server = ThreadingHTTPServer((args.host, args.port), Handler)
    print(f"SSVEP server running at http://{args.host}:{args.port}/index.html")
    print("Recognition API: /api/recognize")
    server.serve_forever()


if __name__ == "__main__":
    main()
