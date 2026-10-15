"""Paywise backend (SPEC.md §9.2). Endpoints arrive in later build steps (§15.7)."""

from fastapi import FastAPI

app = FastAPI(title="Paywise", version="0.1.0")


@app.get("/health")
def health() -> dict[str, bool]:
    return {"ok": True}
