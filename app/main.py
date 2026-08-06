import asyncio
from contextlib import asynccontextmanager

from fastapi import Depends, FastAPI, Request
from fastapi.responses import JSONResponse, PlainTextResponse
from fastapi.exceptions import RequestValidationError
from prometheus_client import generate_latest
from sqlalchemy.exc import SQLAlchemyError
from starlette.exceptions import HTTPException as StarletteHTTPException
import structlog
from slowapi.errors import RateLimitExceeded
from slowapi.middleware import SlowAPIMiddleware

from app.config import settings
from app.logging_config import configure_logging
from app.middleware import LoggingMiddleware, MetricsMiddleware, add_cors_middleware
from app.cache import cache
from app.database import engine
# Imported for their side effect: each registers its mapper on Base.metadata,
# which Alembic autogenerate and create_all depend on. Not unused.
from app.models.user import User  # noqa: F401
from app.models.todo import Todo  # noqa: F401
from app.models.password_reset import PasswordResetToken  # noqa: F401
from app.api.auth import get_current_active_user, verify_metrics_access
from app.api.users import router as users_router
from app.api.todos import router as todos_router
from app.api.security import router as security_router
from app.rate_limit import limiter
from app.services.es_client import ElasticsearchUnavailable, close_elasticsearch_client
from app.tasks import periodic_token_cleanup
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


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Startup/shutdown. Replaces the deprecated @app.on_event hooks and gives
    the async Redis and Elasticsearch clients a place to be closed cleanly."""
    logger.info("Starting Sentinel API", environment=settings.environment)
    cleanup_task = asyncio.create_task(periodic_token_cleanup())
    yield
    logger.info("Shutting down Sentinel API")
    cleanup_task.cancel()
    try:
        await cleanup_task
    except asyncio.CancelledError:
        pass
    await cache.close()
    await close_elasticsearch_client()


async def _rate_limit_handler(request: Request, exc: RateLimitExceeded):
    logger.warning(
        "Rate limit exceeded",
        path=request.url.path,
        client_ip=request.client.host if request.client else "unknown",
    )
    return JSONResponse(
        status_code=429,
        content={"detail": "Too many requests", "type": "rate_limit_exceeded"},
    )

app = FastAPI(
    title="Sentinel: ELK Stack Security Monitoring API",
    description="A production-grade security monitoring application with ELK stack integration",
    version="1.0.0",
    docs_url="/docs" if not settings.is_production else None,
    redoc_url="/redoc" if not settings.is_production else None,
    root_path="/backend",  # Tell FastAPI it's behind a reverse proxy at /backend
    lifespan=lifespan,
)

# Rate limiting (AUDIT SEC-011)
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_handler)
app.add_middleware(SlowAPIMiddleware)

add_cors_middleware(app)
app.add_middleware(LoggingMiddleware)
app.add_middleware(MetricsMiddleware)

app.include_router(users_router, prefix="/api/v1/users", tags=["users"])
app.include_router(todos_router, prefix="/api/v1/todos", tags=["todos"])
# Every security endpoint requires authentication. Previously this router was
# mounted with no dependency at all, leaving 14 endpoints - including four that
# write to Elasticsearch - open to anonymous callers. See AUDIT SEC-001.
app.include_router(
    security_router,
    prefix="/api/v1/security",
    tags=["security"],
    dependencies=[Depends(get_current_active_user)],
)


@app.exception_handler(ElasticsearchUnavailable)
async def elasticsearch_unavailable_handler(request: Request, exc: ElasticsearchUnavailable):
    """Surface detection failures instead of reporting an empty result.

    A detection endpoint that answers 200 {"threats": []} while its backing
    query is failing tells an operator they are safe when nobody is looking.
    See AUDIT FUNC-001.
    """
    logger.error(
        "Elasticsearch unavailable",
        error=str(exc),
        path=request.url.path,
        method=request.method,
    )
    return JSONResponse(
        status_code=503,
        content={
            "status": "degraded",
            "detail": "Threat detection is unavailable: the Elasticsearch query failed.",
            "type": "elasticsearch_unavailable",
        },
    )


# Exception handlers
app.add_exception_handler(TodoAppException, todo_app_exception_handler)
app.add_exception_handler(StarletteHTTPException, http_exception_handler)
app.add_exception_handler(RequestValidationError, validation_exception_handler)
app.add_exception_handler(SQLAlchemyError, sqlalchemy_exception_handler)
app.add_exception_handler(Exception, general_exception_handler)


@app.get("/health")
async def health_check():
    db_healthy = True
    try:
        # Context-managed: previously engine.connect() was never closed, leaking
        # a pooled connection on every probe. See AUDIT OPS-002.
        with engine.connect():
            pass
    except Exception:
        db_healthy = False

    redis_healthy = await cache.health_check()

    if db_healthy and redis_healthy:
        return {"status": "healthy", "database": "ok", "redis": "ok"}

    # Must be a failing status code: liveness/readiness probes test the status
    # code, so returning 200 here meant a broken pod was never restarted.
    return JSONResponse(
        status_code=503,
        content={
            "status": "unhealthy",
            "database": "ok" if db_healthy else "error",
            "redis": "ok" if redis_healthy else "error",
        },
    )


@app.get("/metrics", response_class=PlainTextResponse)
async def metrics(_: None = Depends(verify_metrics_access)):
    """Prometheus metrics. Authenticated - see AUDIT SEC-014."""
    return generate_latest()


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=8000)
