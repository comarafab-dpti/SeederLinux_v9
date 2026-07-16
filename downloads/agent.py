#!/usr/bin/env python3
"""
SeederLinux Lite - Provisioning Agent
=====================================

Checks in with the SeederLinux Lite server, downloads provisioning bundles
when available, and executes them.

No external dependencies - uses only Python 3 standard library.

Usage:
    # First check-in: bind the station to an organization
    sudo python3 agent.py --org COMARA

    # Subsequent runs: token is saved, no --org needed
    sudo python3 agent.py

    # Dry run (no execution)
    sudo python3 agent.py --org COMARA --dry-run

Configuration:
    /etc/seeder/agent.conf        - Server URL and settings
    /etc/seeder/station_token     - Station token (auto-saved on first run)

Logs:
    /var/log/seeder/agent.log

Cron (recommended): every 15 minutes
    */15 * * * * /usr/local/bin/seeder-agent >> /var/log/seeder/agent.log 2>&1
"""

import argparse
import json
import os
import sys
import platform
import subprocess
import socket
import uuid
import configparser
from datetime import datetime
from urllib.request import urlopen, Request
from urllib.error import URLError, HTTPError

# --- Configuration ---
CONFIG_DIR = "/etc/seeder"
CONFIG_FILE = os.path.join(CONFIG_DIR, "agent.conf")
TOKEN_FILE = os.path.join(CONFIG_DIR, "station_token")
LOG_FILE = "/var/log/seeder/agent.log"
BUNDLE_CACHE_DIR = "/var/cache/seeder"
BUNDLE_FILE = os.path.join(BUNDLE_CACHE_DIR, "bundle.sh")

DEFAULT_SERVER = "https://seederlinux.comara.intraer"
CHECKIN_TIMEOUT = 30  # seconds
DOWNLOAD_TIMEOUT = 60  # seconds


def log(message, level="INFO"):
    """Write a log message to the log file and stdout."""
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    line = f"[{timestamp}] [{level}] {message}"
    print(line, flush=True)
    try:
        os.makedirs(os.path.dirname(LOG_FILE), exist_ok=True)
        with open(LOG_FILE, "a") as f:
            f.write(line + "\n")
    except (IOError, PermissionError):
        pass


def parse_args():
    """Parse command-line arguments."""
    parser = argparse.ArgumentParser(
        description="SeederLinux Lite Provisioning Agent",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  First check-in (binds station to an organization):
    sudo python3 agent.py --org COMARA

  Subsequent runs (token already saved):
    sudo python3 agent.py

  Dry run:
    sudo python3 agent.py --org COMARA --dry-run

  Custom server:
    sudo python3 agent.py --org COMARA --server https://seeder.myorg.intraer
        """,
    )
    parser.add_argument(
        "--org", "-o",
        metavar="ACRONYM",
        help="Organization acronym (required on first run to bind the station)",
    )
    parser.add_argument(
        "--server", "-s",
        metavar="URL",
        help="SeederLinux Lite server URL (overrides agent.conf)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Collect system info and show what would happen, without checking in or executing bundles",
    )
    parser.add_argument(
        "--verbose", "-v",
        action="store_true",
        help="Enable verbose output",
    )
    parser.add_argument(
        "--version",
        action="version",
        version="SeederLinux Lite Agent 1.1.0",
    )
    return parser.parse_args()


def load_config(args):
    """Load configuration from config file or defaults, then apply CLI overrides."""
    config = configparser.ConfigParser()
    config.read(CONFIG_FILE)

    server = config.get("server", "url", fallback=DEFAULT_SERVER)

    # CLI --server overrides config file
    if args.server:
        server = args.server

    return {"server": server.rstrip("/")}


def load_token():
    """Read the stored station token, or return None if not present."""
    if os.path.exists(TOKEN_FILE):
        try:
            with open(TOKEN_FILE, "r") as f:
                token = f.read().strip()
                if token:
                    return token
        except (IOError, PermissionError):
            pass
    return None


def save_token(token):
    """Persist a station token to disk."""
    try:
        os.makedirs(CONFIG_DIR, exist_ok=True)
        with open(TOKEN_FILE, "w") as f:
            f.write(token)
        os.chmod(TOKEN_FILE, 0o600)
        log(f"Station token saved to {TOKEN_FILE}", "INFO")
    except (IOError, PermissionError) as e:
        log(f"Cannot save token file: {e}", "ERROR")


def collect_system_info():
    """Collect system information for check-in."""
    hostname = socket.gethostname()

    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip_address = s.getsockname()[0]
        s.close()
    except Exception:
        ip_address = "127.0.0.1"

    try:
        mac = uuid.getnode()
        mac_address = ":".join(f"{(mac >> ele) & 0xff:02x}" for ele in range(40, -1, -8))
    except Exception:
        mac_address = "00:00:00:00:00:00"

    os_name = "Linux"
    os_version = ""

    try:
        if os.path.exists("/etc/os-release"):
            with open("/etc/os-release", "r") as f:
                for line in f:
                    line = line.strip()
                    if line.startswith("NAME="):
                        os_name = line.split("=", 1)[1].strip('"')
                    elif line.startswith("VERSION="):
                        os_version = line.split("=", 1)[1].strip('"')
        else:
            os_version = platform.release()
    except Exception:
        os_version = platform.release()

    serial_number = ""
    try:
        result = subprocess.run(
            ["dmidecode", "-s", "system-serial-number"],
            capture_output=True, text=True, timeout=5
        )
        serial_number = result.stdout.strip()
    except Exception:
        pass

    return {
        "hostname": hostname,
        "os_name": os_name,
        "os_version": os_version,
        "ip_address": ip_address,
        "mac_address": mac_address,
        "serial_number": serial_number,
    }


def checkin(server, system_info, org_acronym=None, station_token=None):
    """
    Send check-in request to the server.

    On first run (no token): include organization_acronym in the payload.
    On subsequent runs: send the stored station_token.
    The server returns station_token in the response on first registration.
    """
    url = f"{server}/api/?action=checkin"
    payload = {
        "hostname": system_info["hostname"],
        "os_name": system_info["os_name"],
        "os_version": system_info["os_version"],
        "ip_address": system_info["ip_address"],
        "mac_address": system_info["mac_address"],
        "serial_number": system_info["serial_number"],
    }

    # Include org acronym for first registration
    if org_acronym:
        payload["organization_acronym"] = org_acronym.upper()

    # Include stored token for subsequent check-ins (also used server-side for lookup)
    if station_token:
        payload["station_token"] = station_token

    data = json.dumps(payload).encode("utf-8")
    headers = {"Content-Type": "application/json"}

    # Bearer token header for subsequent check-ins
    if station_token:
        headers["Authorization"] = f"Bearer {station_token}"

    req = Request(url, data=data, headers=headers, method="POST")

    try:
        with urlopen(req, timeout=CHECKIN_TIMEOUT) as response:
            body = response.read().decode("utf-8")
            return json.loads(body)
    except HTTPError as e:
        log(f"Check-in HTTP error: {e.code} {e.reason}", "ERROR")
        try:
            error_body = e.read().decode("utf-8")
            parsed = json.loads(error_body)
            log(f"Server message: {parsed.get('error', error_body)}", "ERROR")
        except Exception:
            pass
        return None
    except URLError as e:
        log(f"Check-in network error: {e.reason}", "WARNING")
        return None
    except Exception as e:
        log(f"Check-in error: {e}", "ERROR")
        return None


def download_bundle(server, station_token, bundle_id):
    """Download a bundle from the server."""
    url = f"{server}/api/?action=bundle-by-id&id={bundle_id}"
    headers = {}
    if station_token:
        headers["Authorization"] = f"Bearer {station_token}"

    req = Request(url, headers=headers, method="GET")

    try:
        with urlopen(req, timeout=DOWNLOAD_TIMEOUT) as response:
            return response.read()
    except HTTPError as e:
        log(f"Download HTTP error: {e.code} {e.reason}", "ERROR")
        return None
    except URLError as e:
        log(f"Download network error: {e.reason}", "ERROR")
        return None
    except Exception as e:
        log(f"Download error: {e}", "ERROR")
        return None


def execute_bundle(bundle_path):
    """Execute the downloaded bundle with bash."""
    try:
        os.chmod(bundle_path, 0o755)
        log(f"Executing bundle: {bundle_path}", "INFO")
        result = subprocess.run(
            ["bash", bundle_path],
            capture_output=True,
            text=True,
            timeout=1800,
        )
        if result.returncode == 0:
            log("Bundle executed successfully", "INFO")
            if result.stdout:
                log(f"Bundle output: {result.stdout[:500]}", "INFO")
        else:
            log(f"Bundle execution failed (exit code {result.returncode})", "ERROR")
            if result.stderr:
                log(f"Bundle stderr: {result.stderr[:500]}", "ERROR")
        return result.returncode == 0
    except subprocess.TimeoutExpired:
        log("Bundle execution timed out (30 min)", "ERROR")
        return False
    except Exception as e:
        log(f"Bundle execution error: {e}", "ERROR")
        return False


def main():
    args = parse_args()
    dry_run = args.dry_run
    verbose = args.verbose

    log("=" * 60)
    log("SeederLinux Lite Agent 1.1.0 starting")

    config = load_config(args)
    server = config["server"]
    log(f"Server: {server}")

    # Load existing token
    station_token = load_token()
    is_first_run = station_token is None

    if is_first_run:
        if not args.org:
            log(
                "ERROR: No station token found and --org not provided.\n"
                "  This appears to be the first run. Use --org to bind this station:\n"
                "    sudo python3 agent.py --org <ACRONYM>\n"
                "  Example: sudo python3 agent.py --org COMARA",
                "ERROR"
            )
            return 1
        log(f"First run — will register with organization: {args.org.upper()}")
    else:
        if verbose:
            log(f"Token found: {station_token[:8]}...", "DEBUG")
        if args.org:
            log(f"Note: --org ignored (station already registered, token found)", "INFO")

    # Collect system info
    system_info = collect_system_info()
    log(f"Hostname: {system_info['hostname']}")
    log(f"IP: {system_info['ip_address']}, OS: {system_info['os_name']} {system_info['os_version']}")

    if dry_run:
        log("Dry run mode — skipping check-in and bundle execution")
        if verbose:
            log(f"Would send: {json.dumps(system_info, indent=2)}", "DEBUG")
        return 0

    # Check-in
    log("Sending check-in...")
    response = checkin(
        server,
        system_info,
        org_acronym=args.org if is_first_run else None,
        station_token=station_token,
    )

    if response is None:
        log("Check-in failed — network may be unavailable. Exiting.", "WARNING")
        return 0

    if not response.get("success"):
        log(f"Check-in failed: {response.get('error', 'Unknown error')}", "ERROR")
        return 1

    data = response.get("data", {})
    log(f"Check-in successful. Station ID: {data.get('station_id', 'N/A')}")

    # Save token if server returned one (first registration)
    returned_token = data.get("station_token")
    if returned_token:
        save_token(returned_token)
        station_token = returned_token
        log("Station registered and token saved.")

    # Check if update is available
    update_available = data.get("update_available", False)
    bundle_id = data.get("latest_bundle_id")

    if not update_available:
        log("No updates available. System is up to date.")
        return 0

    if not bundle_id:
        log("Update flagged but no bundle ID returned. Skipping.", "WARNING")
        return 0

    log(f"Update available! Downloading bundle ID: {bundle_id}")

    bundle_content = download_bundle(server, station_token, bundle_id)
    if bundle_content is None:
        log("Failed to download bundle", "ERROR")
        return 1

    try:
        os.makedirs(BUNDLE_CACHE_DIR, exist_ok=True)
        with open(BUNDLE_FILE, "wb") as f:
            f.write(bundle_content)
        log(f"Bundle saved to {BUNDLE_FILE} ({len(bundle_content)} bytes)")
    except (IOError, PermissionError) as e:
        log(f"Failed to save bundle: {e}", "ERROR")
        return 1

    success = execute_bundle(BUNDLE_FILE)

    if success:
        log("Provisioning completed successfully")
        return 0
    else:
        log("Provisioning completed with errors", "ERROR")
        return 1


if __name__ == "__main__":
    try:
        exit_code = main()
    except KeyboardInterrupt:
        log("Agent interrupted by user", "WARNING")
        exit_code = 0
    except Exception as e:
        log(f"Unexpected error: {e}", "ERROR")
        exit_code = 1

    sys.exit(exit_code)
