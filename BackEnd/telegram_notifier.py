"""
Telegram Notification System for Owner Alerts
Sends status updates about YouTube downloads and VPN rotation
"""

import asyncio
import os
from typing import Optional
from dotenv import load_dotenv

load_dotenv("../config.env")
load_dotenv("config.env")

OWNER_TELEGRAM_ID = os.getenv("OWNER_TELEGRAM_ID")

class TelegramNotifier:
    def __init__(self, tg_client):
        """
        Initialize notifier with existing Telegram client
        Args:
            tg_client: TelegramClientWrapper instance
        """
        self.tg_client = tg_client
        self.owner_id = OWNER_TELEGRAM_ID
        
    async def notify_owner(self, message: str) -> bool:
        """
        Send notification to owner
        Args:
            message: Notification text (supports markdown)
        Returns:
            True if sent successfully, False otherwise
        """
        if not self.owner_id:
            print("[NOTIFIER] OWNER_TELEGRAM_ID not set, skipping notification")
            return False
            
        try:
            # Send via the telegram client
            await self.tg_client.client.send_message(
                int(self.owner_id),
                message,
                parse_mode='markdown'
            )
            print(f"[NOTIFIER] Sent to owner: {message[:50]}...")
            return True
        except Exception as e:
            print(f"[NOTIFIER] Failed to send: {e}")
            return False
    
    async def notify_youtube_block(self, video_url: str, ip: str):
        """Notify owner that YouTube blocked download"""
        message = (
            "🚫 **YouTube Download Blocked**\n\n"
            f"Video: `{video_url[:50]}...`\n"
            f"IP: `{ip}`\n\n"
            f"_Attempting VPN rotation..._"
        )
        await self.notify_owner(message)
    
    async def notify_vpn_rotating(self, old_ip: str):
        """Notify owner that VPN is rotating"""
        message = (
            "🔄 **VPN Rotation Started**\n\n"
            f"Old IP: `{old_ip}`\n"
            f"_Switching to new server..._"
        )
        await self.notify_owner(message)
    
    async def notify_vpn_success(self, new_ip: str, new_port: int, server: str = "Unknown"):
        """Notify owner of successful VPN rotation"""
        message = (
            "✅ **VPN Rotation Successful**\n\n"
            f"New IP: `{new_ip}`\n"
            f"New Port: `{new_port}`\n"
            f"Server: `{server}`\n\n"
            f"_Retrying download..._"
        )
        await self.notify_owner(message)
    
    async def notify_vpn_failed(self, error: str):
        """Notify owner of VPN rotation failure"""
        message = (
            "❌ **VPN Rotation Failed**\n\n"
            f"Error: `{error}`\n\n"
            f"_Please check VPN manually_"
        )
        await self.notify_owner(message)
    
    async def notify_download_retry(self, video_url: str):
        """Notify owner download is being retried"""
        message = (
            "⬇️ **Retrying Download**\n\n"
            f"Video: `{video_url[:50]}...`\n"
            f"_Using new IP address..._"
        )
        await self.notify_owner(message)
        
    async def notify_download_success(self, title: str):
        """Notify owner of successful download after recovery"""
        message = (
            "🎉 **Download Recovered**\n\n"
            f"Title: `{title}`\n"
            f"_Successfully downloaded after VPN rotation_"
        )
        await self.notify_owner(message)

# Global instance (initialized in main.py)
notifier: Optional[TelegramNotifier] = None

def init_notifier(tg_client):
    """Initialize the global notifier instance"""
    global notifier
    notifier = TelegramNotifier(tg_client)
    return notifier
