import mongoose from 'mongoose';
import Follower from '../models/Follower.js';
import User from '../models/User.js';
import {
  countNewSubscribers,
  fetchSubscribersPage,
  markSubscribersSeen,
  parseSubscriberLimit,
} from '../services/subscriberService.js';

describe('subscriber list + new-subscriber badge', () => {
  const creatorId = new mongoose.Types.ObjectId();
  const subscriberIds = Array.from({ length: 3 }, () => new mongoose.Types.ObjectId());

  // Oldest -> newest so cursor paging and the seen watermark are both testable
  const subscribedAt = [
    new Date('2026-08-01T10:00:00.000Z'),
    new Date('2026-08-10T10:00:00.000Z'),
    new Date('2026-08-15T10:00:00.000Z'),
  ];

  beforeEach(async () => {
    await User.create({
      _id: creatorId,
      googleId: `test-creator-${creatorId}`,
      name: 'Test Creator',
      email: `creator-${creatorId}@test.local`,
    });

    await User.insertMany(subscriberIds.map((id, index) => ({
      _id: id,
      googleId: `test-subscriber-${id}`,
      name: `Subscriber ${index + 1}`,
      email: `subscriber-${id}@test.local`,
      profilePic: '',
    })));

    await Follower.insertMany(subscriberIds.map((id, index) => ({
      follower: id,
      following: creatorId,
      createdAt: subscribedAt[index],
      updatedAt: subscribedAt[index],
    })));
  });

  afterEach(async () => {
    await Follower.deleteMany({ following: creatorId });
    await User.deleteMany({ _id: { $in: [creatorId, ...subscriberIds] } });
  });

  test('pages subscribers newest first without repeats', async () => {
    const firstPage = await fetchSubscribersPage({ creatorId, limit: 2 });

    expect(firstPage.subscribers.map((s) => s.name)).toEqual(['Subscriber 3', 'Subscriber 2']);
    expect(firstPage.hasMore).toBe(true);
    expect(firstPage.nextCursor).toBeTruthy();

    const secondPage = await fetchSubscribersPage({
      creatorId,
      limit: 2,
      cursor: firstPage.nextCursor,
    });

    expect(secondPage.subscribers.map((s) => s.name)).toEqual(['Subscriber 1']);
    expect(secondPage.hasMore).toBe(false);
    expect(secondPage.nextCursor).toBeNull();
  });

  test('everything is new until the creator opens the list', async () => {
    expect(await countNewSubscribers({ creatorId, seenAt: null })).toBe(3);

    const page = await fetchSubscribersPage({ creatorId, limit: 10, seenAt: null });
    expect(page.subscribers.every((s) => s.isNew)).toBe(true);
  });

  test('only subscribers after the watermark stay new', async () => {
    const seenAt = subscribedAt[1]; // saw up to Subscriber 2

    expect(await countNewSubscribers({ creatorId, seenAt })).toBe(1);

    const page = await fetchSubscribersPage({ creatorId, limit: 10, seenAt });
    const newNames = page.subscribers.filter((s) => s.isNew).map((s) => s.name);
    expect(newNames).toEqual(['Subscriber 3']);
  });

  test('watermark moves forward, never backwards or into the future', async () => {
    const first = await markSubscribersSeen({ creatorId, seenAt: subscribedAt[2] });
    expect(first.seenAt).toEqual(subscribedAt[2]);

    const stored = await User.findById(creatorId).select('subscribersSeenAt').lean();
    expect(stored.subscribersSeenAt).toEqual(subscribedAt[2]);
    expect(await countNewSubscribers({ creatorId, seenAt: stored.subscribersSeenAt })).toBe(0);

    // A stale client replaying an older timestamp must not resurrect the badge
    const stale = await markSubscribersSeen({
      creatorId,
      seenAt: subscribedAt[0],
      currentSeenAt: stored.subscribersSeenAt,
    });
    expect(stale.updated).toBe(false);
    expect(stale.seenAt).toEqual(subscribedAt[2]);

    // A bad clock cannot hide subscribers that have not arrived yet
    const future = new Date(Date.now() + 60 * 60 * 1000);
    const clamped = await markSubscribersSeen({ creatorId, seenAt: future });
    expect(clamped.seenAt.getTime()).toBeLessThanOrEqual(Date.now());
  });

  test('limit is clamped to a sane range', () => {
    expect(parseSubscriberLimit(undefined)).toBe(30);
    expect(parseSubscriberLimit('abc')).toBe(30);
    expect(parseSubscriberLimit('5')).toBe(5);
    expect(parseSubscriberLimit('0')).toBe(1);
    expect(parseSubscriberLimit('5000')).toBe(100);
  });

  test('an invalid cursor falls back to the first page instead of failing', async () => {
    const page = await fetchSubscribersPage({ creatorId, limit: 10, cursor: 'not-a-cursor' });
    expect(page.subscribers).toHaveLength(3);
  });
});
