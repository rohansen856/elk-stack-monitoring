import hashlib
import hmac
import html
import secrets
import smtplib
import ssl
import string
from datetime import datetime, timedelta, timezone
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from typing import Optional

import structlog
from sqlalchemy.orm import Session
from starlette.concurrency import run_in_threadpool

from app.config import settings
from app.models.password_reset import PasswordResetToken
from app.models.user import User

logger = structlog.get_logger()

SMTP_TIMEOUT_SECONDS = 15


def generate_otp(length: Optional[int] = None) -> str:
    """Generate a password-reset OTP using a cryptographically secure RNG.

    Previously this used ``random.choices`` (Mersenne Twister), whose output is
    fully reproducible from generator state recoverable from 624 observed
    outputs. A 6-digit code also gave a 10^6 keyspace that was exhaustible
    inside its own 15-minute validity window. See AUDIT SEC-003.
    """
    length = length or settings.otp_length
    return "".join(secrets.choice(string.digits) for _ in range(length))


def hash_otp(otp: str) -> str:
    """Keyed hash of an OTP, so the database never stores the usable code."""
    return hmac.new(
        settings.secret_key.encode("utf-8"), otp.encode("utf-8"), hashlib.sha256
    ).hexdigest()


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


def _as_aware(value: datetime) -> datetime:
    return value if value.tzinfo else value.replace(tzinfo=timezone.utc)


def _send_email_blocking(to_email: str, subject: str, body: str) -> bool:
    """Send an email over an authenticated, certificate-verified TLS session."""
    try:
        msg = MIMEMultipart()
        msg["From"] = f"{settings.email_sender_name} <{settings.email_sender_address}>"
        msg["To"] = to_email
        msg["Subject"] = subject
        msg.attach(MIMEText(body, "html"))

        # Explicit timeout: smtplib.SMTP defaults to no timeout, so an
        # unresponsive server blocked the event loop indefinitely on an
        # unauthenticated endpoint. Certificates are verified, which
        # bare starttls() did not do. See AUDIT SEC-016.
        context = ssl.create_default_context()
        with smtplib.SMTP(
            settings.email_smtp_server, settings.email_smtp_port, timeout=SMTP_TIMEOUT_SECONDS
        ) as server:
            server.starttls(context=context)
            server.login(settings.email_smtp_username, settings.email_smtp_password)
            server.sendmail(settings.email_sender_address, to_email, msg.as_string())
        return True
    except Exception as e:
        # structlog, not print(): print bypasses the very log pipeline this
        # project ships, so delivery failures were invisible to operators.
        logger.error("Failed to send email", error=str(e), to=to_email)
        return False


async def send_email(to_email: str, subject: str, body: str) -> bool:
    """Send mail without blocking the event loop.

    smtplib is synchronous, so the call is offloaded to a worker thread.
    Previously it ran inline inside an async handler on an unauthenticated
    endpoint, so one unresponsive SMTP server stalled the whole process.
    See AUDIT P1 / SEC-016.
    """
    return await run_in_threadpool(_send_email_blocking, to_email, subject, body)


async def send_password_reset_otp(db: Session, user: User) -> Optional[str]:
    """Issue a password-reset OTP, invalidating any still outstanding.

    Previously each call minted an additional valid OTP without touching the
    others, so an attacker could raise the density of valid codes at will.
    See AUDIT SEC-003.
    """
    db.query(PasswordResetToken).filter(
        PasswordResetToken.user_id == user.id,
        PasswordResetToken.is_used == False,  # noqa: E712 - SQLAlchemy requires ==
    ).update({"is_used": True}, synchronize_session=False)

    otp = generate_otp()
    reset_token = PasswordResetToken(
        user_id=user.id,
        token=hash_otp(otp),
        expires_at=_utcnow() + timedelta(minutes=settings.otp_expire_minutes),
    )
    db.add(reset_token)
    db.commit()

    safe_username = html.escape(user.username)
    subject = "Password Reset OTP - Sentinel Security"
    body = f"""
    <html>
    <body>
        <h2>Password Reset Request</h2>
        <p>Hello {safe_username},</p>
        <p>You have requested to reset your password for your Sentinel Security account.</p>

        <div style="background: #f5f5f5; padding: 20px; margin: 20px 0; border-radius: 8px; text-align: center;">
            <h3>Your OTP Code:</h3>
            <h1 style="color: #007bff; letter-spacing: 4px; margin: 10px 0;">{otp}</h1>
            <p><strong>This code will expire in {settings.otp_expire_minutes} minutes.</strong></p>
        </div>

        <p>If you didn't request this password reset, please ignore this email.</p>

        <p>Best regards,<br>
        The Sentinel Security Team</p>

        <hr>
        <p style="font-size: 12px; color: #666;">
            This is an automated email. Please do not reply to this message.
        </p>
    </body>
    </html>
    """

    if await send_email(user.email, subject, body):
        return otp

    db.delete(reset_token)
    db.commit()
    return None


class OTPLockedOut(Exception):
    """Too many failed verification attempts against the active OTP."""


def verify_password_reset_otp(db: Session, email: str, otp: str) -> Optional[User]:
    """Verify an OTP, counting failures and locking out after a threshold.

    Previously there was no attempt counter and no rate limiting anywhere, so
    the entire keyspace could be walked within the code's validity window.
    See AUDIT SEC-003.
    """
    user = db.query(User).filter(User.email == email).first()
    if not user:
        return None

    active = (
        db.query(PasswordResetToken)
        .filter(
            PasswordResetToken.user_id == user.id,
            PasswordResetToken.is_used == False,  # noqa: E712
        )
        .order_by(PasswordResetToken.created_at.desc())
        .first()
    )
    if active is None:
        return None

    if active.attempt_count >= settings.otp_max_attempts:
        active.is_used = True
        db.commit()
        logger.warning(
            "Password reset OTP locked out after repeated failures",
            user_id=user.id,
            attempts=active.attempt_count,
        )
        raise OTPLockedOut()

    if _as_aware(active.expires_at) <= _utcnow():
        return None

    if not hmac.compare_digest(active.token, hash_otp(otp)):
        active.attempt_count += 1
        db.commit()
        return None

    active.is_used = True
    db.commit()
    return user


def cleanup_expired_tokens(db: Session) -> int:
    """Delete expired reset tokens.

    Invoked by the scheduled cleanup task in app.tasks; previously this existed
    but was never called from anywhere, so the table grew without bound
    (AUDIT P7/QA-003).
    """
    deleted = (
        db.query(PasswordResetToken)
        .filter(PasswordResetToken.expires_at < _utcnow())
        .delete(synchronize_session=False)
    )
    db.commit()
    return deleted
