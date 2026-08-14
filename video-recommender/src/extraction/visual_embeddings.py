import numpy as np
import torch
from PIL import Image
from typing import List, Optional
from pathlib import Path

import sys
sys.path.append(str(Path(__file__).parent.parent.parent))
from config.settings import CLIP_MODEL


class VisualEmbedder:
    def __init__(self, model_name: str = CLIP_MODEL):
        self.model_name = model_name
        self.model = None
        self.preprocess = None
        self.device = "cuda" if torch.cuda.is_available() else "cpu"
        self._load_model()
    
    def _load_model(self):
        try:
            import clip
            
            print(f"Loading CLIP model: {self.model_name}")
            self.model, self.preprocess = clip.load(self.model_name, device=self.device)
            self.model.eval()
            print(f"CLIP model loaded on {self.device}")
            
        except ImportError:
            raise ImportError("CLIP not installed. Run: pip install clip @ git+https://github.com/openai/CLIP.git")
    
    def encode_frame(self, frame: np.ndarray) -> np.ndarray:
        pil_image = Image.fromarray(frame)
        preprocessed = self.preprocess(pil_image).unsqueeze(0).to(self.device)
        
        with torch.no_grad():
            embedding = self.model.encode_image(preprocessed)
        
        embedding = embedding.cpu().numpy().flatten()
        embedding = embedding / np.linalg.norm(embedding)
        
        return embedding
    
    def encode_frames(self, frames: List[np.ndarray]) -> np.ndarray:
        embeddings = []
        for frame in frames:
            embedding = self.encode_frame(frame)
            embeddings.append(embedding)
        return np.array(embeddings)
    
    def aggregate_embeddings(self, embeddings: np.ndarray, method: str = "mean") -> np.ndarray:
        if method == "mean":
            aggregated = np.mean(embeddings, axis=0)
        elif method == "max":
            aggregated = np.max(embeddings, axis=0)
        elif method == "weighted":
            weights = np.linspace(0.5, 1.0, len(embeddings))
            weights = weights / weights.sum()
            aggregated = np.average(embeddings, axis=0, weights=weights)
        else:
            raise ValueError(f"Unknown aggregation method: {method}")
        
        aggregated = aggregated / np.linalg.norm(aggregated)
        return aggregated
    
    def get_visual_embedding(self, frames: List[np.ndarray], aggregation: str = "mean") -> np.ndarray:
        embeddings = self.encode_frames(frames)
        return self.aggregate_embeddings(embeddings, method=aggregation)
    
    def get_embedding_dimension(self) -> int:
        return 512
