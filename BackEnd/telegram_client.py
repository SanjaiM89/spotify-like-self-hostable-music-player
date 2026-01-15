import asyncio
import os
import mimetypes
from typing import AsyncGenerator, Dict, Any, Optional
from pyrogram import Client
from pyrogram.errors import FloodWait
from pyrogram.types import Message
from dotenv import load_dotenv

# Load env from root or current dir
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
            raise ValueError("Missing Telegram Config (API_ID, API_HASH, BOT_TOKEN, BIN_CHANNEL)")
        
        # Use in_memory session to avoid auth conflicts on container restarts
        self.app = Client(
            name="SpotifyCloneBot",
            api_id=int(API_ID),
            api_hash=API_HASH,
            bot_token=BOT_TOKEN,
            in_memory=True, # Critical for Render deployment
        )
        self.bin_channel = BIN_CHANNEL
        self._main_loop = None  # Store reference to main event loop

    async def start(self):
        import asyncio
        self._main_loop = asyncio.get_running_loop()
        await self.app.start()
        print("Telegram Client Started")
        # Try to resolve and cache the bin_channel peer on startup
        await self._resolve_bin_channel()

    async def _resolve_bin_channel(self):
        """Attempt to resolve the bin channel peer on startup."""
        chat_id = self.bin_channel
        
        # 1. Try direct get_chat first
        try:
            chat = await self.app.get_chat(chat_id)
            print(f"Resolved BIN_CHANNEL: {chat.title or chat.id}")
            return
        except Exception as e:
            print(f"Direct resolution failed for {chat_id}: {e}")

        # 2. Try get_chat_member to force resolution (Works for Bots)
        print("Attempting to resolve via get_chat_member...")
        try:
            # Getting 'me' (the bot itself) as a member often forces the peer to be cached
            me = await self.app.get_me()
            headers = await self.app.get_chat_member(chat_id, me.id)
            print(f"Found BIN_CHANNEL via member check: {headers.chat.title}")
            return
        except Exception as e:
             print(f"Error checking chat member: {e}")

        # 3. Try fallback with -100 prefix if not already present
        if str(chat_id).startswith("-") and not str(chat_id).startswith("-100"):
            new_id = int(f"-100{abs(chat_id)}")
            try:
                chat = await self.app.get_chat(new_id)
                print(f"Resolved BIN_CHANNEL with -100 prefix: {chat.title or chat.id}")
                self.bin_channel = new_id
                return
            except Exception:
                pass
        
        print("WARNING: Could not resolve BIN_CHANNEL. Uploads may fail.")
        print("IMPORTANT: Make sure the bot is added as an admin to the channel!")

    async def stop(self):
        try:
            if self.app.is_connected:
                await self.app.stop()
                print("Telegram Client Stopped")
        except Exception as e:
            print(f"Error stopping Telegram Client: {e}")
            # If standard stop fails implies loop issue, force close session
            try:
                 if hasattr(self.app, 'session'):
                    await self.app.session.close()
            except:
                pass

    def _sanitize_filename(self, filename: str) -> str:
        """Remove problematic characters from filename"""
        import re
        # Replace problematic Unicode characters
        filename = filename.replace('｜', '-').replace('|', '-')
        # Remove other potentially problematic characters
        filename = re.sub(r'[<>:"/\\?*]', '', filename)
        # Limit length
        if len(filename) > 200:
            name, ext = os.path.splitext(filename)
            filename = name[:195] + ext
        return filename

    async def upload_file(self, file_path: str, progress_callback=None) -> Optional[Message]:
        """Uploads a file to the bin channel with optional progress tracking."""
        import shutil
        import time
        import asyncio
        
        # DEBUG: Check event loops
        current_loop = asyncio.get_running_loop()
        client_loop = getattr(self.app, "loop", None)
        print(f"[TG DEBUG] Current Loop: {id(current_loop)}")
        print(f"[TG DEBUG] Client Loop: {id(client_loop)}")
        
        # PATCH: If loops mismatch, update client loop to current loop
        if client_loop and client_loop != current_loop:
            print(f"[TG DEBUG] Loops mismatch! Patching client loop...")
            self.app.loop = current_loop
            # Also need to update the internal session loop if it exists
            if hasattr(self.app, "session") and hasattr(self.app.session, "loop"):
                 self.app.session.loop = current_loop

        # Check if file exists
        if not os.path.exists(file_path):
            print(f"[TG] File not found: {file_path}")
            return None
        
        # Sanitize filename - copy to temp with clean name if needed
        original_name = os.path.basename(file_path)
        clean_name = self._sanitize_filename(original_name)
        
        upload_path = file_path
        temp_copy = None
        
        if clean_name != original_name:
            print(f"[TG] Sanitizing filename: {original_name} -> {clean_name}")
            temp_copy = os.path.join(os.path.dirname(file_path), clean_name)
            try:
                shutil.copy2(file_path, temp_copy)
                upload_path = temp_copy
            except Exception as e:
                print(f"[TG] Could not copy file: {e}")
                upload_path = file_path
        
        file_size = os.path.getsize(upload_path)
        start_time = time.time()
        
        def _progress(current, total):
            if progress_callback:
                elapsed = time.time() - start_time
                speed = current / elapsed if elapsed > 0 else 0
                progress_callback(current, total, speed)
        
        try:
            print(f"[TG] Starting upload: {upload_path} ({file_size} bytes)")
            msg = await self.app.send_document(
                chat_id=self.bin_channel,
                document=upload_path,
                caption=f"Uploaded via mPlay: {clean_name}",
                progress=_progress
            )
            print(f"[TG] Upload complete! Message ID: {msg.id}")
            return msg
        except Exception as e:
            print(f"[TG] Upload failed: {e}")
            import traceback
            traceback.print_exc()
            return None
        finally:
            # Cleanup temp copy
            if temp_copy and os.path.exists(temp_copy):
                try:
                    os.remove(temp_copy)
                except:
                    pass

    # --- Streaming Logic (Adapted from Thunder) ---

    async def get_message(self, message_id: int) -> Message:
        while True:
            try:
                message = await self.app.get_messages(self.bin_channel, message_id)
                if not message or message.empty:
                     raise FileNotFound(f"Message {message_id} not found or empty")
                return message
            except FloodWait as e:
                print(f"FloodWait in get_message: {e.value}s")
                await asyncio.sleep(e.value)
            except Exception as e:
                print(f"Error getting message {message_id}: {e}")
                raise FileNotFound(f"Message {message_id} not found") from e

    async def stream_file(self, message_id: int, offset: int = 0, limit: int = 0) -> AsyncGenerator[bytes, None]:
        message = await self.get_message(message_id)
        
        # Determine total size to calculate default limit if needed
        media = getattr(message, 'document', None) or getattr(message, 'audio', None) or getattr(message, 'video', None)
        file_size = getattr(media, 'file_size', 0)
        
        if limit <= 0:
            limit = max(0, file_size - offset)
            
        remaining_bytes = limit
        if remaining_bytes == 0:
            return

        # Assumption: Pyrogram uses 1MB chunks for stream_media offsets.
        # This is generally true for standard MTProto file handling in Pyrogram.
        chunk_size = 1024 * 1024 
        
        start_chunk_index = offset // chunk_size
        bytes_to_skip = offset % chunk_size
        
        # Request enough chunks to cover the byte range
        # (limit + skip) / chunk_size rounded up
        chunks_needed = ((limit + bytes_to_skip) + chunk_size - 1) // chunk_size
        
        # Add buffer to chunks request just in case
        async for chunk in self.app.stream_media(message, offset=start_chunk_index, limit=chunks_needed + 1):
            if remaining_bytes <= 0:
                break
                
            # Handle start trimming
            if bytes_to_skip > 0:
                if len(chunk) > bytes_to_skip:
                    chunk = chunk[bytes_to_skip:]
                    bytes_to_skip = 0
                else:
                    # Chunk is entirely within the skip region
                    bytes_to_skip -= len(chunk)
                    continue
            
            # Handle end trimming
            if len(chunk) > remaining_bytes:
                chunk = chunk[:remaining_bytes]
            
            if chunk:
                yield chunk
                remaining_bytes -= len(chunk)

    async def get_file_info(self, message_id: int) -> Dict[str, Any]:
        """Returns size, name, mime for a given message ID."""
        message = await self.get_message(message_id)
        
        media = getattr(message, 'document', None) or getattr(message, 'audio', None) or getattr(message, 'video', None)
        if not media:
             return {"error": "No media found in message"}

        file_name = getattr(media, 'file_name', f"file_{message_id}")
        mime_type = getattr(media, 'mime_type', 'application/octet-stream')
        file_size = getattr(media, 'file_size', 0)
        
        return {
            "file_name": file_name,
            "mime_type": mime_type,
            "file_size": file_size
        }

tg_client = TelegramClientWrapper()
