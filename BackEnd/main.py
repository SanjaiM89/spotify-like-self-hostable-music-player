from fastapi import FastAPI, UploadFile, File, HTTPException, BackgroundTasks, Request, WebSocket, WebSocketDisconnect
from typing import List
from fastapi.responses import StreamingResponse, JSONResponse
from fastapi.middleware.cors import CORSMiddleware
from contextlib import asynccontextmanager
import os
from dotenv import load_dotenv

# Load config.env explicitly for standalone execution
if os.path.exists("config.env"):
    load_dotenv("config.env")

import shutil
import asyncio

# Local imports
from database import (
    db, init_db, add_song, get_all_songs, get_song_by_id, search_songs,
    delete_song, get_songs_paginated,
    create_playlist, get_playlists, get_playlist_by_id,
    add_song_to_playlist, remove_song_from_playlist, delete_playlist,
    record_play, get_recently_played,
    get_ai_cache, update_ai_cache,
    like_song, dislike_song, get_like_status, get_liked_songs, get_recommendations
)
# Removed Telegram Client: from telegram_client import tg_client, FileNotFound
from minio_client import minio_client # MinIO Integration
from metadata import extract_metadata
from mistral_agent import get_music_recommendations, get_homepage_recommendations

# Background task for hourly AI refresh
async def refresh_ai_recommendations():
    """Background task that refreshes AI recommendations every hour"""
    while True:
        try:
            print("[AI] Starting hourly recommendations refresh...")
            all_songs = await get_all_songs()
            if all_songs:
                # Fetch liked songs for personalization
                liked_songs = await get_liked_songs()
                result = await get_homepage_recommendations(all_songs, liked_songs)
                await update_ai_cache(
                    recommendations=result["recommendations"],
                    ai_playlist_name=result["ai_playlist"]["name"],
                    ai_playlist_songs=result["ai_playlist"]["song_ids"]
                )
                print(f"[AI] Cached: {len(result['recommendations'])} recs, playlist '{result['ai_playlist']['name']}'")
            else:
                print("[AI] No songs in library, skipping refresh")
        except Exception as e:
            print(f"[AI] Error refreshing recommendations: {e}")
        
        # Sleep for 1 hour
        await asyncio.sleep(3600)


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup
    await init_db()
    print(f"DEBUG: API_ID={os.getenv('API_ID')} BIN_CHANNEL={os.getenv('BIN_CHANNEL')}") # Assuming API_ID and BIN_CHANNEL are env vars
    
    # Initialize MinIO
    if minio_client.client:
        print("MinIO Client Ready")
    else:
        print("MinIO Client Failed to Initialize")
    
    # Telegram Client Removed
    # await tg_client.start()
        
    # Initialize default playlists
    # This function is not defined in the provided context, assuming it exists elsewhere or is a placeholder.
    # await init_default_playlists() 
    
    # Start background AI refresh task
    ai_task = asyncio.create_task(refresh_ai_recommendations())
    
    yield
    
    # Shutdown
    ai_task.cancel()
    # Telegram Client Removed
    # await tg_client.stop()
    print("Shutting down")

app = FastAPI(lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
    expose_headers=["Content-Range", "Accept-Ranges", "Content-Length", "Content-Type"],
)

TEMP_DIR = "temp_uploads"
os.makedirs(TEMP_DIR, exist_ok=True)

# --- WebSocket Manager ---
import json

class ConnectionManager:
    def __init__(self):
        self.active_connections: List[WebSocket] = []

    async def connect(self, websocket: WebSocket):
        await websocket.accept()
        self.active_connections.append(websocket)

    def disconnect(self, websocket: WebSocket):
        if websocket in self.active_connections:
            self.active_connections.remove(websocket)

    async def broadcast(self, message: str):
        for connection in self.active_connections:
            try:
                await connection.send_text(message)
            except:
                pass

    async def broadcast_json(self, data: dict):
        """Broadcast JSON data to all connected clients"""
        message = json.dumps(data)
        await self.broadcast(message)

manager = ConnectionManager()

@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    await manager.connect(websocket)
    try:
        while True:
            await websocket.receive_text()
    except WebSocketDisconnect:
        manager.disconnect(websocket)

# Helper to notify clients
async def notify_update(event_type: str = "song_added", data: dict = None):
    """Broadcast an event to all WebSocket clients"""
    payload = {"event": event_type}
    if data:
        payload["data"] = data
    await manager.broadcast_json(payload)

async def broadcast_task_update(task_id: str):
    """Broadcast a task update to all WebSocket clients"""
    # Assuming get_task is defined elsewhere
    # task = get_task(task_id)
    # if task:
    #     await notify_update("task_update", task.to_dict())
    pass # Placeholder as get_task is not defined here


# ==================== Connection Info API ====================
# Allows mobile app to fetch current server IP/Port from MongoDB

# Assuming 'db' is initialized elsewhere, e.g., from database.py
# from database import db # Example import if db is a direct mongo client

@app.get("/api/connection-info")
async def get_connection_info():
    """
    Get current server connection info (IP and Port) from MongoDB.
    This is updated by vpn_manager.py when VPN connects.
    """
    try:
        # Placeholder for db access, assuming 'db' is available
        # settings = db["settings"]
        # doc = settings.find_one({"_id": "connection_info"})
        doc = None # Simulate no doc for now
        if doc:
            return {
                "ip": doc.get("ip"),
                "port": doc.get("port"),
                "updated_at": doc.get("updated_at"),
                "domain": "lazyio.duckdns.org"  # DuckDNS domain
            }
        return {"ip": None, "port": None, "domain": "lazyio.duckdns.org"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

from pydantic import BaseModel as PortBaseModel

class PortUpdateRequest(PortBaseModel):
    port: str

@app.post("/api/connection-info/port")
async def update_port(request: PortUpdateRequest):
    """
    Manually update the port in MongoDB.
    Useful if user needs to set it from mobile app.
    """
    try:
        # Placeholder for db access, assuming 'db' is available
        # settings = db["settings"]
        # settings.update_one(
        #     {"_id": "connection_info"},
        #     {"$set": {"port": request.port}},
        #     upsert=True
        # )
        return {"success": True, "port": request.port}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/api/upload")
async def upload_files(files: list[UploadFile] = File(...)):
    """
    Uploads files to server temp, extracts metadata, uploads to MinIO,
    saves to DB, then cleans up.
    For video files: also extracts audio and uploads as separate stream.
    """
    from audio_extractor import extract_audio_from_video, cleanup_extracted_file
    
    VIDEO_EXTENSIONS = ['.mp4', '.mkv', '.webm', '.avi', '.mov']
    uploaded_songs = []
    
    for file in files:
        temp_path = os.path.join(TEMP_DIR, file.filename)
        with open(temp_path, "wb") as buffer:
            shutil.copyfileobj(file.file, buffer)
        
        # Check if it's a video file
        is_video = any(file.filename.lower().endswith(ext) for ext in VIDEO_EXTENSIONS)
        
        # Extract Metadata
        meta = await extract_metadata(temp_path)
        
        # Upload main file to MinIO (video or audio)
        minio_key_base = f"uploads/{os.path.basename(temp_path)}"
        minio_video_key = None
        minio_audio_key = None

        if minio_client.client:
            try:
                minio_client.client.fput_object(
                    "music-library", minio_key_base, temp_path,
                    content_type=file.content_type
                )
                print(f"[UPLOAD] Uploaded {file.filename} to MinIO as {minio_key_base}")
                if is_video:
                    minio_video_key = minio_key_base
                else:
                    minio_audio_key = minio_key_base
            except Exception as e:
                print(f"[UPLOAD] MinIO upload failed for {file.filename}: {e}")
                if os.path.exists(temp_path):
                    os.remove(temp_path)
                continue
        else:
            print("[UPLOAD] MinIO client not initialized, skipping upload.")
            if os.path.exists(temp_path):
                os.remove(temp_path)
            continue
            
        # For video files, also extract and upload audio
        if is_video:
            # Extract audio from video
            audio_path = await extract_audio_from_video(temp_path)
            if audio_path:
                audio_minio_key = f"uploads/{os.path.basename(audio_path)}"
                try:
                    minio_client.client.fput_object(
                        "music-library", audio_minio_key, audio_path,
                        content_type="audio/mpeg" # Assuming mp3 for extracted audio
                    )
                    minio_audio_key = audio_minio_key
                    print(f"[UPLOAD] Audio extracted and uploaded to MinIO: {audio_minio_key}")
                except Exception as e:
                    print(f"[UPLOAD] MinIO audio upload failed for {audio_path}: {e}")
                cleanup_extracted_file(audio_path)
        
        # Save to DB with MinIO keys
        song_id = await add_song(
            minio_audio_key=minio_audio_key,
            minio_video_key=minio_video_key,
            has_video=is_video,
            title=meta.get("title"),
            artist=meta.get("artist"),
            album=meta.get("album"),
            duration=meta.get("duration"),
            cover_art=meta.get("cover_art"),
            file_name=file.filename,
            file_size=os.path.getsize(temp_path)
        )
        
        uploaded_songs.append({"id": song_id, "title": meta.get("title")})
        
        # Cleanup
        if os.path.exists(temp_path):
            os.remove(temp_path)
        
    return {"status": "success", "uploaded": uploaded_songs}

@app.get("/api/songs")
async def list_songs():
    return await get_all_songs()

@app.get("/api/stream/{song_id}")
async def stream_song(song_id: str, request: Request, type: str = None):
    """
    Stream a song by ID.
    Optional query param:
      - type=audio: Force audio stream (uses audio_telegram_id)
      - type=video: Force video stream (uses video_telegram_id)
      - Default: Uses legacy telegram_file_id (audio for audio files, video for video files)
    """
    song = await get_song_by_id(song_id)
    if not song:
        raise HTTPException(status_code=404, detail="Song not found")
    
    # === 1. LOCAL CACHE CHECK (Fastest) ===
    local_path = None
    if type == "video":
        local_path = song.get("video_local_path")
    else:
        local_path = song.get("audio_local_path")
        
    if local_path and os.path.exists(local_path):
        from fastapi.responses import FileResponse
        return FileResponse(local_path, media_type="video/mp4" if type == "video" else "audio/mpeg", filename=os.path.basename(local_path))
    
    # === 2. MINIO CHECK (High Speed Network) ===
    minio_key = song.get("minio_video_key") if type == "video" else song.get("minio_audio_key")
    if minio_key and minio_client.client:
        try:
             # Proxy Stream from MinIO
             obj = minio_client.client.get_object("music-library", minio_key)
             
             def iter_minio():
                 for chunk in obj.stream(32*1024):
                     yield chunk
                 obj.close()
                 obj.release_conn()

             return StreamingResponse(
                 iter_minio(),
                 media_type="video/mp4" if type == "video" else "audio/mpeg"
             )
        except Exception as e:
             print(f"[Stream] MinIO Error: {e}")
             # Fallback to Telegram if MinIO fails
    
    # === 3. ERROR FALLBACK ===
    raise HTTPException(status_code=404, detail="Stream failed: Local file missing and MinIO unavailable")

@app.post("/api/recommend")
async def recommend(current_song_id: str, history_ids: list[str]):
    """
    Get recommendations based on current song and history.
    """
    current_song = await get_song_by_id(current_song_id)
    
    history = []
    for hid in history_ids:
        s = await get_song_by_id(hid)
        if s:
            history.append(s)
    
    if not current_song:
        return {"recommendations": []}
        
    recs = await get_music_recommendations(current_song, history)
    
    # In a real app, we would match these strings to songs in our DB or search Youtube/Spotify
    # For now, we return the strings or try to find matches in our DB
    
    db_matches = []
    for rec in recs:
        # Simple fuzzy search in our DB
        # Assuming rec format "Title - Artist"
        parts = rec.split("-")
        if len(parts) >= 1:
            query = parts[0].strip()
            matches = await search_songs(query)
            if matches:
                db_matches.extend(matches)
                
    # remove duplicates
    unique_matches = {v['id']:v for v in db_matches}.values()
    
    return {
        "mistral_suggestions": recs,
        "playable_matches": list(unique_matches)
    }


# ==================== Like/Dislike API ====================

@app.post("/api/songs/{song_id}/like")
async def api_like_song(song_id: str):
    """Like a song"""
    song = await get_song_by_id(song_id)
    if not song:
        raise HTTPException(status_code=404, detail="Song not found")
    await like_song(song_id)
    return {"status": "liked", "song_id": song_id}


@app.post("/api/songs/{song_id}/dislike")
async def api_dislike_song(song_id: str):
    """Dislike a song"""
    song = await get_song_by_id(song_id)
    if not song:
        raise HTTPException(status_code=404, detail="Song not found")
    await dislike_song(song_id)
    return {"status": "disliked", "song_id": song_id}


@app.get("/api/songs/{song_id}/like-status")
async def api_get_like_status(song_id: str):
    """Get like status for a song. Returns {liked: true/false/null}"""
    status = await get_like_status(song_id)
    return status


@app.get("/api/recommendations")
async def api_get_recommendations(limit: int = 10):
    """Get personalized recommendations based on likes/dislikes"""
    recs = await get_recommendations(limit)
    return {"recommendations": recs}


@app.get("/api/liked-songs")
async def api_get_liked_songs():
    """Get all liked songs"""
    songs = await get_liked_songs()
    return {"songs": songs}


@app.get("/api/upcoming-queue/{song_id}")
async def api_get_upcoming_queue(song_id: str):
    """
    Get LLM-generated upcoming queue based on current song and liked songs.
    Returns songs from library that match AI suggestions.
    """
    current_song = await get_song_by_id(song_id)
    if not current_song:
        raise HTTPException(status_code=404, detail="Song not found")
    
    # Get liked songs for context
    liked_songs = await get_liked_songs()
    all_songs = await get_all_songs()
    
    # Build history from liked songs or all songs
    history = liked_songs[:5] if liked_songs else all_songs[:5]
    
    # Get AI recommendations
    ai_suggestions = await get_music_recommendations(current_song, history)
    
    # Match suggestions to songs in library
    matches = []
    for suggestion in ai_suggestions:
        # Try to find matching song in library
        parts = suggestion.split(" - ")
        if len(parts) >= 1:
            query = parts[0].strip()
            found = await search_songs(query)
            # Filter out current song and add unique matches
            for s in found:
                if s["id"] != song_id and s["id"] not in [m["id"] for m in matches]:
                    matches.append(s)
                    break
    
    # If we don't have enough matches, fill with liked songs then random
    if len(matches) < 5:
        liked_ids = {m["id"] for m in matches}
        liked_ids.add(song_id)
        for s in liked_songs:
            if s["id"] not in liked_ids:
                matches.append(s)
                liked_ids.add(s["id"])
            if len(matches) >= 10:
                break
    
    return {
        "ai_suggestions": ai_suggestions,  # Raw LLM suggestions
        "queue": matches[:10]  # Matched songs from library
    }


# ==================== Persistent AI Queue API ====================
from database import (
    get_ai_queue, save_ai_queue, mark_song_played as db_mark_played,
    get_queue_songs, refill_queue_if_needed, clear_played_queue
)


@app.get("/api/ai-queue")
async def api_get_ai_queue():
    """Get current AI queue from MongoDB (persistent)"""
    # Ensure minimum 10 songs
    await refill_queue_if_needed(min_songs=10)
    
    queue_data = await get_ai_queue()
    songs = await get_queue_songs()
    
    return {
        "songs": songs,
        "played_count": len(queue_data["played_ids"]),
        "created_at": str(queue_data["created_at"]) if queue_data["created_at"] else None,
        "updated_at": str(queue_data["updated_at"]) if queue_data["updated_at"] else None,
    }


@app.post("/api/ai-queue/refresh")
async def api_refresh_ai_queue():
    """Regenerate AI queue using LLM and save to MongoDB"""
    # Get liked songs for personalization
    liked_songs = await get_liked_songs()
    all_songs = await get_all_songs()
    
    if not all_songs:
        return {"status": "error", "message": "No songs in library"}
    
    # Build history from liked songs
    history = liked_songs[:5] if liked_songs else all_songs[:5]
    import random
    sample_song = random.choice(liked_songs) if liked_songs else random.choice(all_songs)
    
    # Get AI suggestions
    ai_suggestions = await get_music_recommendations(sample_song, history)
    
    # Match to library songs
    matched_ids = []
    for suggestion in ai_suggestions:
        parts = suggestion.split(" - ")
        if parts:
            query = parts[0].strip()
            found = await search_songs(query)
            for s in found:
                if s["id"] not in matched_ids:
                    matched_ids.append(s["id"])
                    break
    
    # Add liked songs
    for s in liked_songs:
        if s["id"] not in matched_ids:
            matched_ids.append(s["id"])
        if len(matched_ids) >= 15:
            break
    
    # Fill remaining with random songs
    if len(matched_ids) < 10:
        random.shuffle(all_songs)
        for s in all_songs:
            if s["id"] not in matched_ids:
                matched_ids.append(s["id"])
            if len(matched_ids) >= 15:
                break
    
    # Clear played and save new queue
    await clear_played_queue()
    await save_ai_queue(matched_ids)
    
    # Get full song objects
    songs = await get_queue_songs()
    
    return {
        "status": "refreshed",
        "count": len(songs),
        "songs": songs,
        "ai_suggestions": ai_suggestions,
    }


@app.post("/api/ai-queue/mark-played/{song_id}")
async def api_mark_song_played(song_id: str):
    """Mark a song as played (removes from queue)"""
    await db_mark_played(song_id)
    await refill_queue_if_needed(min_songs=10)
    return {"status": "marked", "song_id": song_id}


from pydantic import BaseModel as PydanticBaseModel

class SignalRequest(PydanticBaseModel):
    signal_type: str  # "listen", "skip", "like", "dislike"
    duration_seconds: int = 0  # For listen signals


@app.post("/api/ai-queue/signal/{song_id}")
async def api_queue_signal(song_id: str, request: SignalRequest):
    """
    Report user behavior signal for smart queue updates.
    - listen: played > 60 seconds (positive signal)
    - skip: skipped before 60 seconds (negative signal)  
    - like/dislike: explicit preference
    """
    signal_type = request.signal_type
    duration = request.duration_seconds
    
    song = await get_song_by_id(song_id)
    if not song:
        return {"status": "error", "message": "Song not found"}
    
    if signal_type == "listen" and duration >= 60:
        # Positive signal: mark as played and potentially add similar
        await db_mark_played(song_id)
        # Could enhance: add similar songs to queue based on this
        
    elif signal_type == "skip":
        # Negative signal: just mark as played to remove from queue
        await db_mark_played(song_id)
        
    elif signal_type == "like":
        # Already handled by like API, but refill queue
        await like_song(song_id)
        
    elif signal_type == "dislike":
        # Remove from queue and don't suggest similar
        await dislike_song(song_id)
        await db_mark_played(song_id)
    
    # Ensure queue stays filled
    await refill_queue_if_needed(min_songs=10)
    
    return {"status": "processed", "signal": signal_type, "song_id": song_id}


# ==================== App Playlists API ====================
from database import (
    get_app_playlists, create_app_playlist, get_playlist_with_songs, init_default_playlists
)
from pydantic import BaseModel

@app.get("/api/app-playlists")
async def api_get_app_playlists():
    """Get all app playlists"""
    return await get_app_playlists()

@app.get("/api/app-playlists/{playlist_id}")
async def api_get_app_playlist(playlist_id: str):
    """Get specific playlist with full song details"""
    playlist = await get_playlist_with_songs(playlist_id)
    if not playlist:
        raise HTTPException(status_code=404, detail="Playlist not found")
    return playlist

class GeneratePlaylistRequest(BaseModel):
    name: str = "New Mix"

@app.post("/api/app-playlists/generate")
async def api_generate_app_playlist(request: GeneratePlaylistRequest):
    """Generate a new random playlist"""
    all_songs = await get_all_songs()
    if not all_songs:
        raise HTTPException(status_code=400, detail="No songs in library")
        
    import random
    count = min(15, len(all_songs))
    selected = random.sample(all_songs, count)
    
    # Try to make it somewhat thematic based on a random attribute
    # e.g. same artist, or just random
    
    song_ids = [s["id"] for s in selected]
    playlist_id = await create_app_playlist(
        name=request.name,
        song_ids=song_ids,
        description="Generated playlist"
    )
    
    return {"status": "created", "id": playlist_id, "count": len(song_ids)}


# ==================== YouTube Audio Download API ====================
from pydantic import BaseModel
from youtube_downloader import youtube_downloader, get_task, DownloadStatus
from database import (
    save_youtube_task, get_youtube_task, get_youtube_tasks,
    update_youtube_task, delete_youtube_task, clear_all_youtube_tasks
)


class YouTubeRequest(BaseModel):
    url: str
    quality: str = "320"


class YouTubePreviewRequest(BaseModel):
    url: str


async def sync_task_to_db(task_id: str):
    """Sync in-memory task state to MongoDB"""
    task = get_task(task_id)
    if task:
        await save_youtube_task({
            "task_id": task.task_id,
            "url": task.url,
            "status": task.status.value,
            "progress": task.progress,
            "title": task.title,
            "artist": task.artist,
            "thumbnail": task.thumbnail,
            "duration": task.duration,
            "file_size": task.file_size,
            "error": task.error,
            "quality": task.quality,
            "song_id": task.song_id,
        })


async def process_youtube_download(task_id: str, url: str, quality: str):
    """
    Background task for downloading YouTube content and uploading to Telegram.
    ALWAYS downloads AUDIO first (high priority), then VIDEO second.
    This ensures background playback is always ready.
    """
    print(f"[MAIN] Starting process_youtube_download for {task_id}")
    
    # Determine if user requested video specifically
    user_wants_video = quality == "best" or quality.endswith("p")
    
    # Helper for progress callbacks
    def on_progress(task):
        import asyncio
        try:
            loop = asyncio.get_running_loop()
            loop.create_task(broadcast_task_update(task.task_id))
        except RuntimeError:
            pass
    
    # Helper for upload progress
    def create_upload_callback(task, base_progress, progress_range):
        import time
        state = {"last_time": time.time(), "last_current": 0}
        
        def on_upload_progress(current, total, speed):
            now = time.time()
            dt = now - state["last_time"]
            
            if dt > 0.5 or current == total:
                if speed and speed > 0:
                    if speed > 1024 * 1024:
                        task.speed = f"{speed / (1024 * 1024):.2f} MiB/s"
                    else:
                        task.speed = f"{speed / 1024:.2f} KiB/s"
                    remaining = total - current
                    eta_seconds = remaining / speed
                    m, s = divmod(int(eta_seconds), 60)
                    h, m = divmod(m, 60)
                    task.eta = f"{h:02d}:{m:02d}:{s:02d}" if h > 0 else f"{m:02d}:{s:02d}"
                else:
                    task.speed = "0 B/s"
                    task.eta = "--:--"
                
                task.downloaded_bytes = current
                task.total_bytes = total
                
                if total > 0:
                    upload_pct = (current / total) * progress_range
                    task.progress = base_progress + upload_pct
                
                state["last_time"] = now
                state["last_current"] = current
                
                import asyncio
                try:
                    loop = asyncio.get_running_loop()
                    loop.create_task(broadcast_task_update(task.task_id))
                except RuntimeError:
                    pass
            
            if task_id in youtube_downloader._cancelled_tasks:
                raise ValueError("Download cancelled by user")
        
        return on_upload_progress
    
    try:
        # ============ STEP 1: DOWNLOAD AUDIO FIRST (Priority) ============
        print(f"[MAIN] Step 1: Downloading AUDIO for {task_id}")
        audio_task = await youtube_downloader.download_audio(url, "320", task_id, broadcast_callback=on_progress)
        
        if audio_task.status == DownloadStatus.FAILED or audio_task.status == DownloadStatus.CANCELLED:
            print(f"[MAIN] Audio download failed: {audio_task.error}")
            await sync_task_to_db(task_id)
            return
        
        # Upload audio to MinIO (Primary)
        minio_audio_key = None
        if minio_client.client and audio_task.file_path:
            try:
                minio_audio_key = f"audio/{task_id}.mp3"
                minio_client.upload_file(audio_task.file_path, minio_audio_key, "audio/mpeg")
                print(f"[MAIN] Audio uploaded to MinIO: {minio_audio_key}")
            except Exception as e:
                print(f"[MAIN] MinIO audio upload failed: {e}")
                minio_audio_key = None # Reset if upload fails
        
        # Upload audio to Telegram (Backup) - REMOVED
        # print(f"[MAIN] Uploading audio to Telegram: {audio_task.file_path}")
        # audio_msg = await tg_client.upload_file(audio_task.file_path, progress_callback=create_upload_callback(audio_task, 0, 40))
        
        if not minio_audio_key:
            youtube_downloader.mark_failed(task_id, "Failed to upload audio to MinIO")
            await sync_task_to_db(task_id)
            return
        
        audio_telegram_id = None # Legacy
        print(f"[MAIN] Audio uploaded! MinIO Key: {minio_audio_key}")
        
        # Get audio file info
        audio_file_size = os.path.getsize(audio_task.file_path) if os.path.exists(audio_task.file_path) else audio_task.file_size
        audio_file_name = os.path.basename(audio_task.file_path) if audio_task.file_path else f"{audio_task.title}.mp3"
        
        # Save audio to database first (user can start using it immediately)
        song_id = await add_song(
            telegram_file_id=audio_telegram_id,  # Legacy compatibility
            audio_telegram_id=audio_telegram_id,
            title=audio_task.title,
            artist=audio_task.artist,
            album="YouTube",
            duration=audio_task.duration,
            cover_art=audio_task.thumbnail,
            file_name=audio_file_name,
            file_size=audio_file_size,
            thumbnail=audio_task.thumbnail,
            has_video=False,  # Will update after video download
            audio_local_path=audio_task.file_path, # LOCAL CACHE
            minio_audio_key=minio_audio_key
        )
        
        # Mark audio complete, notify clients
        youtube_downloader.mark_completed(task_id, song_id, None)
        await sync_task_to_db(task_id)
        await notify_update("library_updated")
        
        # Cleanup audio temp file
        # DISABLED FOR LOCAL CACHE STRATEGY
        # if audio_task.file_path and os.path.exists(audio_task.file_path):
        #    try:
        #        os.remove(audio_task.file_path)
        #    except:
        #        pass
        
        # ============ STEP 2: DOWNLOAD VIDEO (Background) ============
        print(f"[MAIN] Step 2: Downloading VIDEO for {task_id}")
        video_task_id = f"{task_id}_video"
        
        try:
            # Use best quality or user-requested quality
            video_quality = quality if user_wants_video else "best"
            video_task = await youtube_downloader.download_video(url, video_quality, video_task_id, broadcast_callback=None)
            
            if video_task.status == DownloadStatus.FAILED or video_task.status == DownloadStatus.CANCELLED:
                print(f"[MAIN] Video download failed (non-critical): {video_task.error}")
                # Video failure is non-critical, audio is already saved
            else:
                # Upload video to MinIO (Primary)
                print(f"[MAIN] Uploading Video to MinIO")
                minio_video_key = f"video/{task_id}_video.mp4"
                minio_client.upload_file(video_task.file_path, minio_video_key, "video/mp4")

                # Upload video to Telegram (Backup) - REMOVED
                # print(f"[MAIN] Uploading video to Telegram: {video_task.file_path}")
                # video_msg = await tg_client.upload_file(video_task.file_path)
                
                # Proceed if upload success (MinIO)
                if minio_video_key:
                    video_telegram_id = None # Legacy
                    print(f"[MAIN] Video uploaded! MinIO Key: {minio_video_key}")
                    
                    # Update song with video ID
                    existing = await db["songs"].find_one({"id": song_id})
                    if existing:
                        update_doc = {}
                        
                        # Check for video
                        update_doc["has_video"] = True
                        update_doc["minio_video_key"] = minio_video_key
                        
                        if video_telegram_id:
                            update_doc["video_telegram_id"] = video_telegram_id
                        
                        if video_task.file_path:
                                 update_doc["video_local_path"] = video_task.file_path
                        
                        await db["songs"].update_one(
                            {"_id": existing["_id"]},
                            {"$set": update_doc}
                        )
                    await notify_update("library_updated")
                else:
                    print(f"[MAIN] Video upload failed (non-critical)")
                    
        except Exception as ve:
            print(f"[MAIN] Video processing error (non-critical): {ve}")
        finally:
            # Cleanup video temp file
            # DISABLED FOR LOCAL CACHE STRATEGY
            # youtube_downloader.cleanup_task(video_task_id)
            pass
        
    except Exception as e:
        import traceback
        traceback.print_exc()
        youtube_downloader.mark_failed(task_id, str(e))
        await sync_task_to_db(task_id)
    finally:
        youtube_downloader.cleanup_task(task_id)


@app.post("/api/youtube/preview")
async def youtube_preview(request: YouTubePreviewRequest):
    """
    Get video metadata preview before downloading.
    """
    if not youtube_downloader.is_youtube_url(request.url):
        raise HTTPException(status_code=400, detail="Invalid YouTube URL")
    
    try:
        info = await youtube_downloader.get_video_info(request.url)
        return {
            "status": "success",
            "data": info
        }
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))


@app.post("/api/youtube")
async def youtube_download(request: YouTubeRequest):
    """
    Start a YouTube audio download task.
    Returns task_id(s) for status polling.
    """
    if not youtube_downloader.is_youtube_url(request.url):
        raise HTTPException(status_code=400, detail="Invalid YouTube URL")
    
    # Validate quality
    # Validate quality
    valid_qualities = ["320", "256", "192", "128", "m4a", "best", "2160p", "1440p", "1080p", "720p", "480p", "360p"]
    quality = request.quality if request.quality in valid_qualities else "320"
    
    # Check for playlist or single video and extract info
    try:
        videos = await youtube_downloader.extract_playlist_info(request.url)
    except Exception as e:
        print(f"Error extracting info: {e}")
        raise HTTPException(status_code=400, detail=f"Failed to extract info: {str(e)}")
    
    if not videos:
        raise HTTPException(status_code=400, detail="No videos found at URL")

    import uuid
    from youtube_downloader import DownloadTask, _download_tasks

    created_tasks = []
    
    for video in videos:
        task_id = str(uuid.uuid4())
        
        task = DownloadTask(
            task_id=task_id,
            url=video['url'],
            quality=quality,
            status=DownloadStatus.PENDING,
            title=video.get('title', ''),
            song_id=video.get('id')
        )
        _download_tasks[task_id] = task
        
        # Save initial task to DB
        await sync_task_to_db(task_id)
        
        # Start background download using asyncio.create_task
        asyncio.create_task(process_youtube_download(task_id, video['url'], quality))
        
        created_tasks.append({
            "task_id": task_id, 
            "title": video.get('title', 'Unknown'),
            "status": "queued"
        })
    
    return {
        "status": "queued",
        "count": len(created_tasks),
        "tasks": created_tasks,
        "task_id": created_tasks[0]["task_id"] if created_tasks else None
    }
    



@app.get("/api/youtube/status/{task_id}")
async def youtube_status(task_id: str):
    """
    Get the status of a YouTube download task.
    Checks in-memory first, then falls back to MongoDB.
    """
    # Check in-memory first (for active downloads)
    task = get_task(task_id)
    if task:
        return task.to_dict()
    
    # Fall back to MongoDB (for persisted tasks)
    db_task = await get_youtube_task(task_id)
    if db_task:
        return db_task
    
    raise HTTPException(status_code=404, detail="Task not found")


@app.get("/api/youtube/tasks")
async def list_youtube_tasks(page: int = 1, limit: int = 10):
    """
    List all YouTube download tasks with pagination.
    """
    return await get_youtube_tasks(page=page, limit=limit)


@app.delete("/api/youtube/tasks")
async def clear_youtube_tasks():
    """
    Clear all YouTube download tasks from history.
    """
    deleted_count = await clear_all_youtube_tasks()
    return {
        "status": "success",
        "deleted_count": deleted_count,
        "message": f"Cleared {deleted_count} tasks"
    }


@app.delete("/api/youtube/tasks/{task_id}")
async def delete_single_task(task_id: str):
    """
    Delete a single YouTube task from history.
    """
    await delete_youtube_task(task_id)
    return {"status": "success", "message": "Task deleted"}


@app.post("/api/youtube/cancel/{task_id}")
async def youtube_cancel(task_id: str):
    """
    Cancel a running YouTube download.
    """
    task = get_task(task_id)
    if not task:
        # Check if in DB
        db_task = await get_youtube_task(task_id)
        if not db_task:
            raise HTTPException(status_code=404, detail="Task not found")
        return {"status": "already_finished", "message": "Task already finished"}
    
    if task.status in [DownloadStatus.COMPLETED, DownloadStatus.FAILED, DownloadStatus.CANCELLED]:
        return {"status": "already_finished", "message": "Task already finished"}
    
    success = youtube_downloader.cancel_download(task_id)
    return {
        "status": "cancelled" if success else "failed",
        "message": "Cancellation requested" if success else "Could not cancel"
    }


# ==================== Songs Management ====================

@app.get("/api/songs/paginated")
async def get_songs_page(page: int = 1, limit: int = 20):
    """Get paginated songs list"""
    return await get_songs_paginated(page=page, limit=limit)


@app.delete("/api/songs/{song_id}")
async def remove_song(song_id: str):
    """Delete a song from library"""
    success = await delete_song(song_id)
    if not success:
        raise HTTPException(status_code=404, detail="Song not found")
    return {"status": "success", "message": "Song deleted"}


@app.post("/api/songs/{song_id}/play")
async def mark_song_played(song_id: str):
    """Record that a song was played (for history)"""
    song = await get_song_by_id(song_id)
    if not song:
        raise HTTPException(status_code=404, detail="Song not found")
    await record_play(song_id)
    return {"status": "success"}


# ==================== Playlists ====================

class CreatePlaylistRequest(BaseModel):
    name: str
    songs: list = []


@app.get("/api/playlists")
async def list_playlists(page: int = 1, limit: int = 10):
    """Get paginated playlists"""
    return await get_playlists(page=page, limit=limit)


@app.post("/api/playlists/import-app-playlist/{playlist_id}")
async def import_app_playlist(playlist_id: str):
    """Import an App Playlist to User Library"""
    # Get App Playlist
    app_pl = await get_playlist_with_songs(playlist_id)
    if not app_pl:
        raise HTTPException(status_code=404, detail="App Playlist not found")
    
    # Create User Playlist
    name = app_pl.get("name", "Imported Playlist")
    song_ids = [s["id"] for s in app_pl.get("songs", [])]
    
    new_id = await create_playlist(name=name, songs=song_ids)
    
    # Notify clients
    await notify_update("library_updated")
    
    return {"status": "success", "id": new_id, "name": name}





@app.post("/api/playlists")
async def new_playlist(request: CreatePlaylistRequest):
    """Create a new playlist"""
    playlist_id = await create_playlist(name=request.name, songs=request.songs)
    return {"status": "success", "id": playlist_id}


@app.get("/api/playlists/{playlist_id}")
async def get_playlist(playlist_id: str):
    """Get a playlist with song details"""
    pl = await get_playlist_by_id(playlist_id)
    if not pl:
        raise HTTPException(status_code=404, detail="Playlist not found")
    
    # Fetch song details
    songs = []
    for sid in pl.get("songs", []):
        song = await get_song_by_id(sid)
        if song:
            songs.append(song)
    
    pl["song_details"] = songs
    return pl


@app.post("/api/playlists/{playlist_id}/songs")
async def add_to_playlist(playlist_id: str, song_id: str):
    """Add a song to a playlist"""
    success = await add_song_to_playlist(playlist_id, song_id)
    return {"status": "success" if success else "failed"}


@app.delete("/api/playlists/{playlist_id}/songs/{song_id}")
async def remove_from_playlist(playlist_id: str, song_id: str):
    """Remove a song from a playlist"""
    success = await remove_song_from_playlist(playlist_id, song_id)
    return {"status": "success" if success else "failed"}


@app.delete("/api/playlists/{playlist_id}")
async def remove_playlist(playlist_id: str):
    """Delete a playlist"""
    success = await delete_playlist(playlist_id)
    if not success:
        raise HTTPException(status_code=404, detail="Playlist not found")
    return {"status": "success"}


# ==================== Homepage ====================

@app.get("/api/home")
async def get_homepage():
    """Get homepage data with recently played and AI recommendations"""
    recently_played = await get_recently_played(limit=10)
    ai_cache = await get_ai_cache()
    
    # Get AI playlist song details
    ai_playlist_songs = []
    if ai_cache and ai_cache.get("ai_playlist_songs"):
        for sid in ai_cache["ai_playlist_songs"]:
            song = await get_song_by_id(sid)
            if song:
                ai_playlist_songs.append(song)
    
    return {
        "recently_played": recently_played,
        "recommendations": ai_cache.get("recommendations", []) if ai_cache else [],
        "ai_playlist": {
            "name": ai_cache.get("ai_playlist_name", "AI Mix") if ai_cache else "AI Mix",
            "songs": ai_playlist_songs
        },
        "last_updated": ai_cache.get("updated_at") if ai_cache else None
    }


@app.post("/api/home/refresh")
async def refresh_homepage(background_tasks: BackgroundTasks):
    """Manually trigger AI recommendations refresh"""
    async def do_refresh():
        all_songs = await get_all_songs()
        if all_songs:
            result = await get_homepage_recommendations(all_songs)
            await update_ai_cache(
                recommendations=result["recommendations"],
                ai_playlist_name=result["ai_playlist"]["name"],
                ai_playlist_songs=result["ai_playlist"]["song_ids"]
            )
    
    background_tasks.add_task(do_refresh)
    return {"status": "started", "message": "Refresh started in background"}


if __name__ == "__main__":
    import uvicorn
    import os
    port = int(os.environ.get("PORT", 8000))
    # Enable reload to pick up code changes AND config.env changes
    uvicorn.run(
        "main:app", 
        host="0.0.0.0", 
        port=port, 
        reload=True,
        reload_includes=["config.env", "*.env"],
        timeout_graceful_shutdown=1
    )



