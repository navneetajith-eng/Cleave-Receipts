from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.api import routes
from app.db.database import engine, Base

from contextlib import asynccontextmanager

@asynccontextmanager
async def lifespan(app: FastAPI):
    # Create database tables on startup
    try:
        Base.metadata.create_all(bind=engine)
        print("Successfully connected to the database and created tables.")
    except Exception as e:
        print(f"Warning: Could not connect to database on startup: {e}")
    yield
app = FastAPI(title="Fidelity API", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(routes.router, prefix="/api")

@app.get("/")
def read_root():
    return {"status": "ok", "message": "Fidelity API is running"}
