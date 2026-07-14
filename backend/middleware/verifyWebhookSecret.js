import crypto from 'crypto';
import { WEBHOOK_SECRET } from '../services/videoGen/aiAgentService.js';

/**
 * Verifies the shared secret sent by the VayugAI agent on webhook callbacks.
 *
 * The agent is a server, not a logged-in user, so it cannot present a JWT.
 * Instead it echoes back the secret we handed it at trigger time via the
 * `x-vayug-webhook-secret` header. Compared in constant time to avoid
 * timing side-channels.
 *
 * Fails closed: if no secret is configured on the server, every call is
 * rejected (an unauthenticated open webhook that mutates job state is unsafe).
 */
export function verifyWebhookSecret(req, res, next) {
  const expected = WEBHOOK_SECRET;

  if (!expected) {
    console.error(
      '❌ [VideoGen] VIDEO_GEN_WEBHOOK_SECRET is not configured. Rejecting webhook.'
    );
    return res.status(503).json({ error: 'Webhook not configured.' });
  }

  const provided = req.headers['x-vayug-webhook-secret'];
  if (!provided || typeof provided !== 'string') {
    return res.status(401).json({ error: 'Missing webhook secret.' });
  }

  const a = Buffer.from(provided);
  const b = Buffer.from(expected);
  if (a.length !== b.length || !crypto.timingSafeEqual(a, b)) {
    console.warn('⚠️ [VideoGen] Webhook call rejected: invalid secret.');
    return res.status(401).json({ error: 'Invalid webhook secret.' });
  }

  return next();
}

export default verifyWebhookSecret;
