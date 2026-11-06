#!/usr/bin/env python3
"""Local stand-in for Supabase, for end-to-end tests and offline development.

Starts a throwaway Postgres (+ Supabase auth stub + all migrations), PostgREST,
and a tiny proxy on http://127.0.0.1:54321 that serves:
  /auth/v1/signup, /auth/v1/token, /auth/v1/user   (anonymous guests, HS256 JWTs)
  /rest/v1/*                                      (forwarded to PostgREST)

  python3 tools/dev_backend.py            # runs until Ctrl-C
  python3 tools/dev_backend.py --e2e      # also runs tests/test_online_e2e.gd against it, then exits
Needs: brew install postgresql@16 postgrest
shortcut: no Apple/Google identities here; linking is tested against real Supabase only.
"""
import base64
import glob
import hashlib
import hmac
import http.server
import json
import os
import pathlib
import secrets
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import urllib.error
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
SECRET = "dev-only-secret-at-least-32-characters-long!!"
PORT, PG_PORT, PGRST_PORT = 54321, 55433, 54322
PGBIN = sorted(glob.glob("/opt/homebrew/opt/postgresql@*/bin") + glob.glob("/usr/lib/postgresql/*/bin"))
PATH = (PGBIN[-1] + os.pathsep if PGBIN else "") + os.environ["PATH"]
refresh_tokens = {}


def b64(b):
    return base64.urlsafe_b64encode(b).rstrip(b"=").decode()


def jwt(sub):
    head = b64(json.dumps({"alg": "HS256", "typ": "JWT"}).encode())
    body = b64(json.dumps({"sub": sub, "role": "authenticated", "exp": int(time.time()) + 3600}).encode())
    sig = b64(hmac.new(SECRET.encode(), f"{head}.{body}".encode(), hashlib.sha256).digest())
    return f"{head}.{body}.{sig}"


def sub_of(token):
    try:
        return json.loads(base64.urlsafe_b64decode(token.split(".")[1] + "=="))["sub"]
    except Exception:
        return None


def psql(dirpath, sql):
    return subprocess.run(["psql", "-h", dirpath, "-p", str(PG_PORT), "-U", "postgres", "-qtAX", "-v", "ON_ERROR_STOP=1", "-c", sql],
                          check=True, capture_output=True, text=True, env={**os.environ, "PATH": PATH}).stdout.strip()


class Proxy(http.server.BaseHTTPRequestHandler):
    pg_dir = ""

    def log_message(self, *a):
        pass

    def _send(self, code, data):
        body = json.dumps(data).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _session(self, uid):
        rt = secrets.token_hex(16)
        refresh_tokens[rt] = uid
        return {"access_token": jwt(uid), "refresh_token": rt, "expires_in": 3600, "token_type": "bearer",
                "user": {"id": uid, "is_anonymous": True, "identities": []}}

    def _body(self):
        n = int(self.headers.get("Content-Length") or 0)
        return self.rfile.read(n) if n else b""

    def do_POST(self):
        if self.path.startswith("/auth/v1/signup"):
            uid = psql(self.pg_dir, "insert into auth.users default values returning id")
            return self._send(200, self._session(uid))
        if self.path.startswith("/auth/v1/token"):
            rt = json.loads(self._body() or b"{}").get("refresh_token", "")
            return self._send(200, self._session(refresh_tokens[rt])) if rt in refresh_tokens else self._send(400, {"error": "invalid_grant"})
        self._forward("POST")

    def do_GET(self):
        if self.path.startswith("/auth/v1/user"):
            uid = sub_of(self.headers.get("Authorization", "").replace("Bearer ", ""))
            return self._send(200, {"id": uid, "is_anonymous": True, "identities": []}) if uid else self._send(401, {})
        self._forward("GET")

    def _forward(self, method):
        if not self.path.startswith("/rest/v1/"):
            return self._send(404, {"message": "not found"})
        req = urllib.request.Request(f"http://127.0.0.1:{PGRST_PORT}/" + self.path[len("/rest/v1/"):], method=method,
                                     data=self._body() if method == "POST" else None)
        for h in ("Authorization", "Content-Type", "Prefer"):
            if self.headers.get(h):
                req.add_header(h, self.headers[h])
        try:
            with urllib.request.urlopen(req, timeout=15) as r:
                code, body = r.status, r.read()
        except urllib.error.HTTPError as e:
            code, body = e.code, e.read()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def main():
    env = {**os.environ, "PATH": PATH}
    d = tempfile.mkdtemp(prefix="harvest-pg-")
    procs = []
    try:
        subprocess.run(["initdb", "-D", d, "-U", "postgres", "-A", "trust"], check=True, capture_output=True, env=env)
        subprocess.run(["pg_ctl", "-D", d, "-o", f"-p {PG_PORT} -k {d}", "-l", f"{d}/log", "start", "-w"], check=True, capture_output=True, env=env)
        for f in [ROOT / "backend/tests/supabase_stub.sql", *sorted((ROOT / "backend/supabase/migrations").glob("*.sql"))]:
            subprocess.run(["psql", "-h", d, "-p", str(PG_PORT), "-U", "postgres", "-qX", "-v", "ON_ERROR_STOP=1", "-f", str(f)], check=True, capture_output=True, env=env)
        conf = pathlib.Path(d) / "postgrest.conf"
        conf.write_text(f'db-uri = "postgres://postgres@/postgres?host={d}&port={PG_PORT}"\ndb-schemas = "public"\n'
                        f'db-anon-role = "anon"\njwt-secret = "{SECRET}"\nserver-port = {PGRST_PORT}\nserver-host = "127.0.0.1"\n')
        procs.append(subprocess.Popen(["postgrest", str(conf)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, env=env))
        for _ in range(50):
            try:
                urllib.request.urlopen(f"http://127.0.0.1:{PGRST_PORT}/", timeout=1)
                break
            except Exception:
                time.sleep(0.2)
        Proxy.pg_dir = d
        srv = http.server.ThreadingHTTPServer(("127.0.0.1", PORT), Proxy)
        threading.Thread(target=srv.serve_forever, daemon=True).start()
        url = f"http://127.0.0.1:{PORT}"
        print("dev backend ready:", url, flush=True)
        if "--e2e" in sys.argv:
            godot = shutil.which("godot") or "godot"
            r = subprocess.run([godot, "--headless", "--path", str(ROOT), "--script", "res://tests/e2e_runner.gd"],
                               env={**env, "HARVEST_BACKEND_URL": url, "HARVEST_BACKEND_KEY": "dev"}, timeout=180)
            sys.exit(r.returncode)
        while True:
            time.sleep(3600)
    except KeyboardInterrupt:
        pass
    finally:
        for p in procs:
            p.terminate()
        subprocess.run(["pg_ctl", "-D", d, "stop", "-m", "immediate"], capture_output=True, env=env)
        shutil.rmtree(d, ignore_errors=True)


if __name__ == "__main__":
    main()
