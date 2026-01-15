"""
MongoDB-based session storage for Pyrogram.
Persists session data to MongoDB, allowing bots to survive container restarts.
"""
import asyncio
from typing import Any, Dict, List, Optional
from pyrogram.storage import Storage
from motor.motor_asyncio import AsyncIOMotorClient
import os

MONGO_URI = os.getenv("DATABASE_URL") or os.getenv("MONGO_DB_URI") or "mongodb://localhost:27017"


class MongoStorage(Storage):
    """Pyrogram storage backend using MongoDB."""
    
    def __init__(self, name: str):
        super().__init__(name)
        self._client = None
        self._db = None
        self._collection = None
        self._dc_id = 0
        self._api_id = 0
        self._test_mode = False
        self._auth_key = b""
        self._date = 0
        self._user_id = 0
        self._is_bot = True
    
    async def open(self):
        self._client = AsyncIOMotorClient(MONGO_URI)
        self._db = self._client.pyrogram_sessions
        self._collection = self._db[self.name]
        
        # Load existing session
        session = await self._collection.find_one({"_id": "session"})
        if session:
            self._dc_id = session.get("dc_id", 0)
            self._api_id = session.get("api_id", 0)
            self._test_mode = session.get("test_mode", False)
            self._auth_key = session.get("auth_key", b"")
            self._date = session.get("date", 0)
            self._user_id = session.get("user_id", 0)
            self._is_bot = session.get("is_bot", True)
            print(f"[MongoSession] Loaded existing session for {self.name}")
        else:
            print(f"[MongoSession] No existing session found for {self.name}")
    
    async def save(self):
        await self._collection.update_one(
            {"_id": "session"},
            {"$set": {
                "dc_id": self._dc_id,
                "api_id": self._api_id,
                "test_mode": self._test_mode,
                "auth_key": self._auth_key,
                "date": self._date,
                "user_id": self._user_id,
                "is_bot": self._is_bot
            }},
            upsert=True
        )
    
    async def close(self):
        if self._client:
            self._client.close()
    
    async def delete(self):
        await self._collection.delete_many({})
    
    async def update_peers(self, peers: List[tuple]):
        """Store peer access hashes."""
        for peer in peers:
            peer_id, access_hash, peer_type, username, phone = peer
            await self._collection.update_one(
                {"_id": f"peer_{peer_id}"},
                {"$set": {
                    "peer_id": peer_id,
                    "access_hash": access_hash,
                    "type": peer_type,
                    "username": username,
                    "phone": phone
                }},
                upsert=True
            )
    
    async def get_peer_by_id(self, peer_id: int):
        """Retrieve peer by ID."""
        doc = await self._collection.find_one({"_id": f"peer_{peer_id}"})
        if doc:
            return (doc["peer_id"], doc["access_hash"], doc["type"], doc.get("username"), doc.get("phone"))
        return None
    
    async def get_peer_by_username(self, username: str):
        """Retrieve peer by username."""
        doc = await self._collection.find_one({"username": username.lower()})
        if doc:
            return (doc["peer_id"], doc["access_hash"], doc["type"], doc.get("username"), doc.get("phone"))
        return None
    
    async def get_peer_by_phone_number(self, phone_number: str):
        """Retrieve peer by phone number."""
        doc = await self._collection.find_one({"phone": phone_number})
        if doc:
            return (doc["peer_id"], doc["access_hash"], doc["type"], doc.get("username"), doc.get("phone"))
        return None
    
    # Properties required by Pyrogram
    async def dc_id(self, value: int = None):
        if value is not None:
            self._dc_id = value
            await self.save()
        return self._dc_id
    
    async def api_id(self, value: int = None):
        if value is not None:
            self._api_id = value
            await self.save()
        return self._api_id
    
    async def test_mode(self, value: bool = None):
        if value is not None:
            self._test_mode = value
            await self.save()
        return self._test_mode
    
    async def auth_key(self, value: bytes = None):
        if value is not None:
            self._auth_key = value
            await self.save()
        return self._auth_key
    
    async def date(self, value: int = None):
        if value is not None:
            self._date = value
            await self.save()
        return self._date
    
    async def user_id(self, value: int = None):
        if value is not None:
            self._user_id = value
            await self.save()
        return self._user_id
    
    async def is_bot(self, value: bool = None):
        if value is not None:
            self._is_bot = value
            await self.save()
        return self._is_bot
