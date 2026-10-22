#!/usr/bin/env python3
"""Reproducible WebSocket load/compression matrix for Ludo Arena.

For each scenario this script:
  1. starts a fresh backend (compiled binary) with the scenario's WebSocket
     settings on a dedicated port and Redis logical DB (flushed first);
  2. runs bot-play in load-test mode (isolated load-test pool, no wallets);
  3. scrapes the backend's Prometheus metrics at the start and end of the
     steady-state window and samples backend + Redis CPU/RSS with `ps`;
  4. merges bot-play's client-side report (latency percentiles, errors,
     resyncs, hash mismatches).

Results are written to bot-play/loadtest-results/<timestamp>.json and a
Markdown table to stdout. Wire bytes are MEASURED on the server socket
(WebSocket frames incl. headers, after compression, before TLS); payload
bytes are the uncompressed application messages.

Usage (development only; the backend refuses load-test sessions in production):
  BACKEND_BIN=/path/to/server BOTPLAY_BIN=/path/to/bot-play \
  BACKEND_ENV_FILE=/path/to/dev.env BOT_SERVICE_KEY=... \
  python3 scripts/loadtest_matrix.py --bots 1000 --steady 60
"""
import argparse
import json
import os
import re
import signal
import subprocess
import sys
import tempfile
import time
import urllib.request

HTTP_PORT = 8090
METRICS_PORT = 9095
REDIS_DB = 5

SCENARIOS = {
    "no-compression": {"WS_COMPRESSION": "disabled"},
    "deflate-nocontext-1024": {"WS_COMPRESSION": "no_context_takeover", "WS_COMPRESSION_THRESHOLD": "1024"},
    "deflate-nocontext-128": {"WS_COMPRESSION": "no_context_takeover", "WS_COMPRESSION_THRESHOLD": "128"},
    # The client must not offer server_no_context_takeover for the server to
    # keep its compression context (dart:io's default offer doesn't).
    "deflate-context-128": {"WS_COMPRESSION": "context_takeover", "WS_COMPRESSION_THRESHOLD": "128", "_client": "context_takeover"},
    "snapshots-no-compression": {"WS_COMPRESSION": "disabled", "WS_FULL_SNAPSHOTS": "true"},
    "snapshots-deflate-nocontext-1024": {"WS_COMPRESSION": "no_context_takeover", "WS_COMPRESSION_THRESHOLD": "1024", "WS_FULL_SNAPSHOTS": "true"},
}

COUNTERS = [
    "ws_payload_bytes_sent_total", "ws_wire_bytes_sent_total",
    "ws_payload_bytes_received_total", "ws_wire_bytes_received_total",
    "process_cpu_seconds_total",
]


def load_env_file(path):
    env = {}
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            k, v = line.split("=", 1)
            env[k] = v
    return env


def scrape():
    raw = urllib.request.urlopen(f"http://127.0.0.1:{METRICS_PORT}/metrics", timeout=10).read().decode()
    out = {"msgs_sent": 0.0, "msgs_recv": 0.0, "write_buckets": {}, "proc_buckets": {}}
    for line in raw.splitlines():
        if line.startswith("#"):
            continue
        m = re.match(r'^([a-zA-Z_:]+)(\{[^}]*\})?\s+([0-9.eE+-]+)$', line)
        if not m:
            continue
        name, labels, val = m.group(1), m.group(2) or "", float(m.group(3))
        if name in COUNTERS:
            out[name] = val
        elif name == "ws_messages_sent_total":
            out["msgs_sent"] += val
        elif name == "ws_messages_received_total":
            out["msgs_recv"] += val
        elif name in ("go_goroutines", "process_resident_memory_bytes"):
            out[name] = val
        elif name == "ws_connections_active":
            out.setdefault("connections", 0.0)
            out["connections"] += val
        elif name == "ws_write_seconds_bucket":
            le = re.search(r'le="([^"]+)"', labels).group(1)
            out["write_buckets"][le] = val
        elif name == "ws_message_processing_seconds_bucket":
            le = re.search(r'le="([^"]+)"', labels).group(1)
            out["proc_buckets"][le] = out["proc_buckets"].get(le, 0.0) + val
        elif name == "ws_slow_client_events_total":
            out.setdefault("slow_events", 0.0)
            out["slow_events"] += val
        elif name == "ws_messages_rejected_total":
            out.setdefault("rejected", 0.0)
            out["rejected"] += val
    return out


def hist_quantile(b0, b1, q):
    """Quantile from the delta of two cumulative Prometheus histograms."""
    items = []
    for le, v in b1.items():
        bound = float("inf") if le == "+Inf" else float(le)
        items.append((bound, v - b0.get(le, 0.0)))
    items.sort()
    total = items[-1][1] if items else 0
    if total <= 0:
        return None
    for bound, cnt in items:
        if cnt >= q * total:
            return bound
    return None


def ps_sample(pid):
    try:
        out = subprocess.check_output(["ps", "-o", "%cpu=,rss=", "-p", str(pid)], text=True).split()
        return float(out[0]), int(out[1]) * 1024
    except Exception:
        return None


def redis_pid():
    try:
        out = subprocess.check_output(["lsof", "-ti", "tcp:6390", "-sTCP:LISTEN"], text=True).split()
        return int(out[0])
    except Exception:
        return None


def run_scenario(name, overrides, args, base_env):
    env = dict(os.environ)
    env.update(base_env)
    env.update({
        "HTTP_ADDR": f":{HTTP_PORT}", "METRICS_ADDR": f"127.0.0.1:{METRICS_PORT}",
        "REDIS_DB": str(REDIS_DB), "RATE_LIMIT_DISABLED": "true", "BOT_LOADTEST_ENABLED": "true",
        "LOG_LEVEL": "warn", "WS_MAX_CONNECTIONS": str(args.bots * 2 + 100),
        "WS_FULL_SNAPSHOTS": "false",
    })
    env.update({k: v for k, v in overrides.items() if not k.startswith("_")})
    subprocess.run(["redis-cli", "-p", "6390", "-n", str(REDIS_DB), "FLUSHDB"], check=True, capture_output=True)
    log = open(os.path.join(args.out_dir, f"{name}.server.log"), "w")
    srv = subprocess.Popen([args.backend_bin], env=env, cwd=args.backend_dir, stdout=log, stderr=log)
    try:
        for _ in range(100):
            try:
                urllib.request.urlopen(f"http://127.0.0.1:{HTTP_PORT}/readyz", timeout=1)
                break
            except Exception:
                time.sleep(0.2)
        ramp_s = max(1, args.bots // args.ramp)
        cfg = {
            "app": {"environment": "development", "log_level": "warn", "log_format": "text"},
            "connection": {"compression_mode": overrides.get("_client", "no_context_takeover"),
                           "backend_http_url": f"http://localhost:{HTTP_PORT}/api/v1",
                           "backend_ws_url": f"ws://localhost:{HTTP_PORT}/api/v1/ws"},
            "bots": {"enabled": True, "modes": ["loadtest"], "max_concurrent_bots": args.bots,
                     "max_room_joins_per_second": max(50, args.ramp), "max_connection_attempts_per_second": max(50, args.ramp),
                     "lobby_wait_timeout_seconds": 60,
                     "shutdown": {"graceful_timeout_seconds": 5, "policy": "leave_now"}},
            "limits": {"max_actions_per_second_per_bot": 5},
            "loadtest": {"enabled": True, "allowed_hosts": ["localhost", "127.0.0.1"],
                         "forbidden_hosts": ["api.ludoarena.example"], "target_connections": args.bots,
                         "ramp_per_second": args.ramp, "duration_seconds": ramp_s + args.warmup + args.steady + 20,
                         "game_mix": {"ludo": 50, "ludo_quick": 30, "snakes_ladders": 20},
                         "capacity_mix": {"2": 40, "3": 20, "4": 40},
                         "think_time_ms": {"min": args.think_min, "max": args.think_max},
                         "churn_per_minute": args.churn, "slow_reader_fraction": 0.02, "slow_reader_delay_ms": 250,
                         "malformed_message_rate": 0.001,
                         "report_path": os.path.join(args.out_dir, f"{name}.botplay.json")},
            "metrics": {"enabled": True, "listen_addr": "127.0.0.1:9096"},
        }
        cfg_path = os.path.join(args.out_dir, f"{name}.botplay.yaml")
        text = json.dumps(cfg, indent=2)  # JSON is valid YAML...
        # ...except that capacity_mix needs integer keys: emit a YAML flow map.
        text = re.sub(r'"capacity_mix": \{[^}]*\}', '"capacity_mix": {2: 40, 3: 20, 4: 40}', text)
        with open(cfg_path, "w") as f:
            f.write(text)
        bot_env = dict(os.environ)
        bot_log = open(os.path.join(args.out_dir, f"{name}.botplay.log"), "w")
        bot = subprocess.Popen([args.botplay_bin, "--config", cfg_path, "--profiles", args.profiles,
                                "--i-understand-this-is-a-load-test"], env=bot_env, stdout=bot_log, stderr=bot_log,
                               cwd=args.botplay_dir)
        time.sleep(ramp_s + args.warmup)
        m0 = scrape()
        rpid = redis_pid()
        cpu, rss, rcpu, rrss = [], [], [], []
        t0 = time.time()
        while time.time() - t0 < args.steady:
            s = ps_sample(srv.pid)
            if s:
                cpu.append(s[0]); rss.append(s[1])
            if rpid:
                r = ps_sample(rpid)
                if r:
                    rcpu.append(r[0]); rrss.append(r[1])
            time.sleep(2)
        m1 = scrape()
        window = time.time() - t0
        bot.wait(timeout=args.steady + 300)
    finally:
        srv.send_signal(signal.SIGTERM)
        try:
            srv.wait(timeout=30)
        except subprocess.TimeoutExpired:
            srv.kill()
    d = lambda k: m1.get(k, 0.0) - m0.get(k, 0.0)
    report = {}
    rp = os.path.join(args.out_dir, f"{name}.botplay.json")
    if os.path.exists(rp):
        with open(rp) as f:
            report = json.load(f)
    payload, wire = d("ws_payload_bytes_sent_total"), d("ws_wire_bytes_sent_total")
    res = {
        "scenario": name, "settings": overrides, "bots": args.bots, "window_s": round(window, 1),
        "connections_at_end": m1.get("connections"),
        "server_msgs_sent_per_s": round(d("msgs_sent") / window, 1),
        "server_cmds_recv_per_s": round(d("msgs_recv") / window, 1),
        "payload_sent_KBps": round(payload / window / 1024, 1),
        "wire_sent_KBps": round(wire / window / 1024, 1),
        "wire_over_payload": round(wire / payload, 3) if payload else None,
        "avg_payload_bytes_per_msg": round(payload / max(1, d("msgs_sent")), 1),
        "avg_wire_bytes_per_msg": round(wire / max(1, d("msgs_sent")), 1),
        "server_cpu_cores_avg": round(d("process_cpu_seconds_total") / window, 3),
        "server_cpu_pct_ps_max": max(cpu) if cpu else None,
        "server_rss_MB_max": round(max(rss) / 2**20, 1) if rss else None,
        "server_goroutines_end": m1.get("go_goroutines"),
        "redis_cpu_pct_avg": round(sum(rcpu) / len(rcpu), 1) if rcpu else None,
        "redis_rss_MB_max": round(max(rrss) / 2**20, 1) if rrss else None,
        "server_write_p99_le_s": hist_quantile(m0["write_buckets"], m1["write_buckets"], 0.99),
        "server_cmd_processing_p95_le_s": hist_quantile(m0["proc_buckets"], m1["proc_buckets"], 0.95),
        "server_cmd_processing_p99_le_s": hist_quantile(m0["proc_buckets"], m1["proc_buckets"], 0.99),
        "slow_client_events": d("slow_events") if "slow_events" in m1 else 0,
        "rejected_msgs": d("rejected") if "rejected" in m1 else 0,
        "botplay": report,
    }
    return res


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--bots", type=int, default=1000)
    ap.add_argument("--ramp", type=int, default=100, help="new bots per second")
    ap.add_argument("--warmup", type=int, default=15)
    ap.add_argument("--steady", type=int, default=60)
    ap.add_argument("--think-min", type=int, default=200)
    ap.add_argument("--think-max", type=int, default=800)
    ap.add_argument("--churn", type=int, default=30)
    ap.add_argument("--scenarios", default=",".join(SCENARIOS))
    ap.add_argument("--out-dir", default=None)
    args = ap.parse_args()
    here = os.path.dirname(os.path.abspath(__file__))
    args.botplay_dir = os.path.dirname(here)
    args.backend_dir = os.path.join(os.path.dirname(args.botplay_dir), "backend")
    args.profiles = os.path.join(args.botplay_dir, "configs", "profiles.yaml")
    args.backend_bin = os.environ["BACKEND_BIN"]
    args.botplay_bin = os.environ["BOTPLAY_BIN"]
    base_env = load_env_file(os.environ["BACKEND_ENV_FILE"])
    if not os.environ.get("BOT_SERVICE_KEY"):
        sys.exit("BOT_SERVICE_KEY is required")
    args.out_dir = args.out_dir or tempfile.mkdtemp(prefix="ludo-loadtest-")
    os.makedirs(args.out_dir, exist_ok=True)
    results = []
    for name in args.scenarios.split(","):
        print(f"== {name} ({args.bots} bots)", file=sys.stderr, flush=True)
        results.append(run_scenario(name, SCENARIOS[name], args, base_env))
        print(json.dumps({k: v for k, v in results[-1].items() if k != "botplay"}), file=sys.stderr, flush=True)
    out = os.path.join(args.out_dir, "matrix.json")
    with open(out, "w") as f:
        json.dump(results, f, indent=2)
    print(out)


if __name__ == "__main__":
    main()
