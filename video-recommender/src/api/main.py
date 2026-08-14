from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent.parent))

from src.api.routes import router

app = FastAPI(
    title="Video Recommendation API",
    description="Video embedding and recommendation system",
    version="1.0.0"
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(router, prefix="/api/v1")


@app.get("/")
def root():
    return {"message": "Video Recommendation System API"}


@app.get("/health")
def health():
    return {"status": "healthy"}
