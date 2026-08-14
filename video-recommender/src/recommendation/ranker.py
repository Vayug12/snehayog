from typing import List, Dict, Any


class ReRanker:
    def __init__(self):
        pass
    
    def diversify(self, videos: List[Dict[str, Any]], max_diversity: int = 3) -> List[Dict[str, Any]]:
        if len(videos) <= max_diversity:
            return videos
        
        diversified = videos[:max_diversity]
        remaining = videos[max_diversity:]
        
        for video in remaining:
            is_diverse = True
            for selected in diversified:
                if video["video_id"] == selected["video_id"]:
                    is_diverse = False
                    break
            
            if is_diverse and len(diversified) < len(videos):
                diversified.append(video)
        
        return diversified
    
    def filter_by_duration(self, videos: List[Dict[str, Any]], 
                          min_duration: float = 0, 
                          max_duration: float = float('inf')) -> List[Dict[str, Any]]:
        filtered = []
        for video in videos:
            metadata = video.get("metadata", {})
            duration = metadata.get("duration", 0)
            
            if min_duration <= duration <= max_duration:
                filtered.append(video)
        
        return filtered
    
    def filter_by_score(self, videos: List[Dict[str, Any]], 
                       min_score: float = 0.0) -> List[Dict[str, Any]]:
        return [v for v in videos if v.get("score", 0) >= min_score]
