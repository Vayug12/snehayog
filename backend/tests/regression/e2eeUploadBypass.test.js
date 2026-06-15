import request from 'supertest';
import app from '../../server.js';
import mongoose from 'mongoose';
import User from '../../models/User.js';
import Video from '../../models/Video.js';
import { generateJWT } from '../../utils/verifytoken.js';

describe('🔒 E2EE Subscriber-Only Video Upload Bypass', () => {
  let creator;
  let subscriber;
  let creatorToken;

  beforeAll(async () => {
    // 1. Create a mock creator
    const creatorGoogleId = 'creator-google-id-' + Date.now();
    creator = await User.create({
      googleId: creatorGoogleId,
      name: 'Test Creator',
      email: 'creator-' + Date.now() + '@example.com',
      videos: []
    });

    // 2. Create a mock subscriber
    subscriber = await User.create({
      googleId: 'subscriber-google-id-' + Date.now(),
      name: 'Test Subscriber',
      email: 'subscriber-' + Date.now() + '@example.com',
      videos: []
    });

    // 3. Generate a JWT token for the creator
    creatorToken = generateJWT(creatorGoogleId, '1h');
  });

  afterAll(async () => {
    // Clean up mock users and videos
    await User.deleteMany({ _id: { $in: [creator._id, subscriber._id] } });
    await Video.deleteMany({ uploader: creator._id });
  });

  test('POST /api/upload/video/direct-complete should bypass processing and use lock placeholder when subscriber-only', async () => {
    const res = await request(app)
      .post('/api/upload/video/direct-complete')
      .set('Authorization', `Bearer ${creatorToken}`)
      .send({
        key: 'uploads/raw/test-video.mp4',
        videoName: 'Super Secret Encrypted Strategy',
        description: 'E2EE video strategy',
        allowedSubscribers: [subscriber._id.toString()], // passing subscriber ID
        size: 1234567,
        category: 'finance',
        tags: ['crypto', 'trading']
      });

    expect(res.statusCode).toBe(201);
    expect(res.body.success).toBe(true);
    expect(res.body.video).toBeDefined();

    const videoId = res.body.video.id || res.body.video._id;
    expect(videoId).toBeDefined();

    // Verify properties in response
    expect(res.body.video.processingStatus).toBe('completed');
    expect(res.body.video.isSubscriberOnly).toBe(true);
    expect(res.body.video.thumbnailUrl).toBe('https://placehold.co/600x400/1e1e24/ffffff?text=Subscriber+Only+🔒');

    // Retrieve from database to verify persistence
    const dbVideo = await Video.findById(videoId);
    expect(dbVideo).toBeDefined();
    expect(dbVideo.processingStatus).toBe('completed');
    expect(dbVideo.processingProgress).toBe(100);
    expect(dbVideo.isSubscriberOnly).toBe(true);
    expect(dbVideo.thumbnailUrl).toBe('https://placehold.co/600x400/1e1e24/ffffff?text=Subscriber+Only+🔒');
    expect(dbVideo.allowedSubscribers.map(id => id.toString())).toContain(subscriber._id.toString());
  });

  test('GET /api/upload/video/:videoId/status should return completed for the bypass video', async () => {
    // 1. Create a subscriber-only video record directly
    const video = await Video.create({
      uploader: creator._id,
      videoName: 'Status Test Video',
      videoUrl: 'https://cdn.snehayog.site/videos/test.mp4',
      thumbnailUrl: 'https://placehold.co/600x400/1e1e24/ffffff?text=Subscriber+Only+🔒',
      processingStatus: 'completed',
      processingProgress: 100,
      allowedSubscribers: [subscriber._id],
      isSubscriberOnly: true
    });

    // 2. Fetch its status
    const res = await request(app)
      .get(`/api/upload/video/${video._id}/status`)
      .set('Authorization', `Bearer ${creatorToken}`);

    expect(res.statusCode).toBe(200);
    expect(res.body.success).toBe(true);
    expect(res.body.video.processingStatus).toBe('completed');
    expect(res.body.video.thumbnailUrl).toBe('https://placehold.co/600x400/1e1e24/ffffff?text=Subscriber+Only+🔒');
    expect(res.body.video.isSubscriberOnly).toBe(true);

    // Clean up
    await Video.deleteOne({ _id: video._id });
  });
});
