import shutil
import os
import shutil
from pathlib import Path

import sys
sys.path.append(str(Path(__file__).parent.parent.parent))
from config.settings import VIDEO_DIR, MIN_FREE_SPACE_GB


class CleanupManager:
    def __init__(self):
        self.video_dir = VIDEO_DIR
    
    def cleanup_after_processing(self, video_path: str, frames_dir: str):
        if os.path.exists(video_path):
            os.remove(video_path)
            print(f"Deleted video: {video_path}")
        
        if os.path.exists(frames_dir):
            shutil.rmtree(frames_dir)
            print(f"Deleted frames: {frames_dir}")
    
    def cleanup_all(self):
        if os.path.exists(self.video_dir):
            shutil.rmtree(self.video_dir)
            os.makedirs(self.video_dir)
            print("Cleaned all videos")
    
    def get_disk_usage(self) -> dict:
        disk = shutil.disk_usage("/")
        return {
            "used_gb": round(disk.used / (1024**3), 2),
            "free_gb": round(disk.free / (1024**3), 2),
            "total_gb": round(disk.total / (1024**3), 2)
        }
    
    def auto_cleanup_if_low(self, threshold_gb: float = MIN_FREE_SPACE_GB):
        usage = self.get_disk_usage()
        
        if usage["free_gb"] < threshold_gb:
            print(f"Low disk space: {usage['free_gb']}GB free")
            self.cleanup_all()
            return True
        
        return False
