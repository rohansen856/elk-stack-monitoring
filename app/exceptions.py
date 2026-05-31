from fastapi import Request
from fastapi.responses import JSONResponse
from fastapi.exceptions import RequestValidationError
from sqlalchemy.exc import SQLAlchemyError
from starlette.exceptions import HTTPException as StarletteHTTPException
import structlog

logger = structlog.get_logger()


class TodoAppException(Exception):
    def __init__(self, detail: str, status_code: int = 500):
        self.detail = detail
        self.status_code = status_code


class UserNotFoundError(TodoAppException):
    def __init__(self, detail: str = "User not found"):
        super().__init__(detail, 404)


class TodoNotFoundError(TodoAppException):
    def __init__(self, detail: str = "Todo not found"):
        super().__init__(detail, 404)


class AuthenticationError(TodoAppException):
    def __init__(self, detail: str = "Authentication failed"):
        super().__init__(detail, 401)


class AuthorizationError(TodoAppException):
    def __init__(self, detail: str = "Not authorized"):
        super().__init__(detail, 403)


class ValidationError(TodoAppException):
    def __init__(self, detail: str = "Validation error"):
        super().__init__(detail, 422)


async def todo_app_exception_handler(request: Request, exc: TodoAppException):
    logger.error(
        "Application error",
        error=exc.detail,
        status_code=exc.status_code,
        path=request.url.path,
        method=request.method
    )
    return JSONResponse(
        status_code=exc.status_code,
        content={"detail": exc.detail, "type": "application_error"}
    )


async def http_exception_handler(request: Request, exc: StarletteHTTPException):
    logger.error(
        "HTTP error",
        error=exc.detail,
        status_code=exc.status_code,
        path=request.url.path,
        method=request.method
    )
    return JSONResponse(
        status_code=exc.status_code,
        content={"detail": exc.detail, "type": "http_error"}
    )


def _sanitize_validation_errors(errors):
    """Strip the rejected value from pydantic's error payload.

    pydantic v2 includes an `input` key echoing whatever was submitted. That
    payload is both returned to the caller and shipped to Logstash, so a
    type-invalid password, OTP or new_password ended up in Elasticsearch in
    cleartext. Location and message are kept; the value is not.
    See AUDIT SEC-015.
    """
    sanitized = []
    for err in errors:
        sanitized.append({
            "type": err.get("type"),
            "loc": err.get("loc"),
            "msg": err.get("msg"),
        })
    return sanitized


async def validation_exception_handler(request: Request, exc: RequestValidationError):
    safe_errors = _sanitize_validation_errors(exc.errors())
    logger.error(
        "Validation error",
        errors=safe_errors,
        path=request.url.path,
        method=request.method
    )
    return JSONResponse(
        status_code=422,
        content={"detail": safe_errors, "type": "validation_error"}
    )


async def sqlalchemy_exception_handler(request: Request, exc: SQLAlchemyError):
    logger.error(
        "Database error",
        error=str(exc),
        path=request.url.path,
        method=request.method
    )
    return JSONResponse(
        status_code=500,
        content={"detail": "Internal server error", "type": "database_error"}
    )


async def general_exception_handler(request: Request, exc: Exception):
    logger.error(
        "Unexpected error",
        error=str(exc),
        error_type=type(exc).__name__,
        path=request.url.path,
        method=request.method
    )
    return JSONResponse(
        status_code=500,
        content={"detail": "Internal server error", "type": "unexpected_error"}
    )