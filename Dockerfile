# Build stage: compilers live here and are discarded.
FROM python:3.12-slim AS builder

WORKDIR /app

RUN apt-get update \
    && apt-get install -y --no-install-recommends gcc libpq-dev \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt


# Runtime stage: no compiler, non-root user.
FROM python:3.12-slim

WORKDIR /app

RUN apt-get update \
    && apt-get install -y --no-install-recommends libpq5 curl \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --system --gid 1001 sentinel \
    && useradd --system --uid 1001 --gid sentinel --create-home sentinel

COPY --from=builder /install /usr/local
COPY --chown=sentinel:sentinel . .

# Previously the image ran as root with gcc retained. See AUDIT SEC-005.
USER sentinel

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
    CMD curl -fsS http://localhost:8000/health || exit 1

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
