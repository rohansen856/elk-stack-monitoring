from fastapi import HTTPException, Request
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


async def validation_exception_handler(request: Request, exc: RequestValidationError):
    logger.error(
        "Validation error",
        errors=exc.errors(),
        path=request.url.path,
        method=request.method
    )
    return JSONResponse(
        status_code=422,
        content={"detail": exc.errors(), "type": "validation_error"}
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