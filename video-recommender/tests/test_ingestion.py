import pytest
from pathlib import Path

import sys
sys.path.insert(0, str(Path(__file__).parent.parent))

from src.ingestion.downloader import VideoDownloader
from src.ingestion.metadata import MetadataExtractor


def test_video_downloader():
    downloader = VideoDownloader()
    video_id = downloader.generate_video_id()
    assert len(video_id) == 8


def test_metadata_extractor():
    extractor = MetadataExtractor()
    assert extractor.metadata_dir is not None
