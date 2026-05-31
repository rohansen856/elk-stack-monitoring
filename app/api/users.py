from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException, status, Request
from fastapi.security import OAuth2PasswordRequestForm
from sqlalchemy.orm import Session
import structlog

from app.database import get_db
from app.schemas.user import UserCreate, UserResponse, Token
from app.schemas.password_reset import PasswordResetRequest, PasswordResetVerify, PasswordResetResponse
from app.crud.user import get_user_by_email, get_user_by_username, create_user, authenticate_user, get_password_hash
from app.services.email_service import OTPLockedOut, send_password_reset_otp, verify_password_reset_otp
from app.api.auth import create_access_token, get_current_active_user, _password_stamp
from app.config import settings
from app.rate_limit import limiter
from app.services.security_logger import security_logger

logger = structlog.get_logger()
router = APIRouter()

# Deliberately identical for every outcome: a known address whose mail delivery
# failed used to return 500 while an unknown one returned 200, which is a clean
# account-enumeration oracle. See AUDIT SEC-007.
_RESET_REQUEST_RESPONSE = PasswordResetResponse(
    message="If the email exists in our system, you will receive a password reset code.",
    success=True,
)


@router.post("/register", response_model=UserResponse)
@limiter.limit("5/minute")
async def register_user(request: Request, user: UserCreate, db: Session = Depends(get_db)):
    db_user = get_user_by_email(db, email=user.email)
    if db_user:
        raise HTTPException(
            status_code=400,
            detail="Email already registered"
        )

    db_user = get_user_by_username(db, username=user.username)
    if db_user:
        raise HTTPException(
            status_code=400,
            detail="Username already taken"
        )

    db_user = create_user(db=db, user=user)
    logger.info("User created", user_id=db_user.id)
    return db_user


@router.post("/login", response_model=Token)
@limiter.limit("10/minute")
async def login_user(request: Request, form_data: OAuth2PasswordRequestForm = Depends(), db: Session = Depends(get_db)):
    client_ip = request.client.host if request.client else "unknown"
    user_agent = request.headers.get("user-agent", "unknown")

    user = authenticate_user(db, form_data.username, form_data.password)
    if not user:
        await security_logger.log_authentication_event(
            event_type="authentication_failure",
            email=form_data.username,
            source_ip=client_ip,
            user_agent=user_agent
        )

        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect email or password",
            headers={"WWW-Authenticate": "Bearer"},
        )

    await security_logger.log_authentication_event(
        event_type="authentication_success",
        email=user.email,
        user_id=str(user.id),
        source_ip=client_ip,
        user_agent=user_agent
    )

    access_token_expires = timedelta(minutes=settings.access_token_expire_minutes)
    access_token = create_access_token(
        data={"sub": user.email, "pwd_fp": _password_stamp(user)},
        expires_delta=access_token_expires,
    )
    logger.info("User logged in", user_id=user.id)
    return {"access_token": access_token, "token_type": "bearer"}


@router.get("/me", response_model=UserResponse)
async def read_users_me(current_user = Depends(get_current_active_user)):
    return current_user


@router.post("/forgot-password", response_model=PasswordResetResponse)
@limiter.limit("3/minute")
async def forgot_password(request: Request, reset_request: PasswordResetRequest, db: Session = Depends(get_db)):
    """Send a password reset OTP.

    Always returns the same response regardless of whether the address exists or
    whether delivery succeeded, so the endpoint cannot be used to enumerate
    accounts (AUDIT SEC-007).
    """
    user = get_user_by_email(db, email=reset_request.email)
    if not user:
        return _RESET_REQUEST_RESPONSE

    otp = await send_password_reset_otp(db, user)
    if otp:
        logger.info("Password reset OTP sent", user_id=user.id)
    else:
        # Logged for operators, never signalled to the caller.
        logger.error("Failed to send password reset OTP", user_id=user.id)

    return _RESET_REQUEST_RESPONSE


@router.post("/reset-password", response_model=PasswordResetResponse)
@limiter.limit("10/minute")
async def reset_password(request: Request, reset: PasswordResetVerify, db: Session = Depends(get_db)):
    """Verify an OTP and set a new password."""
    try:
        user = verify_password_reset_otp(db, reset.email, reset.otp)
    except OTPLockedOut:
        raise HTTPException(
            status_code=status.HTTP_423_LOCKED,
            detail="Too many invalid attempts. Request a new reset code.",
        )

    if not user:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid or expired OTP code"
        )

    user.hashed_password = get_password_hash(reset.new_password)
    # Invalidates every access token issued before this moment (AUDIT SEC-012).
    user.password_changed_at = datetime.now(timezone.utc)
    db.commit()

    logger.info("Password reset successful", user_id=user.id)
    return PasswordResetResponse(
        message="Password reset successful. You can now login with your new password.",
        success=True
    )
