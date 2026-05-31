"""Single source of truth for Elasticsearch connections.

Previously each service built its own client with different settings:
``security_logger`` authenticated, ``threat_detection`` did not, and
``alerting`` reached into ``threat_detector.es``.  Against a security-enabled
cluster that meant writes succeeded while every detection query returned 401 -
and the failures were swallowed, so detection silently reported "no threats".
See AUDIT/FINDINGS.md FUNC-001.
"""
from typing import Optional

import structlog
from elasticsearch import AsyncElasticsearch

from app.config import settings

logger = structlog.get_logger()


class ElasticsearchUnavailable(RuntimeError):
    """Raised when Elasticsearch cannot be reached or rejects our credentials.

    Callers must surface this rather than returning an empty result set: for a
    detection system, "query failed" and "nothing found" must never look alike.
    """


def raise_if_detection_broken(exc: Exception, context: str) -> None:
    """Decide whether an Elasticsearch error means 'broken' or merely 'no data'.

    This distinction matters: returning [] for a connection or auth failure is
    what made broken detection indistinguishable from a clean result
    (AUDIT FUNC-001). But a missing index just means nothing has been ingested
    yet, and reporting a fresh deployment as degraded forever would be its own
    false alarm.

    Raises ElasticsearchUnavailable for failures that mean detection cannot
    run; returns normally when the caller should treat the result as empty.
    """
    # Import locally: these live in different modules across client versions.
    from elasticsearch import (
        AuthenticationException,
        AuthorizationException,
        ConnectionError as ESConnectionError,
        ConnectionTimeout,
        NotFoundError,
    )

    if isinstance(exc, NotFoundError):
        logger.info(
            "Elasticsearch index not present yet; treating as no results",
            context=context,
        )
        return

    if isinstance(
        exc,
        (AuthenticationException, AuthorizationException, ESConnectionError, ConnectionTimeout),
    ):
        raise ElasticsearchUnavailable(f"{context}: {type(exc).__name__}") from exc

    # Unknown failure: fail loudly. For a detection system, an unexplained
    # error must never be presented to an operator as "no threats found".
    raise ElasticsearchUnavailable(f"{context}: {type(exc).__name__}") from exc


def build_elasticsearch_client() -> AsyncElasticsearch:
    """Build an authenticated Elasticsearch client from settings."""
    scheme = "https" if settings.elasticsearch_use_ssl else "http"
    host = f"{scheme}://{settings.elasticsearch_host}:{settings.elasticsearch_port}"

    kwargs = {}
    if settings.elasticsearch_password:
        kwargs["basic_auth"] = (
            settings.elasticsearch_username,
            settings.elasticsearch_password,
        )
    else:
        # Loud, because an unauthenticated client against a secured cluster is
        # exactly the defect that made threat detection inoperative.
        logger.warning(
            "Elasticsearch password is not configured; queries will fail against "
            "a security-enabled cluster",
            host=host,
        )

    return AsyncElasticsearch([host], **kwargs)


_client: Optional[AsyncElasticsearch] = None


def get_elasticsearch() -> AsyncElasticsearch:
    """Return the process-wide client, building it on first use."""
    global _client
    if _client is None:
        _client = build_elasticsearch_client()
    return _client


def reset_elasticsearch_client() -> None:
    """Drop the cached client (used by tests and on configuration reload)."""
    global _client
    _client = None


async def close_elasticsearch_client() -> None:
    """Close the shared client on application shutdown."""
    global _client
    if _client is not None:
        try:
            await _client.close()
        except Exception:  # pragma: no cover - best-effort shutdown
            pass
        _client = None
