#!/usr/bin/env python3
"""Localhost JSON-RPC relay to an upstream HTTPS RPC, via curl.

Why this exists: in a proxied sandbox (agent proxy + istio egress), anvil's fork
transport does NOT honor HTTPS_PROXY, so its "direct" connection is blocked by the
egress gateway (HTTP 403 from istio-envoy) even though the host is allowed. curl,
by contrast, uses the proxy and the trusted CA bundle correctly. So we let anvil
fork from this loopback relay (127.0.0.1, never intercepted) and have curl do the
real egress. No TLS/proxy flags for anvil, no policy bypass — just reuse the tool
that already works.

Usage:  python3 rpc_forward.py <LISTEN_PORT> <UPSTREAM_URL>
Then:   anvil --fork-url http://127.0.0.1:<LISTEN_PORT> --fork-block-number <N>
"""
import sys, subprocess
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

if len(sys.argv) < 3:
    print("usage: rpc_forward.py <LISTEN_PORT> <UPSTREAM_URL>", file=sys.stderr); sys.exit(2)
PORT = int(sys.argv[1]); UPSTREAM = sys.argv[2]
ERR = b'{"jsonrpc":"2.0","id":null,"error":{"code":-32000,"message":"relay error"}}'


class H(BaseHTTPRequestHandler):
    def _relay(self, body):
        # curl inherits HTTPS_PROXY + the trusted CA bundle already set up in the sandbox.
        p = subprocess.run(
            ["curl", "-sS", "--max-time", "60", "-X", "POST", UPSTREAM,
             "-H", "content-type: application/json", "--data-binary", "@-"],
            input=body, capture_output=True)
        return p.stdout if p.stdout else ERR

    def do_POST(self):
        try:
            n = int(self.headers.get("content-length", 0) or 0)
            out = self._relay(self.rfile.read(n))
            self.send_response(200)
            self.send_header("content-type", "application/json")
            self.send_header("content-length", str(len(out)))
            self.end_headers()
            self.wfile.write(out)
        except Exception:
            try:
                self.send_response(200); self.send_header("content-length", str(len(ERR)))
                self.end_headers(); self.wfile.write(ERR)
            except Exception:
                pass

    def do_GET(self):  # health probe
        self.send_response(200); self.end_headers(); self.wfile.write(b"ok")

    def log_message(self, *a):  # quiet
        pass


if __name__ == "__main__":
    srv = ThreadingHTTPServer(("127.0.0.1", PORT), H)
    print(f"rpc_forward: 127.0.0.1:{PORT} -> {UPSTREAM}", flush=True)
    srv.serve_forever()
