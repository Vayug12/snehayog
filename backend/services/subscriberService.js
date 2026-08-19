import mongoose from 'mongoose';
import Follower from '../models/Follower.js';
import User from '../models/User.js';

/**
 * Subscriber list + "new subscribers" badge logic.
 *
 * A subscriber is a Follower doc pointing at the creator. Anything created
 * after `user.subscribersSeenAt` is unseen, which is what drives the red dot
 * on the profile Subscribers stat. Reads are cursor paginated (newest first)
 * and backed by the { following: 1, createdAt: -1 } index.
 */

const DEFAULT_PAGE_SIZE = 30;
const MAX_PAGE_SIZE = 100;

// Badge only needs "how many", not an exact number for huge creators.
// Capping the count keeps the query bounded no matter how big the audience is.
export const MAX_NEW_SUBSCRIBERS_COUNT = 999;

export const parseSubscriberLimit = (rawLimit) => {
  const parsed = parseInt(rawLimit, 10);
  if (!Number.isFinite(parsed)) return DEFAULT_PAGE_SIZE;
  return Math.min(Math.max(parsed, 1), MAX_PAGE_SIZE);
};

/** Cursor = "<createdAt millis>_<follower doc id>" so equal timestamps never skip rows. */
export const encodeSubscriberCursor = (doc) => {
  if (!doc?._id) return null;
  const createdAt = new Date(doc.createdAt || 0).getTime();
  return `${Number.isFinite(createdAt) ? createdAt : 0}_${doc._id.toString()}`;
};

export const decodeSubscriberCursor = (cursor) => {
  if (typeof cursor !== 'string' || !cursor.includes('_')) return null;

  const separatorIndex = cursor.indexOf('_');
  const millis = Number(cursor.slice(0, separatorIndex));
  const id = cursor.slice(separatorIndex + 1);

  if (!Number.isFinite(millis) || !mongoose.Types.ObjectId.isValid(id)) return null;

  return {
    createdAt: new Date(millis),
    id: new mongoose.Types.ObjectId(id),
  };
};

const toDate = (value) => {
  if (!value) return null;
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : date;
};

/**
 * One page of subscribers, newest first.
 * @returns {Promise<{subscribers: Array, hasMore: boolean, nextCursor: string|null}>}
 */
export const fetchSubscribersPage = async ({
  creatorId,
  limit = DEFAULT_PAGE_SIZE,
  cursor = null,
  seenAt = null,
}) => {
  const empty = { subscribers: [], hasMore: false, nextCursor: null };
  if (!creatorId) return empty;

  const filter = { following: creatorId };
  const decodedCursor = decodeSubscriberCursor(cursor);
  if (decodedCursor) {
    filter.$or = [
      { createdAt: { $lt: decodedCursor.createdAt } },
      { createdAt: decodedCursor.createdAt, _id: { $lt: decodedCursor.id } },
    ];
  }

  // Fetch one extra row to detect "hasMore" without a second count query
  const docs = await Follower.find(filter)
    .sort({ createdAt: -1, _id: -1 })
    .limit(limit + 1)
    .select('follower createdAt')
    .populate('follower', 'name email profilePic profilePicture')
    .lean();

  const hasMore = docs.length > limit;
  const pageDocs = hasMore ? docs.slice(0, limit) : docs;
  if (pageDocs.length === 0) return empty;

  const seenMillis = toDate(seenAt)?.getTime() ?? null;

  const subscribers = pageDocs
    // Follower may point at a deleted account — skip instead of crashing
    .filter((doc) => doc.follower)
    .map((doc) => {
      const subscribedAt = toDate(doc.createdAt);
      return {
        _id: doc.follower._id,
        id: doc.follower._id.toString(),
        name: doc.follower.name || 'Vayug user',
        email: doc.follower.email || '',
        profilePic: doc.follower.profilePic || doc.follower.profilePicture || '',
        subscribedAt,
        // Never opened the list => everything counts as new
        isNew: seenMillis === null
          ? true
          : (subscribedAt?.getTime() ?? 0) > seenMillis,
      };
    });

  return {
    subscribers,
    hasMore,
    // Cursor comes from the raw doc so deleted-account rows still advance the page
    nextCursor: hasMore ? encodeSubscriberCursor(pageDocs[pageDocs.length - 1]) : null,
  };
};

/** Subscribers gained since the creator last opened the list (capped). */
export const countNewSubscribers = async ({ creatorId, seenAt = null }) => {
  if (!creatorId) return 0;

  const filter = { following: creatorId };
  const seenDate = toDate(seenAt);
  if (seenDate) filter.createdAt = { $gt: seenDate };

  return Follower.countDocuments(filter, { limit: MAX_NEW_SUBSCRIBERS_COUNT + 1 });
};

/**
 * Move the "seen" watermark forward. Never moves backwards, and never past now,
 * so a stale client or a bad clock cannot hide genuinely new subscribers.
 * @returns {Promise<{seenAt: Date, updated: boolean}>}
 */
export const markSubscribersSeen = async ({ creatorId, seenAt = null, currentSeenAt = null }) => {
  const now = new Date();
  const requested = toDate(seenAt) ?? now;
  const stamp = requested > now ? now : requested;

  const current = toDate(currentSeenAt);
  if (current && current >= stamp) {
    return { seenAt: current, updated: false };
  }

  const result = await User.updateOne(
    {
      _id: creatorId,
      $or: [
        { subscribersSeenAt: null },
        { subscribersSeenAt: { $exists: false } },
        { subscribersSeenAt: { $lt: stamp } },
      ],
    },
    { $set: { subscribersSeenAt: stamp } },
  );

  return { seenAt: stamp, updated: (result?.modifiedCount ?? 0) > 0 };
};
