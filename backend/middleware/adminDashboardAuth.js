export const requireAdminDashboardKey = (req, res, next) => {
  const adminKey = process.env.ADMIN_DASHBOARD_KEY;
  const providedKey =
    req.headers['x-admin-key'] || req.query.adminKey || req.query.apiKey;

  // Helper to trim and clean keys (removes surrounding quotes and whitespace/carriage returns)
  const cleanKey = (key) => {
    if (!key || typeof key !== 'string') return '';
    let cleaned = key.trim();
    // Strip surrounding double quotes
    if (cleaned.startsWith('"') && cleaned.endsWith('"')) {
      cleaned = cleaned.slice(1, -1);
    }
    // Strip surrounding single quotes
    if (cleaned.startsWith("'") && cleaned.endsWith("'")) {
      cleaned = cleaned.slice(1, -1);
    }
    return cleaned.trim();
  };

  const cleanedAdminKey = cleanKey(adminKey);
  const cleanedProvidedKey = cleanKey(providedKey);

  console.log('🔑 Admin Dashboard Auth Attempt:', {
    hasAdminKey: !!adminKey,
    cleanedAdminKeyLength: cleanedAdminKey.length,
    hasProvidedKey: !!providedKey,
    cleanedProvidedKeyLength: cleanedProvidedKey.length,
    match: cleanedAdminKey === cleanedProvidedKey && cleanedAdminKey !== ''
  });

  if (!cleanedAdminKey) {
    if (process.env.NODE_ENV !== 'production') {
      console.warn(
        '⚠️ ADMIN_DASHBOARD_KEY is not set. Allowing access because NODE_ENV is not production.'
      );
      return next();
    }

    console.error(
      '❌ ADMIN_DASHBOARD_KEY missing and NODE_ENV=production. Rejecting request.'
    );
    return res
      .status(503)
      .json({ error: 'Admin dashboard access not configured' });
  }

  if (cleanedProvidedKey && cleanedProvidedKey === cleanedAdminKey) {
    return next();
  }

  return res
    .status(401)
    .json({ error: 'Unauthorized: invalid admin dashboard key' });
};

/**
 * Same check, but refuses to fall open.
 *
 * `requireAdminDashboardKey` allows everything when ADMIN_DASHBOARD_KEY is
 * unset and NODE_ENV is not 'production' — convenient for read-only dashboard
 * routes, unacceptable for routes that move money (credit grants, refunds).
 * A staging deploy with the key missing would otherwise let anyone mint or
 * return credits. Use this variant wherever the route touches a wallet.
 */
export const requireConfiguredAdminDashboardKey = (req, res, next) => {
  if (!process.env.ADMIN_DASHBOARD_KEY) {
    return res
      .status(503)
      .json({ error: 'Admin dashboard access not configured' });
  }
  return requireAdminDashboardKey(req, res, next);
};

export default requireAdminDashboardKey;

