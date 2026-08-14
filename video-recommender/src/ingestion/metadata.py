import cv2
import json
import os
from typing import Dict, Any
from pathlib import Path

import sys
sys.path.append(str(Path(__file__).parent.parent.parent))
from config.settings import DATA_DIR


class MetadataExtractor:
    def __init__(self):
        self.metadata_dir = str(DATA_DIR / "metadata")
        os.makedirs(self.metadata_dir, exist_ok=True)
    
    def extract(self, video_path: str) -> Dict[str, Any]:
        cap = cv2.VideoCapture(video_path)
        
        if not cap.isOpened():
            raise ValueError(f"Could not open video: {video_path}")
        
        metadata = {
            "video_path": video_path,
            "duration": cap.get(cv2.CAP_PROP_FRAME_COUNT) / cap.get(cv2.CAP_PROP_FPS),
            "fps": cap.get(cv2.CAP_PROP_FPS),
            "frame_count": int(cap.get(cv2.CAP_PROP_FRAME_COUNT)),
            "width": int(cap.get(cv2.CAP_PROP_FRAME_WIDTH)),
            "height": int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT)),
            "codec": int(cap.get(cv2.CAP_PROP_FOURCC)),
            "file_size_mb": os.path.getsize(video_path) / (1024 * 1024)
        }
        
        cap.release()
        return metadata
    
    def extract_and_save(self, video_path: str, video_id: str) -> Dict[str, Any]:
        metadata = self.extract(video_path)
        metadata["video_id"] = video_id
        
        metadata_file = os.path.join(self.metadata_dir, f"{video_id}.json")
        with open(metadata_file, 'w') as f:
            json.dump(metadata, f, indent=2)
        
        print(f"Metadata saved: {metadata_file}")
        return metadata
    
    def load_metadata(self, video_id: str) -> Dict[str, Any]:
        metadata_file = os.path.join(self.metadata_dir, f"{video_id}.json")
        if not os.path.exists(metadata_file):
            raise FileNotFoundError(f"Metadata not found for video: {video_id}")
        
        with open(metadata_file, 'r') as f:
            return json.load(f)
