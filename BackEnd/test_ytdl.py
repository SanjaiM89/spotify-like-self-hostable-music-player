#!/usr/bin/env python3
"""Test yt-dlp with exact same config as youtube_downloader.py"""

from yt_dlp import YoutubeDL
import sys

url = sys.argv[1] if len(sys.argv) > 1 else "https://www.youtube.com/watch?v=dQw4w9WgXcQ"

opts = {
    "format": "bestaudio/best",
    "outtmpl": "/tmp/test_python_%(id)s.%(ext)s",
    "quiet": False,
    "no_warnings": False,
     "noplaylist": True,
    "js_runtimes": {"node": {}},
    "cookiesfrombrowser": ("chrome",),
}

print(f"Testing download of: {url}")
print(f"Options: {opts}")

with YoutubeDL(opts) as ydl:
    ydl.download([url])

print("Download complete!")
