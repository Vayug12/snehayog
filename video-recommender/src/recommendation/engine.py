from typing import List, Dict, Any, Optional
from pathlib import Path

import sys
sys.path.append(str(Path(__file__).parent.parent.parent))

from src.storage.vector_db import VectorDatabase


class RecommendationEngine:
    def __init__(self, vector_db: VectorDatabase):
        self.db = vector_db
    
    def get_similar_videos(self, video_id: str, top_k: int = 10) -> List[Dict[str, Any]]:
        video_data = self.db.get_embedding(video_id)
        
        if video_data is None:
            raise ValueError(f"Video not found: {video_id}")
        
        recommendations = self.db.search(
            query_embedding=video_data["embedding"],
            top_k=top_k,
            exclude_id=video_id
        )
        
        return recommendations
    
    def get_recommendations_by_embedding(self, embedding, top_k: int = 10) -> List[Dict[str, Any]]:
        recommendations = self.db.search(
            query_embedding=embedding,
            top_k=top_k
        )
        
        return recommendations
