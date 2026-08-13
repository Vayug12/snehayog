import express from 'express';
import Feedback from '../../models/Feedback.js';

const router = express.Router();

const sanitizeAttribution = (attribution = {}) => {
  const cleanString = (value, maxLength = 120) => {
    if (value === null || value === undefined) return undefined;
    const normalized = String(value).trim().toLowerCase();
    if (!normalized) return undefined;
    return normalized.slice(0, maxLength);
  };

  return {
    source: cleanString(attribution.source || attribution.utm_source),
    medium: cleanString(attribution.medium || attribution.utm_medium),
    campaign: cleanString(attribution.campaign || attribution.utm_campaign),
    content: cleanString(attribution.content || attribution.utm_content),
    term: cleanString(attribution.term || attribution.utm_term),
    rawReferrer: cleanString(attribution.rawReferrer || attribution.raw_referrer, 1000)
  };
};

// Submit feedback
router.post('/submit', async (req, res) => {
  try {
    const { rating, comments, userEmail, userId, type, videoId, attribution } = req.body;
    const sanitizedAttribution = sanitizeAttribution(attribution);

    console.log('📝 Feedback submission attempt:', { 
      rating, 
      userEmail, 
      userId, 
      type,
      videoId,
      attributionSource: sanitizedAttribution.source,
      commentsLength: comments?.length 
    });

    // Validate required fields
    if (type !== 'suggestion' && (!rating || rating < 1 || rating > 5)) {
      console.log('⚠️ Invalid rating:', rating);
      return res.status(400).json({
        success: false,
        error: 'Rating must be between 1 and 5'
      });
    }

    if (!userEmail || !userEmail.trim()) {
      console.log('⚠️ Missing user email');
      return res.status(400).json({
        success: false,
        error: 'User email is required'
      });
    }

    // Create feedback entry
    const feedback = new Feedback({
      rating: type === 'suggestion' ? (rating || 5) : rating,
      comments: comments || '',
      type: type || 'general',
      videoId: videoId || null,
      userEmail: userEmail.trim().toLowerCase(),
      userId: userId || null,
      userAgent: req.headers['user-agent'] || '',
      ipAddress: req.ip || req.connection?.remoteAddress || '',
      attribution: sanitizedAttribution
    });

    await feedback.save();
    console.log('✅ Feedback saved successfully:', feedback._id);

    res.status(201).json({
      success: true,
      message: 'Feedback submitted successfully',
      feedbackId: feedback._id
    });
  } catch (error) {
    console.error('❌ Error submitting feedback:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to submit feedback',
      details: process.env.NODE_ENV === 'development' ? error.message : undefined
    });
  }
});

// Get feedback statistics (public endpoint)
router.get('/stats', async (req, res) => {
  try {
    const stats = await Feedback.getStats();
    
    res.json({
      success: true,
      stats: stats
    });
  } catch (error) {
    console.error('Error fetching feedback stats:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to fetch feedback statistics'
    });
  }
});

export default router;
