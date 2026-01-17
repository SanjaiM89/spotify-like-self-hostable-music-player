import os
import motor.motor_asyncio
from bson import ObjectId
from dotenv import load_dotenv

# Load env from root or current dir
load_dotenv("config.env")
load_dotenv("../config.env")

DATABASE_URL = os.getenv("DATABASE_URL")
if not DATABASE_URL:
    raise ValueError("DATABASE_URL is not set")

client = motor.motor_asyncio.AsyncIOMotorClient(DATABASE_URL)
db = client.get_database("music_app")
songs_collection = db.get_collection("songs")

def song_helper(song) -> dict:
    file_name = song.get("file_name", "")
    # Determine media_type from file extension
    video_exts = ['.mp4', '.mkv', '.webm', '.avi', '.mov']
    media_type = 'video' if any(file_name.lower().endswith(ext) for ext in video_exts) else 'audio'
    
    # Support new dual-ID schema
    has_video = song.get("has_video") or song.get("video_telegram_id") is not None or song.get("minio_video_key") is not None
    
    return {
        "id": str(song["_id"]),
        "telegram_file_id": song.get("telegram_file_id"),  # Legacy field
        "audio_telegram_id": song.get("audio_telegram_id") or song.get("telegram_file_id"),  # New: audio stream ID
        "video_telegram_id": song.get("video_telegram_id"),  # New: video stream ID
        "has_video": has_video,
        "title": song.get("title"),
        "artist": song.get("artist"),
        "album": song.get("album"),
        "duration": song.get("duration"),
        "cover_art": song.get("cover_art"),
        "thumbnail": song.get("thumbnail"),  # YouTube thumbnail
        "file_name": file_name,
        "file_size": song.get("file_size"),
        "media_type": media_type,
        "audio_local_path": song.get("audio_local_path"),
        "video_local_path": song.get("video_local_path"),
        "minio_audio_key": song.get("minio_audio_key"),
        "minio_video_key": song.get("minio_video_key"),
    }

async def init_db():
    # Motor handles connection pooling automatically
    pass

async def add_song(
    telegram_file_id: str = None, 
    title: str = None, 
    artist: str = None, 
    album: str = None, 
    duration: int = None, 
    cover_art: str = None, 
    file_name: str = None, 
    file_size: int = None, 
    thumbnail: str = None,
    audio_telegram_id: str = None,
    video_telegram_id: str = None,
    has_video: bool = False,
    audio_local_path: str = None,
    video_local_path: str = None,
    minio_audio_key: str = None,
    minio_video_key: str = None
):
    """Add a song with optional dual audio/video IDs"""
    # Check for duplicates by file_name or title+artist combo
    existing = await songs_collection.find_one({
        "$or": [
            {"file_name": file_name},
            {"title": title, "artist": artist}
        ]
    })
    if existing:
        # Update existing song with new IDs if provided
        updates = {}
        if audio_telegram_id:
            updates["audio_telegram_id"] = audio_telegram_id
        if video_telegram_id:
            updates["video_telegram_id"] = video_telegram_id
            updates["has_video"] = True
        if updates:
            await songs_collection.update_one({"_id": existing["_id"]}, {"$set": updates})
        return str(existing["_id"])  # Return existing song ID
    
    # Determine audio_telegram_id: use provided or legacy field
    final_audio_id = audio_telegram_id or telegram_file_id
    
    song_data = {
        "telegram_file_id": telegram_file_id,  # Legacy compatibility
        "audio_telegram_id": final_audio_id,
        "video_telegram_id": video_telegram_id,
        "has_video": has_video or (video_telegram_id is not None),
        "title": title,
        "artist": artist,
        "album": album,
        "duration": duration,
        "cover_art": cover_art,
        "thumbnail": thumbnail or cover_art,
        "file_name": file_name,
        "file_size": file_size,
        "audio_local_path": audio_local_path,
        "video_local_path": video_local_path,
        "minio_audio_key": minio_audio_key,
        "minio_video_key": minio_video_key
    }
    new_song = await songs_collection.insert_one(song_data)
    return str(new_song.inserted_id)

async def get_all_songs():
    songs = []
    async for song in songs_collection.find().sort("_id", -1):
        songs.append(song_helper(song))
    return songs

async def get_song_by_id(song_id: str):
    try:
        song = await songs_collection.find_one({"_id": ObjectId(song_id)})
        if song:
            return song_helper(song)
    except:
        pass
    return None

async def search_songs(query: str):
    songs = []
    # Basic regex search
    regex_query = {"$regex": query, "$options": "i"}
    async for song in songs_collection.find({
        "$or": [
            {"title": regex_query},
            {"artist": regex_query},
            {"album": regex_query}
        ]
    }):
        songs.append(song_helper(song))
    return songs


async def delete_song(song_id: str) -> bool:
    """Delete a song by ID"""
    try:
        result = await songs_collection.delete_one({"_id": ObjectId(song_id)})
        return result.deleted_count > 0
    except:
        return False


async def get_songs_paginated(page: int = 1, limit: int = 20) -> dict:
    """Get paginated songs, newest first"""
    skip = (page - 1) * limit
    total = await songs_collection.count_documents({})
    
    songs = []
    async for song in songs_collection.find().sort("_id", -1).skip(skip).limit(limit):
        songs.append(song_helper(song))
    
    return {
        "songs": songs,
        "page": page,
        "limit": limit,
        "total": total,
        "pages": (total + limit - 1) // limit if total > 0 else 1
    }


# ==================== Playlists Collection ====================
playlists_collection = db.get_collection("playlists")


def playlist_helper(playlist) -> dict:
    return {
        "id": str(playlist["_id"]),
        "name": playlist.get("name", "Untitled"),
        "songs": playlist.get("songs", []),
        "cover_art": playlist.get("cover_art"),
        "created_at": playlist.get("created_at"),
        "is_ai_generated": playlist.get("is_ai_generated", False),
    }


async def create_playlist(name: str, songs: list = None, cover_art: str = None, is_ai: bool = False) -> str:
    from datetime import datetime
    data = {
        "name": name,
        "songs": songs or [],
        "cover_art": cover_art,
        "created_at": datetime.utcnow(),
        "is_ai_generated": is_ai,
    }
    result = await playlists_collection.insert_one(data)
    return str(result.inserted_id)


async def get_playlists(page: int = 1, limit: int = 10) -> dict:
    skip = (page - 1) * limit
    total = await playlists_collection.count_documents({})
    
    playlists = []
    async for pl in playlists_collection.find().sort("created_at", -1).skip(skip).limit(limit):
        p_data = playlist_helper(pl)
        
        # Fetch cover art from first song if available
        if p_data.get("songs") and len(p_data["songs"]) > 0:
            first_song_id = p_data["songs"][0]
            # Verify song exists and get cover
            song = await get_song_by_id(first_song_id)
            if song and song.get("cover_art"):
                p_data["cover_image"] = song["cover_art"]
        
        playlists.append(p_data)
    
    return {
        "playlists": playlists,
        "page": page,
        "total": total,
        "pages": (total + limit - 1) // limit if total > 0 else 1
    }


async def get_playlist_by_id(playlist_id: str) -> dict:
    try:
        pl = await playlists_collection.find_one({"_id": ObjectId(playlist_id)})
        if pl:
            return playlist_helper(pl)
    except:
        pass
    return None


async def add_song_to_playlist(playlist_id: str, song_id: str) -> bool:
    try:
        result = await playlists_collection.update_one(
            {"_id": ObjectId(playlist_id)},
            {"$addToSet": {"songs": song_id}}
        )
        return result.modified_count > 0
    except:
        return False


async def remove_song_from_playlist(playlist_id: str, song_id: str) -> bool:
    try:
        result = await playlists_collection.update_one(
            {"_id": ObjectId(playlist_id)},
            {"$pull": {"songs": song_id}}
        )
        return result.modified_count > 0
    except:
        return False


async def delete_playlist(playlist_id: str) -> bool:
    try:
        result = await playlists_collection.delete_one({"_id": ObjectId(playlist_id)})
        return result.deleted_count > 0
    except:
        return False


# ==================== Play History Collection ====================
play_history_collection = db.get_collection("play_history")


async def record_play(song_id: str):
    """Record a song play"""
    from datetime import datetime
    await play_history_collection.insert_one({
        "song_id": song_id,
        "played_at": datetime.utcnow()
    })
    
    # Increment play count on song
    try:
        await songs_collection.update_one(
            {"_id": ObjectId(song_id)},
            {"$inc": {"play_count": 1}}
        )
    except Exception as e:
        print(f"Error incrementing play count: {e}")


async def get_recently_played(limit: int = 10) -> list:
    """Get recently played songs (unique, most recent first)"""
    from datetime import datetime, timedelta
    
    # Get plays from last 7 days
    since = datetime.utcnow() - timedelta(days=7)
    
    pipeline = [
        {"$match": {"played_at": {"$gte": since}}},
        {"$sort": {"played_at": -1}},
        {"$group": {"_id": "$song_id", "last_played": {"$first": "$played_at"}}},
        {"$sort": {"last_played": -1}},
        {"$limit": limit}
    ]
    
    song_ids = []
    async for doc in play_history_collection.aggregate(pipeline):
        song_ids.append(doc["_id"])
    
    # Fetch song details
    songs = []
    for sid in song_ids:
        song = await get_song_by_id(sid)
        if song:
            songs.append(song)
    
    return songs


# ==================== AI Cache Collection ====================
ai_cache_collection = db.get_collection("ai_cache")


async def get_ai_cache(cache_key: str = "home_recommendations") -> dict:
    """Get cached AI recommendations"""
    doc = await ai_cache_collection.find_one({"key": cache_key})
    if doc:
        return {
            "key": doc.get("key"),
            "recommendations": doc.get("recommendations", []),
            "ai_playlist_name": doc.get("ai_playlist_name", "AI Mix"),
            "ai_playlist_songs": doc.get("ai_playlist_songs", []),
            "updated_at": doc.get("updated_at"),
        }
    return None


async def update_ai_cache(
    recommendations: list,
    ai_playlist_name: str,
    ai_playlist_songs: list,
    cache_key: str = "home_recommendations"
):
    """Update AI recommendations cache"""
    from datetime import datetime
    await ai_cache_collection.update_one(
        {"key": cache_key},
        {"$set": {
            "key": cache_key,
            "recommendations": recommendations,
            "ai_playlist_name": ai_playlist_name,
            "ai_playlist_songs": ai_playlist_songs,
            "updated_at": datetime.utcnow(),
        }},
        upsert=True
    )



# ==================== YouTube Tasks Collection ====================
youtube_tasks_collection = db.get_collection("youtube_tasks")


def youtube_task_helper(task) -> dict:
    return {
        "id": str(task["_id"]),
        "task_id": task.get("task_id"),
        "url": task.get("url"),
        "status": task.get("status"),
        "progress": task.get("progress", 0),
        "title": task.get("title", ""),
        "artist": task.get("artist", ""),
        "thumbnail": task.get("thumbnail", ""),
        "duration": task.get("duration", 0),
        "file_size": task.get("file_size", 0),
        "error": task.get("error", ""),
        "quality": task.get("quality", "320"),
        "song_id": task.get("song_id"),
        "created_at": task.get("created_at"),
    }


async def save_youtube_task(task_data: dict) -> str:
    """Insert or update a YouTube download task"""
    task_id = task_data.get("task_id")
    existing = await youtube_tasks_collection.find_one({"task_id": task_id})
    
    if existing:
        await youtube_tasks_collection.update_one(
            {"task_id": task_id},
            {"$set": task_data}
        )
        return str(existing["_id"])
    else:
        from datetime import datetime
        task_data["created_at"] = datetime.utcnow()
        result = await youtube_tasks_collection.insert_one(task_data)
        return str(result.inserted_id)


async def get_youtube_task(task_id: str) -> dict:
    """Get a YouTube task by task_id"""
    task = await youtube_tasks_collection.find_one({"task_id": task_id})
    if task:
        return youtube_task_helper(task)
    return None


async def get_youtube_tasks(page: int = 1, limit: int = 10) -> dict:
    """Get paginated YouTube tasks, newest first"""
    skip = (page - 1) * limit
    total = await youtube_tasks_collection.count_documents({})
    
    tasks = []
    async for task in youtube_tasks_collection.find().sort("created_at", -1).skip(skip).limit(limit):
        tasks.append(youtube_task_helper(task))
    
    return {
        "tasks": tasks,
        "page": page,
        "limit": limit,
        "total": total,
        "pages": (total + limit - 1) // limit if total > 0 else 1
    }


async def update_youtube_task(task_id: str, updates: dict):
    """Update a YouTube task"""
    await youtube_tasks_collection.update_one(
        {"task_id": task_id},
        {"$set": updates}
    )


async def delete_youtube_task(task_id: str):
    """Delete a single YouTube task"""
    await youtube_tasks_collection.delete_one({"task_id": task_id})


async def clear_all_youtube_tasks():
    """Delete all YouTube tasks"""
    result = await youtube_tasks_collection.delete_many({})
    return result.deleted_count


# ==================== Likes Collection ====================
likes_collection = db.get_collection("likes")


async def like_song(song_id: str) -> bool:
    """Like a song (upsert)"""
    from datetime import datetime
    result = await likes_collection.update_one(
        {"song_id": song_id},
        {"$set": {"song_id": song_id, "liked": True, "updated_at": datetime.utcnow()}},
        upsert=True
    )
    return True


async def dislike_song(song_id: str) -> bool:
    """Dislike a song (upsert)"""
    from datetime import datetime
    result = await likes_collection.update_one(
        {"song_id": song_id},
        {"$set": {"song_id": song_id, "liked": False, "updated_at": datetime.utcnow()}},
        upsert=True
    )
    return True


async def remove_like(song_id: str) -> bool:
    """Remove like/dislike entry (neutral)"""
    result = await likes_collection.delete_one({"song_id": song_id})
    return result.deleted_count > 0


async def get_like_status(song_id: str) -> dict:
    """Get like status for a song. Returns {"liked": True/False/None}"""
    doc = await likes_collection.find_one({"song_id": song_id})
    if doc:
        return {"liked": doc.get("liked")}
    return {"liked": None}  # No preference


async def get_liked_songs() -> list:
    """Get all liked songs"""
    song_ids = []
    async for doc in likes_collection.find({"liked": True}):
        song_ids.append(doc["song_id"])
    
    # Fetch song details
    songs = []
    for sid in song_ids:
        song = await get_song_by_id(sid)
        if song:
            songs.append(song)
    return songs


async def get_disliked_song_ids() -> list:
    """Get IDs of disliked songs"""
    ids = []
    async for doc in likes_collection.find({"liked": False}):
        ids.append(doc["song_id"])
    return ids


async def get_recommendations(limit: int = 10) -> list:
    """Get song recommendations based on likes/dislikes.
    Prioritizes: liked songs first, then songs not disliked, excludes disliked.
    """
    disliked_ids = await get_disliked_song_ids()
    liked_songs = await get_liked_songs()
    
    # Get all songs excluding disliked
    all_songs = await get_all_songs()
    
    # Filter out disliked songs
    filtered = [s for s in all_songs if s["id"] not in disliked_ids]
    
    # Build recommendation list: liked first, then others shuffled
    import random
    liked_ids = {s["id"] for s in liked_songs}
    others = [s for s in filtered if s["id"] not in liked_ids]
    random.shuffle(others)
    
    # Combine: liked songs + random others (up to limit)
    recommendations = liked_songs[:limit]
    remaining = limit - len(recommendations)
    if remaining > 0:
        recommendations.extend(others[:remaining])
    
    return recommendations[:limit]


# ==================== AI Queue Collection ====================
ai_queue_collection = db.get_collection("ai_queue")


async def get_ai_queue() -> dict:
    """Get current AI queue from MongoDB"""
    queue = await ai_queue_collection.find_one({"_id": "main_queue"})
    if queue:
        return {
            "song_ids": queue.get("song_ids", []),
            "played_ids": queue.get("played_ids", []),
            "created_at": queue.get("created_at"),
            "updated_at": queue.get("updated_at"),
        }
    return {"song_ids": [], "played_ids": [], "created_at": None, "updated_at": None}


async def save_ai_queue(song_ids: list) -> bool:
    """Save/update AI queue in MongoDB"""
    from datetime import datetime
    
    existing = await ai_queue_collection.find_one({"_id": "main_queue"})
    now = datetime.utcnow()
    
    if existing:
        await ai_queue_collection.update_one(
            {"_id": "main_queue"},
            {"$set": {"song_ids": song_ids, "updated_at": now}}
        )
    else:
        await ai_queue_collection.insert_one({
            "_id": "main_queue",
            "song_ids": song_ids,
            "played_ids": [],
            "created_at": now,
            "updated_at": now,
        })
    return True


async def mark_song_played(song_id: str) -> bool:
    """Move song from song_ids to played_ids"""
    from datetime import datetime
    
    queue = await ai_queue_collection.find_one({"_id": "main_queue"})
    if not queue:
        return False
    
    song_ids = queue.get("song_ids", [])
    played_ids = queue.get("played_ids", [])
    
    # Remove from queue and add to played
    if song_id in song_ids:
        song_ids.remove(song_id)
    if song_id not in played_ids:
        played_ids.append(song_id)
    
    await ai_queue_collection.update_one(
        {"_id": "main_queue"},
        {"$set": {"song_ids": song_ids, "played_ids": played_ids, "updated_at": datetime.utcnow()}}
    )
    return True


async def clear_played_queue() -> bool:
    """Clear played_ids list (for fresh start)"""
    await ai_queue_collection.update_one(
        {"_id": "main_queue"},
        {"$set": {"played_ids": []}}
    )
    return True


async def get_queue_songs() -> list:
    """Get full song objects for queue"""
    queue = await get_ai_queue()
    songs = []
    for song_id in queue["song_ids"]:
        song = await get_song_by_id(song_id)
        if song:
            songs.append(song)
    return songs


async def refill_queue_if_needed(min_songs: int = 10) -> bool:
    """
    Check if queue has minimum songs, refill from recommendations if needed.
    Returns True if queue was refilled.
    """
    queue = await get_ai_queue()
    current_count = len(queue["song_ids"])
    
    if current_count >= min_songs:
        return False
    
    # Need to add more songs
    needed = min_songs - current_count
    played_ids = set(queue["played_ids"])
    current_ids = set(queue["song_ids"])
    
    # Get all songs excluding played and current queue
    all_songs = await get_all_songs()
    available = [s for s in all_songs if s["id"] not in played_ids and s["id"] not in current_ids]
    
    # Prioritize liked songs
    liked = await get_liked_songs()
    liked_ids = {s["id"] for s in liked}
    
    # Sort: liked first, then others
    liked_available = [s for s in available if s["id"] in liked_ids]
    others = [s for s in available if s["id"] not in liked_ids]
    
    import random
    random.shuffle(others)
    
    candidates = liked_available + others
    new_song_ids = [s["id"] for s in candidates[:needed]]
    
    if new_song_ids:
        updated_queue = queue["song_ids"] + new_song_ids
        await save_ai_queue(updated_queue)
        return True
    
    return False
    return False


# ==================== App Playlists Collection ====================
app_playlists_collection = db.get_collection("app_playlists")

async def get_app_playlists() -> list:
    """Get all app playlists"""
    cursor = app_playlists_collection.find().sort("created_at", -1)
    playlists = []
    async for p in cursor:
        p["id"] = str(p["_id"])
        del p["_id"]
        playlists.append(p)
    return playlists

async def create_app_playlist(name: str, song_ids: list, description: str = "", cover_image: str = None) -> str:
    """Create a new app playlist"""
    from datetime import datetime
    
    # If no cover image, try to get one from first song
    if not cover_image and song_ids:
        first_song = await get_song_by_id(song_ids[0])
        if first_song:
            cover_image = first_song.get("cover_art")

    result = await app_playlists_collection.insert_one({
        "name": name,
        "description": description,
        "song_ids": song_ids,
        "cover_image": cover_image,
        "created_at": datetime.utcnow(),
        "updated_at": datetime.utcnow()
    })
    return str(result.inserted_id)

async def get_playlist_with_songs(playlist_id: str) -> dict:
    """Get playlist details with full song objects"""
    try:
        playlist = await app_playlists_collection.find_one({"_id": ObjectId(playlist_id)})
        if not playlist:
            return None
        
        playlist["id"] = str(playlist["_id"])
        del playlist["_id"]
        
        full_songs = []
        for sid in playlist.get("song_ids", []):
            s = await get_song_by_id(sid)
            if s:
                full_songs.append(s)
        
        playlist["songs"] = full_songs
        return playlist
    except:
        return None

async def init_default_playlists():
    """Initialize some default playlists if none exist"""
    count = await app_playlists_collection.count_documents({})
    if count == 0:
        all_songs = await get_all_songs()
        if not all_songs:
            return
            
        import random
        # Create "Recently Added"
        recent = sorted(all_songs, key=lambda x: x.get("id", ""), reverse=True)[:10]
        if recent:
            await create_app_playlist("Fresh Arrivals", [s["id"] for s in recent], "Newest tracks in your library")
            
        # Create a random mix
        if len(all_songs) >= 5:
            mix = random.sample(all_songs, min(15, len(all_songs)))
            await create_app_playlist("Random Mix", [s["id"] for s in mix], "A bit of everything")
