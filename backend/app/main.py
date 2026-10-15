"""Paywise backend (SPEC.md §9.2). Endpoints arrive in later build steps (§15.7)."""

from fastapi import FastAPI

from app import catalog  # noqa: F401  Loads and validates data/cards.json: a bad catalog stops startup (§15.3).

app = FastAPI(title="Paywise", version="0.1.0")


@app.get("/health")
def health() -> dict[str, bool]:
    return {"ok": True}
