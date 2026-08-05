from pydantic import BaseModel, EmailStr, Field


class PasswordResetRequest(BaseModel):
    email: EmailStr


class PasswordResetVerify(BaseModel):
    email: EmailStr
    otp: str
    # Minimum length enforced here; previously `new_password: str` was
    # completely unconstrained, so a one-character password was accepted.
    new_password: str = Field(..., min_length=12, max_length=128)


class PasswordResetResponse(BaseModel):
    message: str
    success: bool
