#!/usr/bin/env python3
"""
Smart uvicorn launcher that restarts when PORT changes in config.env
"""
import os
import sys
import time
import subprocess
import signal
from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler
from dotenv import load_dotenv, dotenv_values

class ConfigWatcher(FileSystemEventHandler):
    def __init__(self, callback):
        self.callback = callback
        self.last_port = None
        
    def on_modified(self, event):
        if event.src_path.endswith('config.env'):
            # Read new port
            env_values = dotenv_values("config.env")
            new_port = env_values.get("PORT")
            
            if new_port and new_port != self.last_port:
                print(f"🔄 PORT changed: {self.last_port} -> {new_port}")
                self.last_port = new_port
                self.callback(new_port)

class UvicornManager:
    def __init__(self):
        self.process = None
        self.should_restart = False
        
    def get_current_port(self):
        """Read PORT from config.env"""
        env_values = dotenv_values("config.env")
        return int(env_values.get("PORT", 8000))
    
    def start(self, port=None):
        """Start uvicorn server"""
        if port is None:
            port = self.get_current_port()
        
        print(f"🚀 Starting backend on port {port}...")
        
        self.process = subprocess.Popen([
            sys.executable, "-m", "uvicorn",
            "main:app",
            "--host", "0.0.0.0",
            "--port", str(port),
            "--reload",
            "--reload-include", "*.py",
            "--reload-include", "*.env"
        ])
        
        return port
    
    def stop(self):
        """Stop uvicorn server"""
        if self.process:
            print("🛑 Stopping backend...")
            self.process.send_signal(signal.SIGTERM)
            try:
                self.process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.process.kill()
            self.process = None
    
    def restart(self, new_port):
        """Restart server with new port"""
        self.stop()
        time.sleep(2)
        self.start(new_port)
    
    def on_port_change(self, new_port):
        """Callback when port changes"""
        self.restart(int(new_port))

def main():
    manager = UvicornManager()
    
    # Start initial server
    initial_port = manager.start()
    
    # Watch for config changes
    watcher = ConfigWatcher(manager.on_port_change)
    watcher.last_port = str(initial_port)
    
    observer = Observer()
    observer.schedule(watcher, path=".", recursive=False)
    observer.start()
    
    print("👀 Watching for PORT changes in config.env...")
    print("Press Ctrl+C to stop")
    
    try:
        manager.process.wait()
    except KeyboardInterrupt:
        print("\n⚠️  Shutting down...")
        observer.stop()
        manager.stop()
    
    observer.join()

if __name__ == "__main__":
    main()
