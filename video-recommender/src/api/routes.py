from fastapi import APIRouter, HTTPException
from typing import Optional

import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent.parent))

from src.storage.models import (
    ProcessVideoRequest, RecommendationRequest,
    RecommendationResponse, HealthResponse
)
from src.ingestion.downloader import VideoDownloader
from src.ingestion.metadata import MetadataExtractor
from src.extraction.fusion import MultiModalFusion
from src.storage.vector_db import VectorDatabase
from src.recommendation.engine import RecommendationEngine
from src.cleanup.cleanup import CleanupManager

router = APIRouter()

downloader = VideoDownloader()
metadata_extractor = MetadataExtractor()
fusion = MultiModalFusion()
vector_db = VectorDatabase()
recommendation_engine = RecommendationEngine(vector_db)
cleanup = CleanupManager()


@router.post("/process-video")
async def process_video(request: ProcessVideoRequest):
    try:
        video_id = downloader.generate_video_id()
        video_path = downloader.download_from_cdn(request.video_url, video_id)
        
        metadata = metadata_extractor.extract_and_save(video_path, video_id)
        
        embedding = fusion.process_video(video_path, metadata)
        
        vector_db.add_embedding(video_id, embedding, metadata)
        
        cleanup.cleanup_after_processing(video_path, f"data/frames/{video_id}")
        
        return {
            "video_id": video_id,
            "status": "processed",
            "duration": metadata["duration"]
        }
        
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/recommend/{video_id}")
async def get_recommendations(video_id: str, top_k: int = 10):
    try:
        recommendations = recommendation_engine.get_similar_videos(video_id, top_k)
        
        return {
            "video_id": video_id,
            "recommendations": recommendations
        }
        
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/similar")
async def get_similar(request: RecommendationRequest):
    try:
        recommendations = recommendation_engine.get_similar_videos(
            request.video_id, 
            request.top_k
        )
        
        return {
            "video_id": request.video_id,
            "similar_videos": recommendations
        }
        
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/health")
async def health():
    try:
        stats = vector_db.get_index_stats()
        disk_usage = cleanup.get_disk_usage()
        
        return {
            "status": "healthy",
            "videos_processed": stats.get("total_vectors", 0),
            "disk_usage": disk_usage
        }
        
    except Exception as e:
        return {
            "status": "unhealthy",
            "error": str(e)
        }
