"""Application-layer rate limiting.

There was previously no rate limiting anywhere in the application, and the only
nginx zone intended for auth endpoints (`auth_limit`) was declared but never
applied to any location. A measured 50 failed logins and 60 wrong OTP guesses
were all processed without a single 429. See AUDIT SEC-011 / SEC-003.

nginx limits remain useful as a first line, but they are bypassable because
docker-compose publishes the backend directly on port 8000, so the limit has to
exist here too.
"""
from slowapi import Limiter
from slowapi.util import get_remote_address

limiter = Limiter(key_func=get_remote_address, headers_enabled=False)
