import os
import uuid
import requests
from typing import List, Optional
from pathlib import Path

import sys
sys.path.append(str(Path(__file__).parent.parent.parent))
from config.settings import VIDEO_DIR, MAX_VIDEO_SIZE_MB


class VideoDownloader:
    def __init__(self, output_dir: str = VIDEO_DIR):
        self.output_dir = output_dir
        os.makedirs(output_dir, exist_ok=True)
    
    def generate_video_id(self) -> str:
        return str(uuid.uuid4())[:8]
    
    def download_from_cdn(self, url: str, video_id: Optional[str] = None) -> str:
        if video_id is None:
            video_id = self.generate_video_id()
        
        output_path = os.path.join(self.output_dir, f"{video_id}.mp4")
        
        print(f"Downloading video from: {url}")
        response = requests.get(url, stream=True, timeout=30)
        response.raise_for_status()
        
        content_length = response.headers.get('content-length')
        if content_length and int(content_length) > MAX_VIDEO_SIZE_MB * 1024 * 1024:
            raise ValueError(f"Video exceeds max size of {MAX_VIDEO_SIZE_MB}MB")
        
        total_size = 0
        with open(output_path, 'wb') as f:
            for chunk in response.iter_content(chunk_size=8192):
                if chunk:
                    f.write(chunk)
                    total_size += len(chunk)
        
        print(f"Downloaded: {output_path} ({total_size / 1024 / 1024:.2f} MB)")
        return output_path
    
    def download_batch(self, urls: List[str]) -> List[str]:
        downloaded_paths = []
        for url in urls:
            try:
                path = self.download_from_cdn(url)
                downloaded_paths.append(path)
            except Exception as e:
                print(f"Failed to download {url}: {e}")
        return downloaded_paths
