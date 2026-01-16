import os
import asyncio
import subprocess
import math

# Target size in bytes (1.9 GB to be safe for Telegram's 2GB limit)
TARGET_SIZE_BYTES = 1.9 * 1024 * 1024 * 1024

async def get_video_duration(input_path: str) -> float:
    """Get video duration in seconds using ffprobe."""
    cmd = [
        "ffprobe", 
        "-v", "error", 
        "-show_entries", "format=duration", 
        "-of", "default=noprint_wrappers=1:nokey=1", 
        input_path
    ]
    process = await asyncio.create_subprocess_exec(
        *cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )
    stdout, stderr = await process.communicate()
    if process.returncode != 0:
        raise Exception(f"ffprobe error: {stderr.decode()}")
    return float(stdout.decode().strip())

async def compress_video_if_needed(input_path: str) -> str:
    """
    Checks if video exceeds TARGET_SIZE_BYTES.
    If so, compresses it to target size using ffmpeg 2-pass encoding.
    Returns the path to the file to be uploaded (original or compressed).
    """
    file_size = os.path.getsize(input_path)
    
    if file_size <= TARGET_SIZE_BYTES:
        print(f"✅ Video size {file_size / (1024**3):.2f} GB is within limit.")
        return input_path

    print(f"⚠️ Video size {file_size / (1024**3):.2f} GB exceeds limit. Compressing to 1.9 GB...")
    
    duration = await get_video_duration(input_path)
    
    # Calculate target bitrate
    # target_size = duration * bitrate / 8
    # bitrate = target_size * 8 / duration
    target_total_bitrate = (TARGET_SIZE_BYTES * 8) / duration
    
    # Split bitrate: 128k for audio, rest for video
    audio_bitrate = 128 * 1000
    video_bitrate = target_total_bitrate - audio_bitrate
    
    if video_bitrate < 1000:
        raise Exception("Target bitrate too low for compression.")
        
    output_path = f"{os.path.splitext(input_path)[0]}_compressed.mp4"
    
    # Convert bitrates to string for ffmpeg (e.g., "1500k")
    video_bitrate_str = f"{int(video_bitrate)}"
    audio_bitrate_str = f"{int(audio_bitrate)}"

    # 2-pass encoding for better quality at specific size
    # Pass 1
    pass1_cmd = [
        "ffmpeg", "-y", "-i", input_path,
        "-c:v", "libx264", "-b:v", video_bitrate_str, "-pass", "1",
        "-an", "-f", "null", "/dev/null"
    ]
    
    # Pass 2
    pass2_cmd = [
        "ffmpeg", "-y", "-i", input_path,
        "-c:v", "libx264", "-b:v", video_bitrate_str, "-pass", "2",
        "-c:a", "aac", "-b:a", audio_bitrate_str,
        output_path
    ]
    
    print("🔄 Starting Pass 1...")
    p1 = await asyncio.create_subprocess_exec(*pass1_cmd)
    await p1.wait()
    
    print("🔄 Starting Pass 2...")
    p2 = await asyncio.create_subprocess_exec(*pass2_cmd)
    await p2.wait()
    
    # Cleanup pass log files
    for f in os.listdir("."):
        if f.startswith("ffmpeg2pass"):
            os.remove(f)
            
    if os.path.exists(output_path):
        print(f"✅ Compression complete: {output_path}")
        return output_path
    else:
        raise Exception("Compression failed, output file not created.")
