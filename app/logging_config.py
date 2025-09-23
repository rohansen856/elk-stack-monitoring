import structlog
import logging
import logstash
import socket
from app.config import settings


def configure_logging():
    # Basic logging configuration
    logging.basicConfig(
        level=getattr(logging, settings.log_level.upper()),
        format="%(message)s",
    )

    # Add Logstash handler if ELK stack is enabled
    logger = logging.getLogger()

    # Try to add Logstash handler
    try:
        logstash_host = getattr(settings, 'logstash_host', 'logstash')
        logstash_port = getattr(settings, 'logstash_tcp_port', 5000)

        logstash_handler = logstash.TCPLogstashHandler(
            host=logstash_host,
            port=int(logstash_port),
            version=1
        )
        logstash_handler.setLevel(logging.INFO)
        logger.addHandler(logstash_handler)
    except Exception as e:
        # If Logstash is not available, continue with console logging
        print(f"Warning: Could not connect to Logstash: {e}")

    # Configure structlog
    processors = [
        structlog.stdlib.filter_by_level,
        structlog.stdlib.add_logger_name,
        structlog.stdlib.add_log_level,
        structlog.stdlib.PositionalArgumentsFormatter(),
        structlog.processors.TimeStamper(fmt="iso"),
        structlog.processors.StackInfoRenderer(),
        structlog.processors.format_exc_info,
    ]

    # Always use JSON renderer for ELK integration
    if hasattr(settings, 'elasticsearch_url') or settings.environment in ["production", "development"]:
        processors.append(structlog.processors.JSONRenderer())
    else:
        processors.append(structlog.dev.ConsoleRenderer())

    structlog.configure(
        processors=processors,
        context_class=dict,
        logger_factory=structlog.stdlib.LoggerFactory(),
        wrapper_class=structlog.stdlib.BoundLogger,
        cache_logger_on_first_use=True,
    )