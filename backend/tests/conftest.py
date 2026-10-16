"""Shared test setup: every test starts with an empty rate-limit window.

RateLimit (app/middleware.py) limits every request that can carry a body, on every route, and the
limiter is module state; without a reset, one file's requests would use up the next file's window.
"""

import pytest

from app import middleware


@pytest.fixture(autouse=True)
def fresh_rate_limit_window():
    middleware.LIMITER.reset()
    yield
    middleware.LIMITER.reset()
