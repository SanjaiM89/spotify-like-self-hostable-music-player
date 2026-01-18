import asyncio
import os
import time
import mimetypes
from typing import AsyncGenerator, Dict, Any, Optional

# 1. OPTIMIZATION: Install uvloop for faster async handling
try:
    import uvloop
    asyncio.set_event_loop_policy(uvloop.EventLoopPolicy())
except ImportError:
    pass

from telethon import TelegramClient, events, utils, errors
from telethon.tl.types import DocumentAttributeFilename, InputPeerChannel
from dotenv import load_dotenv

# Load env
load_dotenv("../config.env")
load_dotenv("config.env")

API_ID = os.getenv("API_ID")
API_HASH = os.getenv("API_HASH")
BOT_TOKEN = os.getenv("BOT_TOKEN")
BIN_CHANNEL = int(os.getenv("BIN_CHANNEL", "0"))

print(f"DEBUG: API_ID={API_ID} BIN_CHANNEL={BIN_CHANNEL}")

class FileNotFound(Exception):
    pass

class TelegramClientWrapper:
    def __init__(self):
        if not all([API_ID, API_HASH, BOT_TOKEN, BIN_CHANNEL]):
            raise ValueError("Missing Telegram Config")
        
        self.session_name = "TelethonBot"
        
        # 2. OPTIMIZATION: Connection retries and timeout settings
        self.client = TelegramClient(
            self.session_name,
            int(API_ID),
            API_HASH,
            connection_retries=5,
            retry_delay=1
        )
        self.bin_channel = BIN_CHANNEL
        self._bin_entity = None

    async def start(self):
        print("Starting Telegram Client (Telethon)...")
        await self.client.start(bot_token=BOT_TOKEN)
        
        # FIXED: Safe check for cryptg without accessing internal client attributes
        try:
            import cryptg
            print("🚀 Fast Crypto (cryptg) is detected and active.")
        except ImportError:
            print("⚠️ PERFORMANCE WARNING: 'cryptg' is not installed! Streaming will be slow.")
            print("👉 Run: pip install cryptg")

        me = await self.client.get_me()
        print(f"Bot info: {me.first_name} (@{me.username})")
        
        # Resolve channel entity once at startup
        await self._resolve_bin_channel()

    async def stop(self):
        await self.client.disconnect()

    async def _resolve_bin_channel(self):
        """Resolves and caches the BIN_CHANNEL entity for faster access."""
        try:
            # Try caching via simple ID first
            self._bin_entity = await self.client.get_input_entity(self.bin_channel)
            print(f"✅  Resolved BIN_CHANNEL: {self.bin_channel}")
        except Exception as e:
            print(f"❌  Could not resolve BIN_CHANNEL: {e}")
            print("   Uploads might fail if the bot hasn't seen the channel yet.")

    def _sanitize_filename(self, filename: str) -> str:
        import re
        filename = filename.replace('｜', '-').replace('|', '-')
        filename = re.sub(r'[<>:"/\\?*]', '', filename)
        if len(filename) > 200:
            name, ext = os.path.splitext(filename)
            filename = name[:195] + ext
        return filename

    async def upload_file(self, file_path: str, progress_callback=None) -> Optional[Any]:
        if not os.path.exists(file_path):
            return None

        clean_name = self._sanitize_filename(os.path.basename(file_path))
        start_time = time.time()
        
        async def _progress(current, total):
            if progress_callback:
                now = time.time()
                elapsed = now - start_time
                speed = current / elapsed if elapsed > 0 else 0
                progress_callback(current, total, speed)

        try:
            print(f"[TG] Uploading {clean_name}...")
            
            attributes = []
            if clean_name != os.path.basename(file_path):
                attributes.append(DocumentAttributeFilename(file_name=clean_name))
            
            # Telethon handles parallel upload automatically for large files
            msg = await self.client.send_file(
                self.bin_channel,
                file_path,
                caption=f"Uploaded via mPlay: {clean_name}",
                progress_callback=_progress if progress_callback else None,
                attributes=attributes,
                force_document=False,
                supports_streaming=True  # Important for video seeking
            )
            print(f"[TG] Upload complete! Msg ID: {msg.id}")
            return msg
        except Exception as e:
            print(f"[TG] Upload failed: {e}")
            return None

    async def get_file_info(self, message_id: int) -> Dict[str, Any]:
        try:
            message = await self.client.get_messages(self.bin_channel, ids=message_id)
            if not message or not message.media:
                raise FileNotFound("No media found")
            
            return {
                "file_name": message.file.name or f"file_{message_id}",
                "mime_type": message.file.mime_type or "application/octet-stream",
                "file_size": message.file.size
            }
        except Exception as e:
            print(f"Error get_file_info: {e}")
            raise FileNotFound(f"Message {message_id} not found")

    async def stream_file(self, message_id: int, offset: int = 0, limit: int = 0) -> AsyncGenerator[bytes, None]:
        """
        Hybrid Streamer (The "IDM" approach):
        1. Fast Start: Downloads first 1MB sequentially for instant play.
        2. Parallel Sliding Window: Downloads next 3 chunks simultaneously.
        """
        try:
            message = await self.client.get_messages(self.bin_channel, ids=message_id)
            if not message or not message.media:
                raise FileNotFound(f"Message {message_id} not found")

            file_size = message.file.size
            if limit <= 0:
                limit = file_size - offset

            remaining_bytes = limit
            current_offset = offset
            
            # --- PHASE 1: FAST START (Instant Play) ---
            # Download first 1MB sequentially. 
            # This ensures the player gets headers immediately and doesn't timeout.
            
            fast_start_size = 1024 * 1024 # 1 MB
            
            if remaining_bytes > 0:
                req = min(fast_start_size, remaining_bytes)
                print(f"[STREAM] 🚀 Hybrid: Fast starting first {req/1024:.0f}KB...")
                
                async for chunk in self.client.iter_download(
                    message.media,
                    offset=current_offset,
                    limit=req,
                    chunk_size=req,
                    request_size=512*1024
                ):
                    yield chunk
                    remaining_bytes -= len(chunk)
                    current_offset += len(chunk)

            if remaining_bytes <= 0:
                return

            # --- PHASE 2: PARALLEL SLIDING WINDOW ---
            # Now we launch 3 parallel workers for the rest of the file.
            
            worker_count = 3          # 3 Simultaneous downloads
            chunk_size = 1024 * 1024  # 1 MB per worker
            
            tasks = [] # Keeps our active downloads in order [Task A, Task B, Task C]

            # Helper to create a background download task
            async def download_part(start, size):
                # We use a distinct client iterator for every task to ensure isolation
                data = b""
                async for part in self.client.iter_download(
                    message.media,
                    offset=start,
                    limit=size,
                    chunk_size=size, 
                    request_size=512*1024
                ):
                    data += part
                return data

            # Initial Fill: Launch first 3 workers
            for _ in range(worker_count):
                if remaining_bytes <= 0:
                    break
                req = min(chunk_size, remaining_bytes)
                
                # Create task (don't await yet!)
                t = asyncio.create_task(download_part(current_offset, req))
                tasks.append(t)
                
                current_offset += req
                remaining_bytes -= req

            # Consume Loop
            while tasks:
                # 1. Get the next task in the queue (Strict Order)
                next_task = tasks.pop(0)
                
                # 2. Wait for it to finish (It was likely downloading while we yielded previous data)
                chunk_data = await next_task
                
                # 3. Yield to player
                yield chunk_data
                
                # 4. Refill: Start a new worker at the end of the line
                if remaining_bytes > 0:
                    req = min(chunk_size, remaining_bytes)
                    
                    new_t = asyncio.create_task(download_part(current_offset, req))
                    tasks.append(new_t)
                    
                    current_offset += req
                    remaining_bytes -= req
                    
                    print(f"[STREAM] ⚡ Parallel: Yielded 1MB | Active Workers: {len(tasks)+1}")

        except GeneratorExit:
            # Clean up tasks if user disconnects
            for t in tasks: t.cancel()
            print("[STREAM] User disconnected, tasks cancelled.")
            raise
        except Exception as e:
            print(f"[STREAM ERROR] {e}")
            for t in tasks: t.cancel()
            raise

tg_client = TelegramClientWrapper()