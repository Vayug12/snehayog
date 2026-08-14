import os
from pathlib import Path

# Base paths
BASE_DIR = Path(__file__).parent.parent
DATA_DIR = BASE_DIR / "data"

# Video Processing
VIDEO_DIR = str(DATA_DIR / "videos")
MAX_VIDEO_SIZE_MB = 500
FRAME_SAMPLE_COUNT = 8

# Models
CLIP_MODEL = "ViT-B/32"

# Vector Database (Pinecone)
PINECONE_API_KEY = os.getenv("PINECONE_API_KEY", "")
PINECONE_INDEX_NAME = "video-recommendations"
EMBEDDING_DIMENSION = 576

# Cleanup
AUTO_CLEANUP = True
CLEANUP_AFTER_EMBEDDING = True
MIN_FREE_SPACE_GB = 1.0

# API
API_HOST = "0.0.0.0"
API_PORT = 8000

# Create directories if they don't exist
os.makedirs(VIDEO_DIR, exist_ok=True)
os.makedirs(str(DATA_DIR / "embeddings"), exist_ok=True)
os.makedirs(str(DATA_DIR / "metadata"), exist_ok=True)
