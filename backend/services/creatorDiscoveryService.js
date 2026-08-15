const DAY_MS = 24 * 60 * 60 * 1000;

export const NEW_CREATOR_WINDOW_DAYS = 30;

export const getUtcMonthRange = (month, year) => ({
  startDate: new Date(Date.UTC(year, month, 1)),
  endDate: new Date(Date.UTC(year, month + 1, 1)),
});

export const getUtcMonthKey = (date = new Date()) =>
  `${date.getUTCFullYear()}-${String(date.getUTCMonth() + 1).padStart(2, '0')}`;

export const buildPublishingCreatorStatsPipeline = ({
  videoType,
  now = new Date(),
}) => {
  const { startDate, endDate } = getUtcMonthRange(
    now.getUTCMonth(),
    now.getUTCFullYear(),
  );

  return [
    {
      $match: {
        uploader: { $ne: null },
        processingStatus: 'completed',
        isSubscriberOnly: { $ne: true },
      },
    },
    {
      $group: {
        _id: '$uploader',
        latestUpload: { $max: { $ifNull: ['$uploadedAt', '$createdAt'] } },
        monthlyUploadCount: {
          $sum: {
            $cond: [
              {
                $and: [
                  { $gte: ['$createdAt', startDate] },
                  { $lt: ['$createdAt', endDate] },
                ],
              },
              1,
              0,
            ],
          },
        },
        matchingVideoCount: {
          $sum: { $cond: [{ $eq: ['$videoType', videoType] }, 1, 0] },
        },
      },
    },
  ];
};

const timestamp = (value) => {
  const result = new Date(value || 0).getTime();
  return Number.isFinite(result) ? result : 0;
};

const discoveryTier = ({ stats, user }, newCreatorCutoff) => {
  const isNew = timestamp(user.createdAt) >= newCreatorCutoff;
  const isMonthlyActive = Number(stats.monthlyUploadCount || 0) > 0;
  if (isNew && isMonthlyActive) return 3;
  if (isMonthlyActive) return 2;
  if (isNew) return 1;
  return 0;
};

export const rankCreatorSuggestions = ({
  publishingCreatorStats,
  creatorUsers,
  now = new Date(),
}) => {
  const userById = new Map(
    creatorUsers.map((creator) => [creator._id.toString(), creator]),
  );
  const newCreatorCutoff = now.getTime() - NEW_CREATOR_WINDOW_DAYS * DAY_MS;

  return publishingCreatorStats
    .map((stats) => ({ stats, user: userById.get(stats.id) }))
    .filter((entry) => entry.user)
    .sort((a, b) => {
      const tierDifference =
        discoveryTier(b, newCreatorCutoff) -
        discoveryTier(a, newCreatorCutoff);
      if (tierDifference !== 0) return tierDifference;

      const monthlyUploadDifference =
        Number(b.stats.monthlyUploadCount || 0) -
        Number(a.stats.monthlyUploadCount || 0);
      if (monthlyUploadDifference !== 0) return monthlyUploadDifference;

      const latestUploadDifference =
        timestamp(b.stats.latestUpload) - timestamp(a.stats.latestUpload);
      if (latestUploadDifference !== 0) return latestUploadDifference;

      const matchingVideoDifference =
        Number(b.stats.matchingVideoCount || 0) -
        Number(a.stats.matchingVideoCount || 0);
      if (matchingVideoDifference !== 0) return matchingVideoDifference;

      const joinedDifference =
        timestamp(b.user.createdAt) - timestamp(a.user.createdAt);
      if (joinedDifference !== 0) return joinedDifference;

      const followerDifference =
        Number(b.user.followerCount || 0) -
        Number(a.user.followerCount || 0);
      if (followerDifference !== 0) return followerDifference;

      return a.stats.id.localeCompare(b.stats.id);
    });
};

export const paginateCreatorSuggestions = ({
  rankedCreators,
  excludedIds,
  cursor,
  limit,
}) => {
  const creators = [];
  let nextOffset = cursor;

  while (nextOffset < rankedCreators.length && creators.length < limit) {
    const entry = rankedCreators[nextOffset];
    nextOffset += 1;
    if (!excludedIds.has(entry.stats.id)) creators.push(entry.user);
  }

  const hasMore = rankedCreators
    .slice(nextOffset)
    .some((entry) => !excludedIds.has(entry.stats.id));

  return {
    creators,
    hasMore,
    nextCursor: hasMore ? String(nextOffset) : null,
  };
};
