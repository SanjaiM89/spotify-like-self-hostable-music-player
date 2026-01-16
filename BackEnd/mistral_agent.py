import os
import httpx
from typing import List, Dict
import asyncio

MISTRAL_API_KEY = os.getenv("MISTRAL_API_KEY", "5w4rvCocyO2ZWXDUw974C8BbGdc4MJiB")
MISTRAL_API_URL = "https://api.mistral.ai/v1/chat/completions"

# Rate limiting - free tier is 1 request/second
_last_request_time = 0


async def _rate_limit():
    """Ensure at least 1.5 seconds between requests (safe margin for free tier)"""
    global _last_request_time
    import time
    now = time.time()
    wait_time = max(0, 1.5 - (now - _last_request_time))
    if wait_time > 0:
        await asyncio.sleep(wait_time)
    _last_request_time = time.time()


async def _call_mistral(prompt: str, temperature: float = 0.7) -> str:
    """Make a rate-limited call to Mistral API"""
    await _rate_limit()
    
    headers = {
        "Authorization": f"Bearer {MISTRAL_API_KEY}",
        "Content-Type": "application/json"
    }
    
    payload = {
        "model": "mistral-tiny",  # Cheapest model for free tier
        "messages": [{"role": "user", "content": prompt}],
        "temperature": temperature,
        "max_tokens": 200  # Limit tokens to save quota
    }
    
    try:
        async with httpx.AsyncClient() as client:
            response = await client.post(MISTRAL_API_URL, json=payload, headers=headers, timeout=15.0)
            if response.status_code == 200:
                data = response.json()
                return data["choices"][0]["message"]["content"]
            else:
                print(f"Mistral API Error: {response.status_code} - {response.text}")
                return ""
    except Exception as e:
        print(f"Error calling Mistral API: {e}")
        return ""


async def get_music_recommendations(current_song: Dict, history: List[Dict]) -> List[str]:
    """
    Asks Mistral to recommend songs based on current song and history.
    Returns a list of song titles/artist strings.
    """
    history_str = "\n".join([f"- {s.get('title', 'Unknown')} by {s.get('artist', 'Unknown')}" for s in history[-5:]])
    current_str = f"{current_song.get('title', 'Unknown')} by {current_song.get('artist', 'Unknown')}"
    
    # Build list of songs to exclude
    all_titles = [s.get('title', '').lower() for s in history]
    all_titles.append(current_song.get('title', '').lower())
    
    prompt = f"""I am listening to: {current_str}

My recent songs:
{history_str}

Recommend 5 similar songs that are NOT already in my list above.
Do NOT repeat any song I already have. Suggest NEW songs only.
Return ONLY "Title - Artist" format, one per line, no numbers."""
    
    content = await _call_mistral(prompt)
    if content:
        # Filter out any songs that match existing titles
        recommendations = []
        for line in content.split("\n"):
            line = line.strip()
            if line and " - " in line:
                title = line.split(" - ")[0].lower()
                if title not in all_titles:
                    recommendations.append(line)
        return recommendations[:5]
    return []


async def generate_ai_playlist(songs: List[Dict]) -> Dict:
    """
    Generate an AI playlist with a creative name based on library songs.
    Returns {"name": "Creative Name", "song_ids": [...]}
    """
    if not songs:
        return {"name": "AI Mix", "song_ids": []}
    
    # Pick random songs for the playlist (max 10)
    import random
    selected = random.sample(songs, min(10, len(songs)))
    song_ids = [s["id"] for s in selected]
    
    # Generate creative playlist name
    song_list = ", ".join([f"{s.get('title', 'Unknown')}" for s in selected[:5]])
    
    prompt = f"""Create a creative, catchy playlist name (2-4 words) for a mix containing: {song_list}

Examples: "Late Night Vibes", "Morning Energy", "Sunset Drive", "Chill Mode"

Return ONLY the playlist name, nothing else."""
    
    name = await _call_mistral(prompt, temperature=0.9)
    name = name.strip().strip('"').strip("'")[:30] if name else "AI Mix"
    
    return {
        "name": name,
        "song_ids": song_ids
    }


async def get_homepage_recommendations(all_songs: List[Dict], liked_songs: List[Dict] = None) -> Dict:
    """
    Generate recommendations for homepage (called hourly).
    Uses liked_songs to personalize AI recommendations.
    Returns {"recommendations": [...], "ai_playlist": {...}}
    """
    if not all_songs:
        return {
            "recommendations": [],
            "ai_playlist": {"name": "AI Mix", "song_ids": []}
        }
    
    import random
    
    # Use liked songs if available, otherwise use random
    if liked_songs and len(liked_songs) > 0:
        # Base recommendations on user's liked songs
        sample_song = random.choice(liked_songs)
        history = liked_songs[:5]
        print(f"[AI] Using {len(liked_songs)} liked songs for personalization")
    else:
        sample_song = random.choice(all_songs) if all_songs else {}
        history = all_songs[:5]
        print("[AI] No liked songs, using random sample")
    
    recommendations = await get_music_recommendations(sample_song, history)
    ai_playlist = await generate_ai_playlist(all_songs)
    
    return {
        "recommendations": recommendations,
        "ai_playlist": ai_playlist
    }


