import { buildVideoPath, slugifyVideoTitle } from '../utils/videoUrl.js';

describe('video URL helpers', () => {
  test('creates a stable, readable slug', () => {
    expect(slugifyVideoTitle("Creator's Tips & Tricks!"))
      .toBe('creators-tips-and-tricks');
  });

  test('keeps the immutable video ID before the slug', () => {
    expect(buildVideoPath('507f1f77bcf86cd799439011', 'Morning Yoga'))
      .toBe('/video/507f1f77bcf86cd799439011/morning-yoga');
  });

  test('uses a stable fallback when the title has no ASCII words', () => {
    expect(slugifyVideoTitle('!!!')).toBe('video');
  });
});
