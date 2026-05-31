from sqlalchemy import Column, Integer, String, DateTime, Boolean, ForeignKey, Index, false
from sqlalchemy.sql import func
from sqlalchemy.orm import relationship
from app.database import Base


class PasswordResetToken(Base):
    __tablename__ = "password_reset_tokens"

    id = Column(Integer, primary_key=True, index=True)
    # Indexed: every OTP verification filters on user_id, which previously meant
    # a sequential scan over a table that was never cleaned up (AUDIT P6/P7).
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    # HMAC-SHA256 of the OTP, not the OTP itself. Also no longer globally
    # unique: a collision between two users' codes used to raise IntegrityError
    # and surface as a 500 (AUDIT SEC-003).
    token = Column(String(64), index=True, nullable=False)
    is_used = Column(Boolean, default=False, server_default=false(), nullable=False)
    # Counts failed verification attempts so the OTP can be locked out before
    # its keyspace can be exhausted.
    attempt_count = Column(Integer, default=0, server_default="0", nullable=False)
    expires_at = Column(DateTime(timezone=True), nullable=False, index=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    user = relationship("User", back_populates="password_reset_tokens")


Index("ix_password_reset_user_active", PasswordResetToken.user_id, PasswordResetToken.is_used)
