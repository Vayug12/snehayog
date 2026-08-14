import cv2
import numpy as np
from typing import List, Tuple, Optional
from pathlib import Path

import sys
sys.path.append(str(Path(__file__).parent.parent.parent))
from config.settings import FRAME_SAMPLE_COUNT


class FrameSampler:
    def __init__(self):
        self.min_scene_length = 30
    
    def detect_scenes(self, video_path: str) -> List[Tuple[float, float]]:
        try:
            from scenedetect import detect, ContentDetector
            
            scene_list = detect(video_path, ContentDetector(threshold=27.0))
            
            scenes = []
            for scene in scene_list:
                start_time = scene[0].get_seconds()
                end_time = scene[1].get_seconds()
                scenes.append((start_time, end_time))
            
            return scenes if scenes else self._fallback_scene_detection(video_path)
            
        except ImportError:
            print("PySceneDetect not available, using fallback detection")
            return self._fallback_scene_detection(video_path)
    
    def _fallback_scene_detection(self, video_path: str) -> List[Tuple[float, float]]:
        cap = cv2.VideoCapture(video_path)
        fps = cap.get(cv2.CAP_PROP_FPS)
        frame_count = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
        duration = frame_count / fps
        
        scene_length = duration / 10
        scenes = []
        
        for i in range(10):
            start = i * scene_length
            end = min((i + 1) * scene_length, duration)
            scenes.append((start, end))
        
        cap.release()
        return scenes
    
    def smart_sample(self, video_path: str, num_frames: int = FRAME_SAMPLE_COUNT) -> List[np.ndarray]:
        cap = cv2.VideoCapture(video_path)
        fps = cap.get(cv2.CAP_PROP_FPS)
        frame_count = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
        duration = frame_count / fps
        
        scenes = self.detect_scenes(video_path)
        
        if len(scenes) >= num_frames:
            selected_times = self._select_from_scenes(scenes, num_frames)
        else:
            selected_times = self._interpolate_frames(duration, num_frames)
        
        frames = []
        for timestamp in selected_times:
            frame = self._extract_frame_at(cap, timestamp)
            if frame is not None:
                frames.append(frame)
        
        cap.release()
        
        if len(frames) < num_frames:
            frames = self._fallback_sampling(video_path, num_frames)
        
        return frames
    
    def _select_from_scenes(self, scenes: List[Tuple[float, float]], num_frames: int) -> List[float]:
        selected_times = []
        
        if len(scenes) >= num_frames:
            indices = np.linspace(0, len(scenes) - 1, num_frames, dtype=int)
            for idx in indices:
                start, end = scenes[idx]
                mid_point = (start + end) / 2
                selected_times.append(mid_point)
        else:
            for start, end in scenes:
                mid_point = (start + end) / 2
                selected_times.append(mid_point)
        
        return selected_times
    
    def _interpolate_frames(self, duration: float, num_frames: int) -> List[float]:
        return np.linspace(0, duration, num_frames, endpoint=False).tolist()
    
    def _extract_frame_at(self, cap: cv2.VideoCapture, timestamp: float) -> Optional[np.ndarray]:
        fps = cap.get(cv2.CAP_PROP_FPS)
        frame_number = int(timestamp * fps)
        
        cap.set(cv2.CAP_PROP_POS_FRAMES, frame_number)
        ret, frame = cap.read()
        
        if ret:
            frame = cv2.resize(frame, (224, 224))
            frame = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
            return frame
        
        return None
    
    def _fallback_sampling(self, video_path: str, num_frames: int) -> List[np.ndarray]:
        cap = cv2.VideoCapture(video_path)
        frame_count = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
        
        frame_indices = np.linspace(0, frame_count - 1, num_frames, dtype=int)
        
        frames = []
        for idx in frame_indices:
            cap.set(cv2.CAP_PROP_POS_FRAMES, idx)
            ret, frame = cap.read()
            if ret:
                frame = cv2.resize(frame, (224, 224))
                frame = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
                frames.append(frame)
        
        cap.release()
        return frames
    
    def get_timestamps(self, video_path: str) -> List[float]:
        scenes = self.detect_scenes(video_path)
        timestamps = []
        for start, end in scenes:
            timestamps.append((start + end) / 2)
        return timestamps
    
    def extract_frames_to_disk(self, video_path: str, output_dir: str, num_frames: int = FRAME_SAMPLE_COUNT) -> List[str]:
        import os
        os.makedirs(output_dir, exist_ok=True)
        
        frames = self.smart_sample(video_path, num_frames)
        frame_paths = []
        
        for i, frame in enumerate(frames):
            frame_path = os.path.join(output_dir, f"frame_{i:03d}.jpg")
            frame_rgb = cv2.cvtColor(frame, cv2.COLOR_RGB2BGR)
            cv2.imwrite(frame_path, frame_rgb)
            frame_paths.append(frame_path)
        
        return frame_paths
