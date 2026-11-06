#!/usr/bin/env python3
"""Generate config/backend.json (git-ignored) from environment variables or .env.

Only the PUBLIC anon key belongs here. Never the service_role key.
Usage: python3 tools/write_config.py
"""
import json
import os
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent


def read_dotenv() -> dict:
    env = {}
    p = ROOT / ".env"
    if p.exists():
        for line in p.read_text().splitlines():
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                env[k.strip()] = v.strip()
    return env


def main() -> None:
    dot = read_dotenv()
    url = os.environ.get("SUPABASE_URL") or dot.get("SUPABASE_URL", "")
    key = os.environ.get("SUPABASE_ANON_KEY") or dot.get("SUPABASE_ANON_KEY", "")
    if "YOUR-PROJECT" in url:
        url, key = "", ""
    if "service_role" in key:
        raise SystemExit("Refusing to write a service_role key into the client.")
    out = ROOT / "config" / "backend.json"
    out.parent.mkdir(exist_ok=True)
    out.write_text(json.dumps({"supabase_url": url, "supabase_anon_key": key}, indent=2))
    print(f"wrote {out.relative_to(ROOT)} (online={'yes' if url and key else 'no — offline build'})")


if __name__ == "__main__":
    main()
