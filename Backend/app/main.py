import os
from contextlib import asynccontextmanager

from fastapi import Depends, FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import text
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.util import get_remote_address
from slowapi.errors import RateLimitExceeded
from dotenv import load_dotenv

load_dotenv()

from app.api import routes
from app.db.database import Base, engine, get_db


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Local SQLite can self-bootstrap. Production databases are changed only by migrations.
    if engine.url.get_backend_name() == "sqlite":
        Base.metadata.create_all(bind=engine)
    with engine.connect() as connection:
        connection.execute(text("SELECT 1"))
    yield


API_VERSION = 3
IS_PRODUCTION = os.environ.get("ENVIRONMENT", "").strip().lower() == "production"
app = FastAPI(
    title="Cleave API",
    version=str(API_VERSION),
    lifespan=lifespan,
    docs_url=None if IS_PRODUCTION else "/docs",
    redoc_url=None if IS_PRODUCTION else "/redoc",
    openapi_url=None if IS_PRODUCTION else "/openapi.json",
)

limiter = Limiter(key_func=get_remote_address)
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)


allowed_origins = [
    origin.strip()
    for origin in os.environ.get("CORS_ALLOWED_ORIGINS", "").split(",")
    if origin.strip()
]
if allowed_origins:
    app.add_middleware(
        CORSMiddleware,
        allow_origins=allowed_origins,
        allow_credentials=True,
        allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE"],
        allow_headers=["Authorization", "Content-Type"],
    )

app.include_router(routes.router, prefix="/api")


@app.middleware("http")
async def add_security_headers(request, call_next):
    response = await call_next(request)
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["Referrer-Policy"] = "no-referrer"
    response.headers["Permissions-Policy"] = "camera=(), microphone=(), geolocation=()"
    if request.url.path.startswith("/api"):
        response.headers.setdefault("Cache-Control", "private, no-store")
    if request.headers.get("x-forwarded-proto", request.url.scheme) == "https":
        response.headers["Strict-Transport-Security"] = "max-age=31536000; includeSubDomains"
    return response

@app.get("/")
def read_root():
    return {"status": "ok", "message": "Cleave API is running"}


@app.get("/health")
def health(db: Session = Depends(get_db)):
    return database_readiness(db)


@app.get("/ready")
def ready(db: Session = Depends(get_db)):
    return database_readiness(db)


def database_readiness(db: Session):
    try:
        db.execute(text("SELECT 1"))
        # Readiness includes the release schema, not merely a reachable
        # database. This prevents Cloud Run from serving a new app against an
        # old migration state.
        db.execute(text(
            "SELECT aani_id, age_band, avatar_visibility, payment_visibility, display_name "
            "FROM profiles LIMIT 0"
        ))
        db.execute(text(
            "SELECT client_request_id, currency_code FROM receipts LIMIT 0"
        ))
        db.execute(text(
            "SELECT status, confirmed_at, reviewed_by FROM settlements LIMIT 0"
        ))
    except SQLAlchemyError as error:
        raise HTTPException(status_code=503, detail="Database or required migrations unavailable") from error
    return {"status": "ok", "api_version": API_VERSION}
