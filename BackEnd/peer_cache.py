"""
Simple peer cache for Pyrogram - stores access hashes in MongoDB.
"""
import os
from motor.motor_asyncio import AsyncIOMotorClient

MONGO_URI = os.getenv("DATABASE_URL") or os.getenv("MONGO_DB_URI") or "mongodb://localhost:27017"

_client = None
_collection = None


async def get_collection():
    global _client, _collection
    if _collection is None:
        _client = AsyncIOMotorClient(MONGO_URI)
        _collection = _client.lazyio.peer_cache
    return _collection


async def save_peer(peer_id: int, access_hash: int, peer_type: str = "channel"):
    """Save a peer's access hash to MongoDB."""
    coll = await get_collection()
    await coll.update_one(
        {"peer_id": peer_id},
        {"$set": {"access_hash": access_hash, "type": peer_type}},
        upsert=True
    )
    print(f"[PeerCache] Saved peer {peer_id} with access_hash")


async def get_peer(peer_id: int):
    """Get a peer's access hash from MongoDB."""
    coll = await get_collection()
    doc = await coll.find_one({"peer_id": peer_id})
    if doc:
        return doc.get("access_hash")
    return None
