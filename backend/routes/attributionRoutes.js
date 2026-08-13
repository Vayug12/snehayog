import express from 'express';
import AnonymousDevice from '../models/AnonymousDevice.js';

const router = express.Router();

/**
 * POST /api/attribution/capture
 * Captures install attribution for anonymous devices on first API call.
 * Body: { deviceId, attribution: { source, medium, campaign, content, term, rawReferrer }, appVersion }
 */
router.post('/capture', async (req, res) => {
  try {
    const { deviceId, attribution, appVersion } = req.body;

    if (!deviceId || deviceId.trim() === '' || deviceId === 'anon' || deviceId === 'anonymous') {
      return res.status(400).json({ error: 'Valid device ID is required' });
    }

    const trimmedDeviceId = deviceId.trim();

    // Check if attribution data exists
    if (!attribution || Object.keys(attribution).length === 0) {
      return res.status(400).json({ error: 'Attribution data is required' });
    }

    const sanitizedAttribution = {};
    if (attribution.source) sanitizedAttribution.source = String(attribution.source).trim().toLowerCase().slice(0, 120);
    if (attribution.medium) sanitizedAttribution.medium = String(attribution.medium).trim().toLowerCase().slice(0, 120);
    if (attribution.campaign) sanitizedAttribution.campaign = String(attribution.campaign).trim().toLowerCase().slice(0, 120);
    if (attribution.content) sanitizedAttribution.content = String(attribution.content).trim().toLowerCase().slice(0, 120);
    if (attribution.term) sanitizedAttribution.term = String(attribution.term).trim().toLowerCase().slice(0, 120);
    if (attribution.rawReferrer) sanitizedAttribution.rawReferrer = String(attribution.rawReferrer).trim().slice(0, 1000);

    if (Object.keys(sanitizedAttribution).length === 0) {
      return res.status(400).json({ error: 'No valid attribution fields provided' });
    }

    // Upsert: create or update attribution for this device
    // Only update if device has no attribution yet (first capture wins)
    const existing = await AnonymousDevice.findOne({ deviceId: trimmedDeviceId });

    if (existing) {
      // If already merged to a user, don't overwrite
      if (existing.mergedToUser) {
        return res.json({ success: true, message: 'Device already attributed and merged', merged: true });
      }
      // If attribution already exists, don't overwrite (first capture wins)
      if (existing.attribution && existing.attribution.source) {
        return res.json({ success: true, message: 'Attribution already captured', alreadyCaptured: true });
      }
      // Update with new attribution
      existing.attribution = sanitizedAttribution;
      if (appVersion) existing.appVersion = appVersion;
      existing.lastSeenAt = new Date();
      await existing.save();
    } else {
      await AnonymousDevice.create({
        deviceId: trimmedDeviceId,
        attribution: sanitizedAttribution,
        appVersion: appVersion || 'unknown',
        firstSeenAt: new Date(),
        lastSeenAt: new Date()
      });
    }

    console.log(`✅ Attribution captured for device: ${trimmedDeviceId.substring(0, 8)}... source: ${sanitizedAttribution.source || 'unknown'}`);
    res.json({ success: true, message: 'Attribution captured successfully' });

  } catch (error) {
    console.error('❌ Attribution capture error:', error);
    res.status(500).json({ error: 'Failed to capture attribution' });
  }
});

export default router;
