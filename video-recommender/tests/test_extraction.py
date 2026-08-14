import pytest
import numpy as np
from pathlib import Path

import sys
sys.path.insert(0, str(Path(__file__).parent.parent))

from src.extraction.metadata_embeddings import MetadataEmbedder


def test_metadata_embedder():
    embedder = MetadataEmbedder()
    
    metadata = {
        "duration": 30.0,
        "fps": 30.0,
        "width": 1920,
        "height": 1080,
        "file_size_mb": 50.0
    }
    
    embedding = embedder.create_metadata_embedding(metadata)
    
    assert embedding.shape == (6,)
    assert np.all(embedding >= 0)
    assert np.all(embedding <= 1)
