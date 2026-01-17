# Use official Python 3.13 slim image
FROM python:3.13-slim

# Set working directory
WORKDIR /app

# Install system dependencies (ffmpeg for yt-dlp, build-essential/python3-dev for tgcrypto)
RUN apt-get update && apt-get install -y \
    ffmpeg \
    git \
    build-essential \
    libssl-dev \
    python3-dev \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements file
COPY requirements.txt .

# Install Python dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY . .

# Expose port (FastAPI defaults to 8000, we use Dynamic)
ENV PORT=8080
EXPOSE $PORT

# Run the application
CMD ["python", "main.py"]
