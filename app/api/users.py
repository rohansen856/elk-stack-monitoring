from datetime import timedelta
from fastapi import APIRouter, Depends, HTTPException, status, Request
from fastapi.security import OAuth2PasswordRequestForm
from sqlalchemy.orm import Session
from app.database import get_db
from app.schemas.user import UserCreate, UserResponse, UserLogin, Token
from app.schemas.password_reset import PasswordResetRequest, PasswordResetVerify, PasswordResetResponse
from app.crud.user import get_user_by_email, get_user_by_username, create_user, authenticate_user, get_password_hash
from app.services.email_service import send_password_reset_otp, verify_password_reset_otp
from app.api.auth import create_access_token, get_current_active_user
from app.config import settings
from app.services.security_logger import security_logger
import structlog

logger = structlog.get_logger()
router = APIRouter()


@router.post("/register", response_model=UserResponse)
async def register_user(user: UserCreate, db: Session = Depends(get_db)):
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
    logger.info("User created", user_id=db_user.id, email=db_user.email)
    return db_user


@router.post("/login", response_model=Token)
async def login_user(request: Request, form_data: OAuth2PasswordRequestForm = Depends(), db: Session = Depends(get_db)):
    # Get client IP
    client_ip = request.client.host if request.client else "unknown"
    user_agent = request.headers.get("user-agent", "unknown")

    user = authenticate_user(db, form_data.username, form_data.password)
    if not user:
        # Log failed authentication
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

    # Log successful authentication
    await security_logger.log_authentication_event(
        event_type="authentication_success",
        email=user.email,
        user_id=str(user.id),
        source_ip=client_ip,
        user_agent=user_agent
    )

    access_token_expires = timedelta(minutes=settings.access_token_expire_minutes)
    access_token = create_access_token(
        data={"sub": user.email}, expires_delta=access_token_expires
    )
    logger.info("User logged in", user_id=user.id, email=user.email)
    return {"access_token": access_token, "token_type": "bearer"}


@router.get("/me", response_model=UserResponse)
async def read_users_me(current_user = Depends(get_current_active_user)):
    return current_user


@router.post("/forgot-password", response_model=PasswordResetResponse)
async def forgot_password(request: PasswordResetRequest, db: Session = Depends(get_db)):
    """Send password reset OTP to user's email"""
    user = get_user_by_email(db, email=request.email)
    if not user:
        # Don't reveal if email exists or not for security
        return PasswordResetResponse(
            message="If the email exists in our system, you will receive a password reset code.",
            success=True
        )

    # Send OTP
    otp = send_password_reset_otp(db, user)
    if otp:
        logger.info("Password reset OTP sent", user_id=user.id, email=user.email)
        return PasswordResetResponse(
            message="If the email exists in our system, you will receive a password reset code.",
            success=True
        )
    else:
        logger.error("Failed to send password reset OTP", user_id=user.id, email=user.email)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to send password reset email. Please try again later."
        )


@router.post("/reset-password", response_model=PasswordResetResponse)
async def reset_password(request: PasswordResetVerify, db: Session = Depends(get_db)):
    """Verify OTP and reset password"""
    user = verify_password_reset_otp(db, request.email, request.otp)
    if not user:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid or expired OTP code"
        )

    # Update user's password
    hashed_password = get_password_hash(request.new_password)
    user.hashed_password = hashed_password
    db.commit()

    logger.info("Password reset successful", user_id=user.id, email=user.email)
    return PasswordResetResponse(
        message="Password reset successful. You can now login with your new password.",
        success=True
    )