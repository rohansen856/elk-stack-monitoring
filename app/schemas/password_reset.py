from pydantic import BaseModel, EmailStr
from datetime import datetime
from typing import Optional


class PasswordResetRequest(BaseModel):
    email: EmailStr


class PasswordResetVerify(BaseModel):
    email: EmailStr
    otp: str
    new_password: str


class PasswordResetResponse(BaseModel):
    message: str
    success: bool


class PasswordResetTokenBase(BaseModel):
    user_id: int
    token: str
    expires_at: datetime
    is_used: bool


class PasswordResetToken(PasswordResetTokenBase):
    id: int
    created_at: datetime

    class Config:
        from_attributes = True