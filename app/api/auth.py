import hashlib
import secrets
from datetime import datetime, timedelta, timezone
from typing import Optional

from jose import JWTError, jwt
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from sqlalchemy.orm import Session

from app.config import settings
from app.database import get_db
from app.crud.user import get_user_by_email
from app.schemas.user import TokenData

security = HTTPBearer()
# auto_error=False so an anonymous request reaches our own handler and can be
# answered with 401 rather than HTTPBearer's default 403.
optional_security = HTTPBearer(auto_error=False)


def _password_stamp(user) -> str:
    """Fingerprint of the user's current credential.

    Embedded in each token as `pwd_fp` and re-checked on every request, so
    changing a password invalidates every token issued before it. Derived from
    the stored hash rather than a timestamp column, so an out-of-band password
    change invalidates tokens too. The bcrypt hash itself never leaves the
    server - only a truncated digest of it.

    Previously there was no refresh, logout or revocation of any kind, so a
    stolen token outlived a password reset. See AUDIT SEC-012.
    """
    digest = hashlib.sha256(
        (user.hashed_password or "").encode("utf-8")
    ).hexdigest()
    return digest[:16]


def create_access_token(data: dict, expires_delta: Optional[timedelta] = None):
    to_encode = data.copy()
    now = datetime.now(timezone.utc)
    if expires_delta:
        expire = now + expires_delta
    else:
        expire = now + timedelta(minutes=settings.access_token_expire_minutes)
    to_encode.update({"exp": expire, "iat": now, "jti": secrets.token_urlsafe(16)})
    encoded_jwt = jwt.encode(to_encode, settings.secret_key, algorithm=settings.algorithm)
    return encoded_jwt


async def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(security),
    db: Session = Depends(get_db)
):
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Could not validate credentials",
        headers={"WWW-Authenticate": "Bearer"},
    )
    try:
        payload = jwt.decode(
            credentials.credentials, settings.secret_key, algorithms=[settings.algorithm]
        )
        email: str = payload.get("sub")
        if email is None:
            raise credentials_exception
        token_data = TokenData(email=email)
    except JWTError:
        raise credentials_exception

    user = get_user_by_email(db, email=token_data.email)
    if user is None:
        raise credentials_exception

    # Reject tokens minted before the user's most recent password change.
    if payload.get("pwd_fp") != _password_stamp(user):
        raise credentials_exception

    return user


async def get_current_active_user(current_user = Depends(get_current_user)):
    if not current_user.is_active:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN, detail="Inactive user"
        )
    return current_user


async def verify_metrics_access(
    credentials: Optional[HTTPAuthorizationCredentials] = Depends(optional_security),
    db: Session = Depends(get_db),
) -> None:
    """Guard /metrics.

    Accepts either a dedicated scrape token (``METRICS_TOKEN``, for Prometheus,
    which cannot perform a login flow) or a normal user JWT. Fails closed when
    neither is present. See AUDIT SEC-014.
    """
    unauthorized = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Not authenticated",
        headers={"WWW-Authenticate": "Bearer"},
    )
    if credentials is None:
        raise unauthorized

    token = credentials.credentials

    if settings.metrics_token and secrets.compare_digest(token, settings.metrics_token):
        return None

    try:
        payload = jwt.decode(token, settings.secret_key, algorithms=[settings.algorithm])
    except JWTError:
        raise unauthorized

    email = payload.get("sub")
    if email is None or get_user_by_email(db, email=email) is None:
        raise unauthorized
    return None
