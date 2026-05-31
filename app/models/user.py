from sqlalchemy import Column, Integer, String, DateTime, Boolean, true
from sqlalchemy.sql import func
from sqlalchemy.orm import relationship
from app.database import Base


class User(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True)
    email = Column(String(255), unique=True, index=True, nullable=False)
    username = Column(String(50), unique=True, index=True, nullable=False)
    hashed_password = Column(String(255), nullable=False)
    is_active = Column(Boolean, default=True, server_default=true(), nullable=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())
    # Stamped into every issued JWT as `pwd_ts`; changing a password moves this
    # forward and so invalidates every previously issued token (AUDIT SEC-012).
    password_changed_at = Column(DateTime(timezone=True), server_default=func.now())

    todos = relationship("Todo", back_populates="owner", cascade="all, delete-orphan")
    password_reset_tokens = relationship("PasswordResetToken", back_populates="user", cascade="all, delete-orphan")
