# Use official Python 3.10 slim image
FROM python:3.10-slim

# Set working directory
WORKDIR /app

# Install system dependencies (ffmpeg is required for yt-dlp)
RUN apt-get update && apt-get install -y \
    ffmpeg \
    git \
    && rm -rf /var/lib/apt/lists/*

# Copy backend requirements from the BackEnd folder
COPY BackEnd/requirements.txt .

# Install Python dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Copy the rest of the backend code
COPY BackEnd/ .

# Expose the port (Render sets PORT env var, but 8000 is default fallback)
EXPOSE 8000

# Run the application
CMD ["python", "main.py"]
