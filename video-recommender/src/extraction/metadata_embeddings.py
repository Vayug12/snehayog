import numpy as np
from typing import Dict, Any


class MetadataEmbedder:
    def __init__(self):
        self.feature_names = [
            "duration", "fps", "width", "height", 
            "file_size_mb", "aspect_ratio"
        ]
    
    def create_metadata_embedding(self, metadata: Dict[str, Any]) -> np.ndarray:
        duration = metadata.get("duration", 0)
        fps = metadata.get("fps", 30)
        width = metadata.get("width", 0)
        height = metadata.get("height", 0)
        file_size = metadata.get("file_size_mb", 0)
        
        aspect_ratio = width / height if height > 0 else 1.0
        
        features = np.array([
            duration,
            fps,
            width,
            height,
            file_size,
            aspect_ratio
        ], dtype=np.float32)
        
        normalized = self.normalize_features(features)
        return normalized
    
    def normalize_features(self, features: np.ndarray) -> np.ndarray:
        min_vals = np.array([0, 10, 320, 240, 0.1, 0.5], dtype=np.float32)
        max_vals = np.array([600, 60, 3840, 2160, 500, 2.5], dtype=np.float32)
        
        normalized = (features - min_vals) / (max_vals - min_vals + 1e-8)
        normalized = np.clip(normalized, 0, 1)
        
        return normalized
    
    def get_embedding_dimension(self) -> int:
        return 6
