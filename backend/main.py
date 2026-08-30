"""Vercel FastAPI entrypoint.

The root module must not be named ``app.py`` because that shadows the
``app`` package imported below when Vercel loads the function.
"""

from app.main import app
