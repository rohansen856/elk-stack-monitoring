"""Redis cache.

Previously this wrapped the *synchronous* redis client in ``async def``
methods, so every cache call blocked the event loop for a full network round
trip and serialised all concurrent requests behind it. See AUDIT P1.
"""
import json
from typing import Any, Optional

import redis.asyncio as redis
import structlog

from app.config import settings

logger = structlog.get_logger()


class RedisCache:
    def __init__(self) -> None:
        self.redis_client = redis.from_url(settings.redis_url, decode_responses=True)

    async def get(self, key: str) -> Optional[Any]:
        try:
            value = await self.redis_client.get(key)
            if value:
                return json.loads(value)
            return None
        except Exception as e:
            logger.error("Redis get error", key=key, error=str(e))
            return None

    async def set(self, key: str, value: Any, expire: int = 300) -> bool:
        try:
            serialized_value = json.dumps(value, default=str)
            await self.redis_client.setex(key, expire, serialized_value)
            return True
        except Exception as e:
            logger.error("Redis set error", key=key, error=str(e))
            return False

    async def delete(self, key: str) -> bool:
        try:
            result = await self.redis_client.delete(key)
            return result > 0
        except Exception as e:
            logger.error("Redis delete error", key=key, error=str(e))
            return False

    async def delete_pattern(self, pattern: str) -> int:
        """Delete every key matching a pattern.

        Uses SCAN rather than KEYS: KEYS is O(N) over the entire keyspace and
        blocks the single-threaded Redis server for its duration, and this runs
        on every todo create, update and delete. See AUDIT P2.
        """
        try:
            deleted = 0
            batch = []
            async for key in self.redis_client.scan_iter(match=pattern, count=500):
                batch.append(key)
                if len(batch) >= 500:
                    deleted += await self.redis_client.delete(*batch)
                    batch = []
            if batch:
                deleted += await self.redis_client.delete(*batch)
            return deleted
        except Exception as e:
            logger.error("Redis delete pattern error", pattern=pattern, error=str(e))
            return 0

    async def health_check(self) -> bool:
        try:
            await self.redis_client.ping()
            return True
        except Exception:
            return False

    async def close(self) -> None:
        try:
            await self.redis_client.aclose()
        except Exception:  # pragma: no cover - best-effort shutdown
            pass


cache = RedisCache()
