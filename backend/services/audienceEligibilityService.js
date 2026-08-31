/**
 * Profession targeting is an eligibility filter only. It never alters scores.
 */
export const buildProfessionEligibilityClause = (professionId) => {
  const publicVideoClause = { 'targetProfessionIds.0': { $exists: false } };
  if (!professionId) return publicVideoClause;

  return {
    $or: [
      publicVideoClause,
      { targetProfessionIds: professionId },
    ],
  };
};

export const withProfessionEligibility = (query, professionId) => ({
  $and: [query, buildProfessionEligibilityClause(professionId)],
});

export const isVideoEligibleForProfession = (video, professionId) => {
  const targets = Array.isArray(video?.targetProfessionIds)
    ? video.targetProfessionIds.map(String)
    : [];
  return targets.length === 0 || (!!professionId && targets.includes(professionId));
};

