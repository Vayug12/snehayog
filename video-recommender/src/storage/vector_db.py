import os
import json
from typing import List, Dict, Any, Optional
from pathlib import Path
from datetime import datetime

import sys
sys.path.append(str(Path(__file__).parent.parent.parent))
from config.settings import PINECONE_API_KEY, PINECONE_INDEX_NAME, EMBEDDING_DIMENSION


class VectorDatabase:
    def __init__(self):
        self.index = None
        self._connect()
    
    def _connect(self):
        try:
            from pinecone import Pinecone, ServerlessSpec
            
            if not PINECONE_API_KEY:
                raise ValueError("PINECONE_API_KEY not set")
            
            pc = Pinecone(api_key=PINECONE_API_KEY)
            
            existing_indexes = [idx.name for idx in pc.list_indexes()]
            
            if PINECONE_INDEX_NAME not in existing_indexes:
                pc.create_index(
                    name=PINECONE_INDEX_NAME,
                    dimension=EMBEDDING_DIMENSION,
                    metric="cosine",
                    spec=ServerlessSpec(
                        cloud="aws",
                        region="us-east-1"
                    )
                )
            
            self.index = pc.Index(PINECONE_INDEX_NAME)
            print(f"Connected to Pinecone index: {PINECONE_INDEX_NAME}")
            
        except ImportError:
            raise ImportError("Pinecone not installed. Run: pip install pinecone-client")
    
    def add_embedding(self, video_id: str, embedding: np.ndarray, metadata: Optional[Dict[str, Any]] = None):
        vector = embedding.tolist()
        
        upsert_metadata = {
            "video_id": video_id,
            "created_at": datetime.now().isoformat()
        }
        
        if metadata:
            upsert_metadata.update(metadata)
        
        self.index.upsert(
            vectors=[(video_id, vector, upsert_metadata)]
        )
        print(f"Added embedding for video: {video_id}")
    
    def search(self, query_embedding: np.ndarray, top_k: int = 10, exclude_id: Optional[str] = None) -> List[Dict[str, Any]]:
        query_vector = query_embedding.tolist()
        
        results = self.index.query(
            vector=query_vector,
            top_k=top_k + 1 if exclude_id else top_k,
            include_metadata=True
        )
        
        recommendations = []
        for match in results.matches:
            if exclude_id and match.id == exclude_id:
                continue
            recommendations.append({
                "video_id": match.id,
                "score": match.score,
                "metadata": match.metadata
            })
        
        return recommendations[:top_k]
    
    def get_embedding(self, video_id: str) -> Optional[Dict[str, Any]]:
        results = self.index.fetch(ids=[video_id])
        
        if video_id in results.vectors:
            vector_data = results.vectors[video_id]
            return {
                "video_id": video_id,
                "embedding": np.array(vector_data.values),
                "metadata": vector_data.metadata
            }
        
        return None
    
    def delete_embedding(self, video_id: str):
        self.index.delete(ids=[video_id])
        print(f"Deleted embedding for video: {video_id}")
    
    def get_index_stats(self) -> Dict[str, Any]:
        stats = self.index.describe_index_stats()
        return {
            "total_vectors": stats.total_vector_count,
            "dimension": stats.dimension
        }
