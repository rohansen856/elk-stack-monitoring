from fastapi import FastAPI
from fastapi.responses import PlainTextResponse
from fastapi.exceptions import RequestValidationError
from prometheus_client import generate_latest
from sqlalchemy.exc import SQLAlchemyError
from starlette.exceptions import HTTPException as StarletteHTTPException
import structlog

from app.config import settings
from app.logging_config import configure_logging
from app.middleware import LoggingMiddleware, MetricsMiddleware, add_cors_middleware
from app.cache import cache
from app.database import engine
from app.models.user import User
from app.models.todo import Todo
from app.models.password_reset import PasswordResetToken
from app.api.users import router as users_router
from app.api.todos import router as todos_router
from app.api.security import router as security_router  
from app.exceptions import (
    TodoAppException,
    todo_app_exception_handler,
    http_exception_handler,
    validation_exception_handler,
    sqlalchemy_exception_handler,
    general_exception_handler
)

configure_logging()
logger = structlog.get_logger()

app = FastAPI(
    title="ELK Stack Security Monitoring API",
    description="A production-grade security monitoring application with ELK stack integration",
    version="1.0.0",
    docs_url="/docs" if settings.environment != "production" else None,
    redoc_url="/redoc" if settings.environment != "production" else None,
)

add_cors_middleware(app)
app.add_middleware(LoggingMiddleware)
app.add_middleware(MetricsMiddleware)

app.include_router(users_router, prefix="/api/v1/users", tags=["users"])
app.include_router(todos_router, prefix="/api/v1/todos", tags=["todos"])
app.include_router(security_router, prefix="/api/v1/security", tags=["security"]) 

# Exception handlers
app.add_exception_handler(TodoAppException, todo_app_exception_handler)
app.add_exception_handler(StarletteHTTPException, http_exception_handler)
app.add_exception_handler(RequestValidationError, validation_exception_handler)
app.add_exception_handler(SQLAlchemyError, sqlalchemy_exception_handler)
app.add_exception_handler(Exception, general_exception_handler)


@app.on_event("startup")
async def startup_event():
    logger.info("Starting Todo API", environment=settings.environment)


@app.on_event("shutdown")
async def shutdown_event():
    logger.info("Shutting down Todo API")


@app.get("/health")
async def health_check():
    db_healthy = True
    try:
        engine.connect()
    except Exception:
        db_healthy = False

    redis_healthy = cache.health_check()

    if db_healthy and redis_healthy:
        return {"status": "healthy", "database": "ok", "redis": "ok"}
    else:
        return {
            "status": "unhealthy",
            "database": "ok" if db_healthy else "error",
            "redis": "ok" if redis_healthy else "error"
        }


@app.get("/metrics", response_class=PlainTextResponse)
async def metrics():
    return generate_latest()


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)