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


app = FastAPI(title="Cleave API", lifespan=lifespan)

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
        allow_methods=["GET", "POST", "PATCH", "DELETE"],
        allow_headers=["Authorization", "Content-Type"],
    )

app.include_router(routes.router, prefix="/api")

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
    except SQLAlchemyError as error:
        raise HTTPException(status_code=503, detail="Database unavailable") from error
    return {"status": "ok"}
