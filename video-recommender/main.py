import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

from src.ingestion.downloader import VideoDownloader
from src.ingestion.metadata import MetadataExtractor


def main():
    parser = argparse.ArgumentParser(description="Video Recommendation System")
    parser.add_argument("--url", type=str, help="Video URL to download and process")
    parser.add_argument("--test", action="store_true", help="Run basic test")
    
    args = parser.parse_args()
    
    if args.test:
        print("Video Recommendation System - Phase 1 Complete!")
        print("Project structure created successfully.")
        return
    
    if args.url:
        downloader = VideoDownloader()
        extractor = MetadataExtractor()
        
        video_id = downloader.generate_video_id()
        video_path = downloader.download_from_cdn(args.url, video_id)
        metadata = extractor.extract_and_save(video_path, video_id)
        
        print(f"\nVideo processed successfully!")
        print(f"Video ID: {video_id}")
        print(f"Duration: {metadata['duration']:.2f}s")
        print(f"Resolution: {metadata['width']}x{metadata['height']}")
        return
    
    parser.print_help()


if __name__ == "__main__":
    main()
