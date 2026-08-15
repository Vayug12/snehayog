import request from 'supertest';
import app from '../../server.js';
import User from '../../models/User.js';
import Video from '../../models/Video.js';
import Follower from '../../models/Follower.js';
import redisService from '../../services/caching/redisService.js';
import {
  getUtcMonthKey,
  rankCreatorSuggestions,
} from '../../services/creatorDiscoveryService.js';
import { generateJWT } from '../../utils/verifytoken.js';

describe('Suggested creator discovery', () => {
  const marker = `suggested-creators-${Date.now()}`;
  const videoType = `${marker}-type`;
  let viewer;
  let creators = [];
  let token;

  beforeAll(async () => {
    viewer = await User.create({
      googleId: `${marker}-viewer`,
      name: 'Suggestion Viewer',
      email: `${marker}-viewer@example.com`,
    });
    token = generateJWT(viewer.googleId, '1h');

    const now = new Date();
    creators = await User.insertMany(
      Array.from({ length: 26 }, (_, index) => ({
        googleId: `${marker}-creator-${index}`,
        name: `Suggestion Creator ${index}`,
        email: `${marker}-creator-${index}@example.com`,
        createdAt: new Date(now.getTime() - index * 60 * 1000),
      })),
    );

    await Video.insertMany(
      creators.map((creator, index) => ({
        uploader: creator._id,
        videoName: `Suggestion Video ${index}`,
        videoUrl: `https://example.com/${marker}/${index}.mp4`,
        videoType,
        processingStatus: 'completed',
        isSubscriberOnly: false,
        uploadedAt: new Date(now.getTime() - index * 60 * 1000),
        createdAt: new Date(now.getTime() - index * 60 * 1000),
      })),
    );
    await Follower.create({
      follower: viewer._id,
      following: creators[25]._id,
    });

    await redisService.del(
      `creators:publishing:v3:${videoType}:${getUtcMonthKey(now)}`,
    );
  });

  afterAll(async () => {
    const creatorIds = creators.map((creator) => creator._id);
    await Follower.deleteMany({ follower: viewer._id });
    await Video.deleteMany({ uploader: { $in: creatorIds } });
    await User.deleteMany({ _id: { $in: [viewer._id, ...creatorIds] } });
    await redisService.del(
      `creators:publishing:v3:${videoType}:${getUtcMonthKey(new Date())}`,
    );
  });

  test('GET /api/users/suggested-creators paginates beyond 12 without skips or duplicates', async () => {
    const seenCreatorIds = new Set();
    let cursor;
    let pageNumber = 0;
    let hasMore = true;

    while (hasMore && pageNumber < 100) {
      const response = await request(app)
        .get('/api/users/suggested-creators')
        .query({
          limit: 12,
          videoType,
          ...(cursor ? { cursor } : {}),
        })
        .set('Authorization', `Bearer ${token}`);

      expect(response.statusCode).toBe(200);
      expect(response.body.success).toBe(true);
      if (pageNumber < 2) {
        expect(response.body.creators).toHaveLength(12);
      } else {
        expect(response.body.creators.length).toBeLessThanOrEqual(12);
      }

      for (const creator of response.body.creators) {
        expect(seenCreatorIds.has(creator.id)).toBe(false);
        seenCreatorIds.add(creator.id);
      }

      hasMore = response.body.hasMore;
      cursor = response.body.nextCursor;
      if (hasMore) {
        expect(typeof cursor).toBe('string');
        expect(cursor).not.toBe('');
      } else {
        expect(cursor).toBeNull();
      }
      pageNumber += 1;
    }

    expect(hasMore).toBe(false);
    expect(pageNumber).toBeGreaterThanOrEqual(3);
    for (const creator of creators.slice(0, 25)) {
      expect(seenCreatorIds.has(creator.googleId)).toBe(true);
    }
    expect(seenCreatorIds.has(creators[25].googleId)).toBe(false);
  });

  test('new and current-month uploaders rank ahead of inactive creators', () => {
    const now = new Date('2026-08-15T12:00:00.000Z');
    const creatorUsers = [
      {
        _id: 'new-active',
        createdAt: '2026-08-10T00:00:00.000Z',
        followerCount: 0,
      },
      {
        _id: 'old-active',
        createdAt: '2024-01-01T00:00:00.000Z',
        followerCount: 0,
      },
      {
        _id: 'new-inactive',
        createdAt: '2026-07-25T00:00:00.000Z',
        followerCount: 0,
      },
      {
        _id: 'old-inactive',
        createdAt: '2024-01-01T00:00:00.000Z',
        followerCount: 100000,
      },
    ];
    const publishingCreatorStats = [
      {
        id: 'old-inactive',
        monthlyUploadCount: 0,
        matchingVideoCount: 100,
        latestUpload: '2026-05-01T00:00:00.000Z',
      },
      {
        id: 'new-inactive',
        monthlyUploadCount: 0,
        matchingVideoCount: 1,
        latestUpload: '2026-07-26T00:00:00.000Z',
      },
      {
        id: 'old-active',
        monthlyUploadCount: 8,
        matchingVideoCount: 1,
        latestUpload: '2026-08-14T00:00:00.000Z',
      },
      {
        id: 'new-active',
        monthlyUploadCount: 1,
        matchingVideoCount: 1,
        latestUpload: '2026-08-11T00:00:00.000Z',
      },
    ];

    const ranked = rankCreatorSuggestions({
      publishingCreatorStats,
      creatorUsers,
      now,
    });

    expect(ranked.map((entry) => entry.stats.id)).toEqual([
      'new-active',
      'old-active',
      'new-inactive',
      'old-inactive',
    ]);
  });
});
