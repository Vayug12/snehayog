# Video Recommendation System - Complete Implementation Plan

## Goal
Build a video embedding pipeline that processes videos from Cloudflare CDN, generates multi-modal embeddings, and stores them in a vector database for future recommendation use cases.

---

## System Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    VIDEO RECOMMENDATION SYSTEM           │
├─────────────────────────────────────────────────────────┤
│                                                          │
│  ┌──────────┐    ┌──────────┐    ┌──────────┐          │
│  │ Cloudflare│───▶│ Ingestion│───▶│ Feature  │          │
│  │   CDN    │    │ Pipeline │    │ Extraction│          │
│  └──────────┘    └──────────┘    └──────────┘          │
│                                      │                  │
│                          ┌───────────┴───────────┐      │
│                          ▼                       ▼      │
│                    ┌──────────┐            ┌──────────┐  │
│                    │  Visual  │            │ Metadata │  │
│                    │Embeddings│            │   Data   │  │
│                    └──────────┘            └──────────┘  │
│                          │                       │      │
│                          └───────────┬───────────┘      │
│                                      ▼                  │
│                              ┌──────────────┐           │
│                              │   Vector     │           │
│                              │   Database   │           │
│                              └──────────────┘           │
│                                      │                  │
│                                      ▼                  │
│                              ┌──────────────┐           │
│                              │Recommendation│           │
│                              │    Engine    │           │
│                              └──────────────┘           │
└─────────────────────────────────────────────────────────┘
```

---

## Tech Stack

### Core Technologies
- **Language:** Python 3.10+
- **Video Processing:** OpenCV, FFmpeg, PySceneDetect
- **Visual Embeddings:** CLIP (OpenAI, local)
- **Vector Database:** FAISS (Facebook AI Similarity Search)
- **API Framework:** FastAPI
- **Task Queue:** Celery + Redis (optional for async)

### Models Used

| Component | Model | Size | RAM Usage |
|-----------|-------|------|-----------|
| Visual | CLIP ViT-B/32 | 350MB | 400MB |
| Scene Detection | PySceneDetect | 50MB | 100MB |

---

## Resource Requirements

### Minimum Requirements
- **RAM:** 4GB (6GB recommended)
- **Storage:** 4GB free space (with auto-cleanup)
- **CPU:** 4+ cores recommended
- **Internet:** Required for video download

### Processing Specs (8GB RAM)
| Task | RAM | Time (per video) |
|------|-----|------------------|
| Download | 100MB | 10-30 sec |
| Scene Detection | 200MB | 5-10 sec |
| Frame Extraction | 300MB | 3-5 sec |
| CLIP Encoding | 400MB | 5-10 sec |
| FAISS Storage | 200MB | <1 sec |
| **Total** | **~1.2GB** | **30-90 sec** |

---

## File Structure

```
video-recommender/
├── config/
│   ├── __init__.py
│   └── settings.py
├── src/
│   ├── __init__.py
│   ├── ingestion/
│   │   ├── __init__.py
│   │   ├── downloader.py
│   │   └── metadata.py
│   ├── extraction/
│   │   ├── __init__.py
│   │   ├── frame_sampler.py
│   │   ├── visual_embeddings.py
│   │   └── fusion.py
│   ├── storage/
│   │   ├── __init__.py
│   │   ├── vector_db.py
│   │   └── models.py
│   ├── cleanup/
│   │   ├── __init__.py
│   │   └── cleanup.py
│   ├── recommendation/
│   │   ├── __init__.py
│   │   ├── engine.py
│   │   └── ranker.py
│   └── api/
│       ├── __init__.py
│       ├── main.py
│       └── routes.py
├── data/
│   ├── videos/
│   ├── embeddings/
│   └── metadata/
├── models/
│   ├── clip/
│   └── sentence_transformers/
├── tests/
│   ├── test_ingestion.py
│   ├── test_extraction.py
│   └── test_api.py
├── requirements.txt
├── setup.py
├── main.py
└── README.md
```

---

## Implementation Phases

### Phase 1: Project Setup & Ingestion Pipeline (Day 1-2)

**Objective:** Set up project structure and video download pipeline

**Tasks:**
1. Initialize Python project with virtual environment
2. Install dependencies (requirements.txt)
3. Create configuration module (settings.py)
4. Implement video downloader (async/batch)
5. Implement metadata extractor
6. Create storage directories

**Files to Create:**
- `config/settings.py`
- `src/ingestion/downloader.py`
- `src/ingestion/metadata.py`
- `requirements.txt`

**Key Code Components:**
```python
# downloader.py
class VideoDownloader:
    def download_from_cdn(url: str, output_path: str) -> str
    def download_batch(urls: List[str]) -> List[str]

# metadata.py
class MetadataExtractor:
    def extract(video_path: str) -> dict
    # Returns: duration, resolution, fps, codec, etc.
```

---

### Phase 2: Frame Extraction & Scene Detection (Day 3-4)

**Objective:** Extract key frames from videos using intelligent sampling

**Tasks:**
1. Implement scene detection using PySceneDetect
2. Create smart frame sampler (5-10 frames per video)
3. Implement frame preprocessing (resize, normalize)
4. Add fallback sampling (if scene detection fails)

**Files to Create:**
- `src/extraction/frame_sampler.py`

**Key Code Components:**
```python
# frame_sampler.py
class FrameSampler:
    def detect_scenes(video_path: str) -> List[Tuple[float, float]]
    def smart_sample(video_path: str, num_frames: int = 8) -> List[np.ndarray]
    def get_timestamps(video_path: str) -> List[float]
```

**Sampling Strategy:**
```
Video: [====|====|====|====|====|====|====]
        ↑    ↑         ↑         ↑    ↑
      Start 25%     Middle     75%  End
      (Light)    (Heavy)    (Light)

Total: 5-10 key frames per video
```

---

### Phase 3: Visual Embeddings with CLIP (Day 5-6)

**Objective:** Generate visual embeddings from sampled frames

**Tasks:**
1. Set up CLIP model (ViT-B/32)
2. Implement frame encoding
3. Create embedding aggregation (multiple frames → single vector)
4. Add normalization

**Files to Create:**
- `src/extraction/visual_embeddings.py`

**Key Code Components:**
```python
# visual_embeddings.py
class VisualEmbedder:
    def __init__(self):
        self.model = clip.load_model("ViT-B/32")
    
    def encode_frames(self, frames: List[np.ndarray]) -> np.ndarray
    def aggregate_embeddings(self, embeddings: List[np.ndarray]) -> np.ndarray
    def get_visual_embedding(self, video_path: str) -> np.ndarray
```

**Output:** 512-dimensional vector per video

---

### Phase 4: Metadata Embeddings (Day 7-8)

**Objective:** Create metadata embeddings from video properties (duration, resolution, codec, etc.)

**Tasks:**
1. Extract video metadata (duration, resolution, fps, codec)
2. Create metadata embedding vector
3. Normalize metadata features

**Files to Create:**
- `src/extraction/metadata_embeddings.py`

**Key Code Components:**
```python
# metadata_embeddings.py
class MetadataEmbedder:
    def create_metadata_embedding(self, metadata: dict) -> np.ndarray
    def normalize_features(self, features: np.ndarray) -> np.ndarray
```

**Output:** 64-dimensional vector per video

---

### Phase 5: Multi-Modal Fusion (Day 9)

**Objective:** Combine visual and metadata embeddings into unified vector

**Tasks:**
1. Implement fusion strategies (concatenation, weighted average)
2. Create final embedding generation pipeline
3. Add dimensionality reduction (optional)

**Files to Create:**
- `src/extraction/fusion.py`

**Key Code Components:**
```python
# fusion.py
class MultiModalFusion:
    def weighted_fusion(self, visual: np.ndarray, metadata: np.ndarray) -> np.ndarray
    def process_video(self, video_path: str) -> np.ndarray  # Main entry point
```

**Fusion Strategy:**
```python
final_embedding = weighted_combine(
    visual_embedding,   # 70% weight (512 dims)
    metadata_embedding  # 30% weight (64 dims)
)
# Output: 576-dimensional unified vector
```

---

### Phase 6: Vector Database with FAISS (Day 10-11)

**Objective:** Store embeddings and enable similarity search

**Tasks:**
1. Set up FAISS index (IndexFlatIP for cosine similarity)
2. Implement embedding storage
3. Create similarity search function
4. Add persistence (save/load index)
5. Implement metadata storage (video_id → embedding mapping)

**Files to Create:**
- `src/storage/vector_db.py`
- `src/storage/models.py`

**Key Code Components:**
```python
# vector_db.py
class VectorDatabase:
    def __init__(self, dimension: int = 576):
        self.index = faiss.IndexFlatIP(dimension)
        self.video_ids = []
    
    def add_embedding(self, video_id: str, embedding: np.ndarray)
    def search(self, query_embedding: np.ndarray, top_k: int = 10) -> List[str]
    def save(self, path: str)
    def load(self, path: str)
```

**Storage:**
- FAISS index file: `data/embeddings/faiss_index.bin`
- Metadata JSON: `data/embeddings/metadata.json`

---

### Phase 7: Recommendation Engine (Day 12)

**Objective:** Build recommendation logic using embeddings

**Tasks:**
1. Implement similarity-based recommendations
2. Create re-ranking logic (diversity, freshness)
3. Add filtering (by category, duration, etc.)
4. Create recommendation API

**Files to Create:**
- `src/recommendation/engine.py`
- `src/recommendation/ranker.py`

**Key Code Components:**
```python
# engine.py
class RecommendationEngine:
    def __init__(self, vector_db: VectorDatabase):
        self.db = vector_db
    
    def get_similar_videos(self, video_id: str, top_k: int = 10) -> List[str]
    def get_recommendations_by_embedding(self, embedding: np.ndarray, 
                                        top_k: int = 10) -> List[str]

# ranker.py
class ReRanker:
    def diversify(self, videos: List[str], max_diversity: int = 3) -> List[str]
    def filter_by_duration(self, videos: List[str], 
                          min_duration: int, max_duration: int) -> List[str]
```

---

### Phase 8: API Layer (Day 13)

**Objective:** Create REST API for video processing and recommendations

**Tasks:**
1. Set up FastAPI server
2. Create video processing endpoint
3. Create recommendation endpoint
4. Add health check and monitoring
5. Implement error handling

**Files to Create:**
- `src/api/main.py`
- `src/api/routes.py`

**API Endpoints:**
```
POST /api/v1/process-video
  - Body: { "video_url": "string" }
  - Response: { "video_id": "string", "status": "processing" }

GET /api/v1/recommend/{video_id}
  - Params: top_k (int, default=10)
  - Response: { "recommendations": ["video_id_1", ...] }

POST /api/v1/similar
  - Body: { "video_id": "string", "top_k": 10 }
  - Response: { "similar_videos": [...] }

GET /api/v1/health
  - Response: { "status": "healthy", "videos_processed": 1234 }
```

---

### Phase 9: Testing & Optimization (Day 14-15)

**Objective:** Test system and optimize performance

**Tasks:**
1. Write unit tests for each module
2. Create integration tests
3. Benchmark processing speed
4. Optimize memory usage
5. Add logging and monitoring

**Files to Create:**
- `tests/test_ingestion.py`
- `tests/test_extraction.py`
- `tests/test_api.py`

---

### Phase 10: Cleanup & Monitoring (Day 16)

**Objective:** Auto-cleanup processed files and monitor disk usage

**Tasks:**
1. Implement auto-cleanup after video processing
2. Add disk space monitoring
3. Create cleanup configuration
4. Add manual cleanup command

**Files to Create:**
- `src/cleanup/cleanup.py`

**Key Code Components:**
```python
# cleanup.py
class CleanupManager:
    def cleanup_after_processing(self, video_path: str, frames_dir: str):
        """Delete video and frames after embedding stored"""
        os.remove(video_path)
        shutil.rmtree(frames_dir)
    
    def cleanup_all(self, data_dir: str):
        """Delete all processed files"""
        shutil.rmtree("data/videos/*")
        shutil.rmtree("data/frames/*")
    
    def get_disk_usage(self) -> dict:
        """Check current disk usage"""
        # Returns: {used: "2.5GB", free: "1.5GB", total: "4GB"}
    
    def auto_cleanup_if_low(self, threshold_gb: float = 1.0):
        """Auto cleanup if disk space < 1GB"""
```

**Cleanup Flow:**
```
Video Downloaded → Frames Extracted → Embedding Stored → DELETE Video + Frames ✅
```

**Configuration:**
```python
# settings.py
AUTO_CLEANUP = True  # Processed files auto-delete
CLEANUP_AFTER_EMBEDDING = True  # Embedding store hone ke baad cleanup
MIN_FREE_SPACE_GB = 1.0  # Minimum free space rakhna hai
```

---

## Configuration

### settings.py
```python
# Video Processing
VIDEO_DIR = "data/videos"
MAX_VIDEO_SIZE_MB = 500
FRAME_SAMPLE_COUNT = 8

# Models
CLIP_MODEL = "ViT-B/32"

# Vector Database
EMBEDDING_DIMENSION = 576
FAISS_INDEX_PATH = "data/embeddings/faiss_index.bin"

# Cleanup
AUTO_CLEANUP = True
CLEANUP_AFTER_EMBEDDING = True
MIN_FREE_SPACE_GB = 1.0

# API
API_HOST = "0.0.0.0"
API_PORT = 8000
```

---

## Cost Analysis

| Component | Cost | Notes |
|-----------|------|-------|
| CLIP | Free | Local model |
| FAISS | Free | Local database |
| Cloudflare CDN | Pay per use | Video hosting |
| **Total** | **~$0-2/month** | For small-medium scale |

---

## Performance Metrics

| Metric | Target |
|--------|--------|
| Processing Speed | <1 min/video |
| Recommendation Accuracy | >80% relevant |
| RAM Usage | <1.5GB peak |
| Storage per Video | 0 (auto-cleanup) |
| API Response Time | <500ms |

---

## Usage Example

### Process a Video
```python
from src.extraction.fusion import MultiModalFusion
from src.storage.vector_db import VectorDatabase
from src.cleanup.cleanup import CleanupManager

# Initialize
fusion = MultiModalFusion()
db = VectorDatabase()
cleanup = CleanupManager()

# Process video
video_path = "data/videos/sample.mp4"
embedding = fusion.process_video(video_path)

# Store in database
db.add_embedding("video_001", embedding)

# Cleanup after embedding stored
cleanup.cleanup_after_processing(video_path, "data/frames/sample/")
```

### Get Recommendations
```python
from src.recommendation.engine import RecommendationEngine

# Initialize
engine = RecommendationEngine(db)

# Get similar videos
similar = engine.get_similar_videos("video_001", top_k=5)
print(similar)  # ['video_023', 'video_045', ...]
```

---

## Future Enhancements

1. **User Preferences** - Track user watching history
2. **Collaborative Filtering** - User-user similarity
3. **Real-time Updates** - Process videos on upload
4. **A/B Testing** - Test different recommendation strategies
5. **GPU Acceleration** - Faster CLIP inference
6. **Distributed Processing** - Scale to millions of videos

---

## Notes for Next Session

1. Start with **Phase 1** - Project setup
2. Use **virtual environment** for isolation
3. Test each phase independently before moving to next
4. Keep **8GB RAM limit** in mind - optimize as needed

---

## Dependencies (requirements.txt)

```
# Video Processing
opencv-python>=4.8.0
pyscenedetect>=0.5.3
ffmpeg-python>=0.2.0

# ML Models
torch>=2.0.0
torchvision>=0.15.0
clip @ git+https://github.com/openai/CLIP.git

# Vector Database
faiss-cpu>=1.7.4

# API
fastapi>=0.104.0
uvicorn>=0.24.0

# Utilities
numpy>=1.24.0
Pillow>=10.0.0
pydantic>=2.0.0
python-multipart>=0.0.6
```

---

**Plan Created:** Ready for implementation
**Next Step:** Start new session with Phase 1
