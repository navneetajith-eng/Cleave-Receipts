from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.api import routes
from app.db.database import engine, Base

# Create database tables
Base.metadata.create_all(bind=engine)

app = FastAPI(title="Fidelity API")

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
