from pydantic import BaseModel
from typing import Optional, Dict, Any


class VideoMetadata(BaseModel):
    video_id: str
    video_path: str
    duration: float
    fps: float
    width: int
    height: int
    file_size_mb: float
    codec: Optional[int] = None


class ProcessVideoRequest(BaseModel):
    video_url: str


class RecommendationRequest(BaseModel):
    video_id: str
    top_k: int = 10


class RecommendationResponse(BaseModel):
    video_id: str
    recommendations: list


class HealthResponse(BaseModel):
    status: str
    videos_processed: int
    index_stats: Dict[str, Any]
