import json
import redis
from typing import Optional, Any
from app.config import settings
import structlog

logger = structlog.get_logger()


class RedisCache:
    def __init__(self):
        self.redis_client = redis.from_url(settings.redis_url, decode_responses=True)

    async def get(self, key: str) -> Optional[Any]:
        try:
            value = self.redis_client.get(key)
            if value:
                return json.loads(value)
            return None
        except Exception as e:
            logger.error("Redis get error", key=key, error=str(e))
            return None

    async def set(self, key: str, value: Any, expire: int = 300) -> bool:
        try:
            serialized_value = json.dumps(value, default=str)
            self.redis_client.setex(key, expire, serialized_value)
            return True
        except Exception as e:
            logger.error("Redis set error", key=key, error=str(e))
            return False

    async def delete(self, key: str) -> bool:
        try:
            result = self.redis_client.delete(key)
            return result > 0
        except Exception as e:
            logger.error("Redis delete error", key=key, error=str(e))
            return False

    async def delete_pattern(self, pattern: str) -> int:
        try:
            keys = self.redis_client.keys(pattern)
            if keys:
                return self.redis_client.delete(*keys)
            return 0
        except Exception as e:
            logger.error("Redis delete pattern error", pattern=pattern, error=str(e))
            return 0

    def health_check(self) -> bool:
        try:
            self.redis_client.ping()
            return True
        except Exception:
            return False


cache = RedisCache()