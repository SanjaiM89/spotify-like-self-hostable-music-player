import os
import time
import requests
import subprocess
import pymongo
from dotenv import load_dotenv

# Load env variables
load_dotenv("config.env")

# Config
BOT_TOKEN = os.getenv("BOT_TOKEN")
# Chat ID can be BIN_CHANNEL or a specific group. User said "telegram group where the bot resides".
# We'll use BIN_CHANNEL if it's a chat ID (integer), or ask user to set NOTIFY_CHAT_ID
CHAT_ID = os.getenv("NOTIFY_CHAT_ID", os.getenv("BIN_CHANNEL")) 
MONGO_URL = os.getenv("DATABASE_URL", "mongodb://localhost:27017")
DB_NAME = os.getenv("DATABASE_NAME", "FileToLink") 
DUCKDNS_DOMAIN = os.getenv("DUCKDNS_DOMAIN")
DUCKDNS_TOKEN = os.getenv("DUCKDNS_TOKEN")

def get_public_ip():
    try:
        return requests.get("https://api.ipify.org").text
    except:
        return None

def get_vpn_port():
    """
    Attempts to get the forwarded port from ProtonVPN.
    Priority:
    1. ProtonVPN forwarded_port file (Official Linux App) - DYNAMIC
    2. VPN_PORT environment variable (manual override)
    3. CLI commands (legacy fallback)
    Note: PORT env var is ignored as it's often set in config.env statically
    """
    # 1. Read from ProtonVPN forwarded_port file (Official Linux App)
    # The file is at /run/user/$UID/Proton/VPN/forwarded_port
    uid = os.getuid()
    port_file = f"/run/user/{uid}/Proton/VPN/forwarded_port"
    try:
        if os.path.exists(port_file):
            with open(port_file, 'r') as f:
                port = f.read().strip()
                if port and port.isdigit():
                    print(f"Found Port in ProtonVPN file ({port_file}): {port}")
                    return port
        else:
             print(f"ProtonVPN port file not found at: {port_file}")
    except Exception as e:
        print(f"Error reading port file: {e}")

    # 2. Check VPN_PORT Env Var (Manual Override - NOT 'PORT' which is in config.env)
    env_port = os.getenv("VPN_PORT")
    if env_port:
        print(f"Using Port from VPN_PORT env: {env_port}")
        return env_port

    # 3. Try CLI commands (Legacy fallback)
    cli_commands = ["protonvpn-cli", "protonvpn"]
    
    for cmd in cli_commands:
        try:
            # Check if command exists first
            import shutil
            if not shutil.which(cmd):
                continue
                
            print(f"Trying auto-detection with '{cmd}'...")
            try:
                # Try getting status/pmp info
                # Older CLI uses 'ks --pmp', new might use 's' or just show it in status
                result = subprocess.check_output([cmd, "ks", "--pmp"], encoding="utf-8", stderr=subprocess.DEVNULL)
                import re
                match = re.search(r"Port[:\s]+(\d+)", result, re.IGNORECASE)
                if match:
                    print(f"Found port using '{cmd} ks --pmp': {match.group(1)}")
                    return match.group(1)
            except subprocess.CalledProcessError:
                # Try alternatives for different versions
                try:
                    # Some versions show it in 'status'
                    result = subprocess.check_output([cmd, "s"], encoding="utf-8", stderr=subprocess.DEVNULL)
                    match = re.search(r"P2P[:\s]+Enabled.*Port[:\s]+(\d+)", result, re.IGNORECASE | re.DOTALL)
                    if not match: # Try simple port search
                        match = re.search(r"Port[:\s]+(\d+)", result, re.IGNORECASE)
                    
                    if match:
                        print(f"Found port using '{cmd} s': {match.group(1)}")
                        return match.group(1)
                except:
                    pass
            except FileNotFoundError:
                continue

        except Exception as e:
            print(f"Error checking {cmd}: {e}")
            
    print("Automatic port detection failed.")
    return None

def update_duckdns(ip):
    if not DUCKDNS_DOMAIN or not DUCKDNS_TOKEN:
        print("DuckDNS credentials missing.")
        return False
    
    # Extract subdomain from full URL if provided (e.g., "https://lazyio.duckdns.org" -> "lazyio")
    domain = DUCKDNS_DOMAIN
    if "duckdns.org" in domain:
        # Extract subdomain from URL or full domain
        import re
        match = re.search(r'(?:https?://)?([^.]+)\.duckdns\.org', domain)
        if match:
            domain = match.group(1)
    
    url = f"https://www.duckdns.org/update?domains={domain}&token={DUCKDNS_TOKEN}&ip={ip}"
    try:
        res = requests.get(url)
        if res.text == "OK":
            print(f"DuckDNS updated: {domain}.duckdns.org -> {ip}")
            return True
        else:
            print(f"DuckDNS update failed: {res.text}")
    except Exception as e:
        print(f"DuckDNS update error: {e}")
    return False

def save_to_db(ip, port):
    try:
        client = pymongo.MongoClient(MONGO_URL)
        db = client[DB_NAME]
        settings = db["settings"]
        
        settings.update_one(
            {"_id": "connection_info"},
            {"$set": {"ip": ip, "port": port, "updated_at": time.time()}},
            upsert=True
        )
        print(f"Saved connection info to MongoDB: {ip}:{port}")
    except Exception as e:
        print(f"MongoDB update failed: {e}")

def update_config_env(port):
    """Updates the PORT variable in config.env"""
    try:
        env_file = "config.env"
        if not os.path.exists(env_file):
            print("config.env not found!")
            return

        with open(env_file, 'r') as f:
            lines = f.readlines()
        
        new_lines = []
        port_updated = False
        
        current_port_infile = None
        for line in lines:
            if line.strip().startswith("PORT="):
                current_port_infile = line.strip().split("=")[1]
                new_lines.append(f"PORT={port}\n")
                port_updated = True
            else:
                new_lines.append(line)
        
        # STOP if port is already correct
        if current_port_infile == str(port):
             # print("Config.env port is already correct. Skipping write.")
             return

        if not port_updated:
            new_lines.append(f"PORT={port}\n")
            
        with open(env_file, 'w') as f:
            f.writelines(new_lines)
            
        print(f"Updated config.env with PORT={port}")
        
    except Exception as e:
        print(f"Error updating config.env: {e}")

def notify_telegram(ip, port):
    if not BOT_TOKEN or not CHAT_ID:
        print("Telegram credentials missing.")
        return

    message = (
        f"🚀 **Server Connection Updated**\n\n"
        f"🌐 **IP**: `{ip}` (DuckDNS Updated)\n"
        f"🔌 **Port**: `{port}`\n\n"
        f"Please update your App connection!"
    )
    
    url = f"https://api.telegram.org/bot{BOT_TOKEN}/sendMessage"
    payload = {
        "chat_id": CHAT_ID,
        "text": message,
        "parse_mode": "Markdown"
    }
    
    try:
        requests.post(url, json=payload)
        print("Telegram notification sent.")
    except Exception as e:
        print(f"Telegram notification failed: {e}")

import sys

def get_current_db_settings():
    try:
        client = pymongo.MongoClient(MONGO_URL)
        db = client[DB_NAME]
        settings = db["settings"]
        doc = settings.find_one({"_id": "connection_info"})
        return doc if doc else {}
    except Exception as e:
        print(f"Error reading DB: {e}")
        return {}

def main():
    print("Starting VPN Connection Manager...")
    
    # Check for non-interactive flag
    no_input = "--no-input" in sys.argv
    
    # 1. Check/Get Public IP
    current_ip = get_public_ip()
    if not current_ip:
        print("Could not get public IP.")
        return

    print(f"Current Public IP: {current_ip}")
    
    # 2. Get Port
    port = get_vpn_port()
    
    if not port:
        print("Could not automatically detect Port.")
        if not no_input:
            print("\n⚠️  LEGACY CLI DETECTED: Automatic port forwarding is not supported.")
            try:
                port = input("👉 Enter Port manually: ").strip()
            except (EOFError, KeyboardInterrupt):
                pass
        else:
            print("Running in --no-input mode. Skipping manual entry.")

    # 3. State Check & Update
    # Only update DuckDNS/Telegram if something CHANGED (or if forced?)
    saved_settings = get_current_db_settings()
    saved_ip = saved_settings.get("ip")
    saved_port = saved_settings.get("port")
    
    has_changes = False
    
    if current_ip != saved_ip:
        print(f"Detected IP Change: {saved_ip} -> {current_ip}")
        update_duckdns(current_ip)
        has_changes = True
    
    if port and port != saved_port:
        print(f"Detected Port Change: {saved_port} -> {port}")
        has_changes = True
        
    if has_changes:
        # If we have a port (or old port?), save. 
        # Be careful: if port is None (detection failed), do we keep old port?
        # Yes, preferably.
        final_port = port if port else saved_port
        
        # Save to DB
        save_to_db(current_ip, final_port)
        
        # Update config.env for Backend
        if final_port:
             update_config_env(final_port)
        
        # Notify
        notify_telegram(current_ip, final_port)
    else:
        print("No changes in IP/Port detected. Skipping updates.")
        # Emsure config.env is up to date even if no changes detected
        final_port = port if port else saved_port
        if final_port:
             update_config_env(final_port)

def rotate_vpn_location():
    """
    Rotate ProtonVPN to a different server location
    Returns: (success: bool, new_ip: str, new_port: int, server: str)
    """
    print("🔄 Starting VPN rotation...")
    
    try:
        # Get current IP before disconnection
        old_ip = get_public_ip()
        print(f"Current IP: {old_ip}")
        
        # List of preferred countries (residential IPs, good YouTube access)
        preferred_countries = ["US", "CA", "GB", "DE", "FR", "NL", "SE", "CH"]
        
        # Disconnect current VPN
        print("Disconnecting current VPN...")
        subprocess.run(["protonvpn-cli", "disconnect"], check=False, capture_output=True)
        time.sleep(3)
        
        # Try connecting to random country
        import random
        country = random.choice(preferred_countries)
        
        print(f"Connecting to ProtonVPN ({country})...")
        result = subprocess.run(
            ["protonvpn-cli", "connect", "--cc", country],
            capture_output=True,
            text=True,
            timeout=60
        )
        
        if result.returncode != 0:
            print(f"Connection failed: {result.stderr}")
            return (False, None, None, None)
        
        # Wait for connection to stabilize
        print("Waiting for connection to stabilize...")
        time.sleep(10)
        
        # Get new IP
        new_ip = get_public_ip()
        if not new_ip or new_ip == old_ip:
            print("IP did not change!")
            return (False, None, None, None)
        
        # Get new port (wait for port forwarding)
        max_wait = 30
        new_port = None
        for _ in range(max_wait):
            new_port = get_vpn_port()
            if new_port:
                break
            time.sleep(1)
        
        if not new_port:
            print("Warning: Could not detect port, but VPN connected")
        
        # Update DuckDNS and config
        print(f"New IP: {new_ip}, Port: {new_port}")
        update_duckdns(new_ip)
        if new_port:
            update_config_env(new_port)
            # Signal backend to restart (uvicorn will detect this)
            restart_signal = "restart_required.flag"
            with open(restart_signal, 'w') as f:
                f.write(f"{time.time()}\n{new_port}\n")
        save_to_db(new_ip, new_port)
        
        # Get server info
        server_info = subprocess.run(
            ["protonvpn-cli", "status"],
            capture_output=True,
            text=True
        )
        server = country
        if "Server:" in server_info.stdout:
            import re
            match = re.search(r'Server:\s+(.+)', server_info.stdout)
            if match:
                server = match.group(1).strip()
        
        print(f"✅ VPN rotation successful! New IP: {new_ip}, Server: {server}")
        return (True, new_ip, new_port, server)
        
    except subprocess.TimeoutExpired:
        print("❌ VPN connection timeout")
        return (False, None, None, None)
    except Exception as e:
        print(f"❌ VPN rotation failed: {e}")
        import traceback
        traceback.print_exc()
        return (False, None, None, None)

if __name__ == "__main__":
    main()
