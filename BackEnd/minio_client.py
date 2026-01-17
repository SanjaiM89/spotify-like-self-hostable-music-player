import os
from minio import Minio
from minio.error import S3Error
from datetime import timedelta

# MinIO Configuration
MINIO_ENDPOINT = os.getenv("MINIO_ENDPOINT", "localhost:9000")
MINIO_ACCESS_KEY = os.getenv("MINIO_ACCESS_KEY", "admin")
MINIO_SECRET_KEY = os.getenv("MINIO_SECRET_KEY", "password")
BUCKET_NAME = "music-library"
# Convert 'false' string to boolean False
MINIO_SECURE = os.getenv("MINIO_SECURE", "false").lower() == "true"

class MinioClient:
    def __init__(self):
        self.client = None
        self.init_client()

    def init_client(self):
        try:
            self.client = Minio(
                MINIO_ENDPOINT,
                access_key=MINIO_ACCESS_KEY,
                secret_key=MINIO_SECRET_KEY,
                secure=MINIO_SECURE
            )
            self._ensure_bucket_exists()
            print("[MinIO] Client Initialized & Connected")
        except Exception as e:
            print(f"[MinIO] Connection Failed: {e}")
            self.client = None

    def _ensure_bucket_exists(self):
        if not self.client: return
        try:
            if not self.client.bucket_exists(BUCKET_NAME):
                self.client.make_bucket(BUCKET_NAME)
                print(f"[MinIO] Created bucket: {BUCKET_NAME}")
                
                # Set public policy for simpler access (optional, usually safer to use presigned)
                # But for a local music server, let's stick to presigned for now.
        except S3Error as e:
            print(f"[MinIO] Bucket check failed: {e}")

    def upload_file(self, file_path: str, object_name: str, content_type: str = "application/octet-stream"):
        """Uploads a file to MinIO."""
        if not self.client:
            print("[MinIO] Client not ready, skipping upload")
            return None

        try:
            result = self.client.fput_object(
                BUCKET_NAME, 
                object_name, 
                file_path,
                content_type=content_type
            )
            print(f"[MinIO] Uploaded {object_name} (Etag: {result.etag})")
            return object_name
        except S3Error as e:
            print(f"[MinIO] Upload failed: {e}")
            return None

    def get_presigned_url(self, object_name: str, expires_hours=1):
        """Generates a presigned URL for streaming."""
        if not self.client: return None
        
        try:
            url = self.client.get_presigned_url(
                "GET",
                BUCKET_NAME,
                object_name,
                expires=timedelta(hours=expires_hours)
            )
            return url
        except S3Error as e:
            print(f"[MinIO] URL generation failed: {e}")
            return None

    def get_object_stat(self, object_name: str):
        if not self.client: return None
        try:
            return self.client.stat_object(BUCKET_NAME, object_name)
        except:
            return None

# Global Instance
minio_client = MinioClient()
