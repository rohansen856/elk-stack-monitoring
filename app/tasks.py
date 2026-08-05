"""Background maintenance tasks.

``cleanup_expired_tokens`` existed but was never called from anywhere, so the
``password_reset_tokens`` table grew without bound - and because
``/forgot-password`` was unauthenticated and unthrottled, an attacker could
drive that growth. See AUDIT P7 / QA-003.
"""
import asyncio

import structlog

from app.database import SessionLocal
from app.services.email_service import cleanup_expired_tokens

logger = structlog.get_logger()

CLEANUP_INTERVAL_SECONDS = 3600


async def _run_cleanup_once() -> int:
    db = SessionLocal()
    try:
        return cleanup_expired_tokens(db)
    finally:
        db.close()


async def periodic_token_cleanup(interval: int = CLEANUP_INTERVAL_SECONDS) -> None:
    """Delete expired password-reset tokens on a schedule."""
    while True:
        try:
            await asyncio.sleep(interval)
            # Synchronous ORM work, so keep it off the event loop.
            deleted = await asyncio.to_thread(_sync_cleanup)
            if deleted:
                logger.info("Expired password reset tokens removed", count=deleted)
        except asyncio.CancelledError:
            raise
        except Exception as e:  # keep the loop alive across transient failures
            logger.error("Token cleanup failed", error=str(e))


def _sync_cleanup() -> int:
    db = SessionLocal()
    try:
        return cleanup_expired_tokens(db)
    finally:
        db.close()
