import numpy as np
from pathlib import Path

import sys
sys.path.append(str(Path(__file__).parent.parent.parent))

from src.extraction.frame_sampler import FrameSampler
from src.extraction.visual_embeddings import VisualEmbedder
from src.extraction.metadata_embeddings import MetadataEmbedder


class MultiModalFusion:
    def __init__(self, visual_weight: float = 0.7, metadata_weight: float = 0.3):
        self.visual_weight = visual_weight
        self.metadata_weight = metadata_weight
        
        self.frame_sampler = FrameSampler()
        self.visual_embedder = VisualEmbedder()
        self.metadata_embedder = MetadataEmbedder()
    
    def weighted_fusion(self, visual: np.ndarray, metadata: np.ndarray) -> np.ndarray:
        visual_dim = len(visual)
        metadata_dim = len(metadata)
        
        visual_padded = np.zeros(512)
        visual_padded[:visual_dim] = visual
        
        metadata_padded = np.zeros(64)
        metadata_padded[:metadata_dim] = metadata
        
        fused = (self.visual_weight * visual_padded) + (self.metadata_weight * metadata_padded)
        
        norm = np.linalg.norm(fused)
        if norm > 0:
            fused = fused / norm
        
        return fused
    
    def process_video(self, video_path: str, metadata: dict) -> np.ndarray:
        frames = self.frame_sampler.smart_sample(video_path)
        visual_embedding = self.visual_embedder.get_visual_embedding(frames)
        
        metadata_embedding = self.metadata_embedder.create_metadata_embedding(metadata)
        
        fused = self.weighted_fusion(visual_embedding, metadata_embedding)
        
        return fused
    
    def get_embedding_dimension(self) -> int:
        return 576
