/**
 * Access Control Middleware
 * Ensures users can only access/modify their own payment data
 */

/**
 * Middleware to verify user owns the resource
 * Checks if the authenticated user matches the requested user ID
 */
export function verifyResourceOwnership(req, res, next) {
  try {
    const authenticatedUserId = req.user?.id || req.user?.googleId;
    
    if (!authenticatedUserId) {
      return res.status(401).json({ 
        error: 'Authentication required' 
      });
    }

    // Extract user ID from params or body
    const requestedUserId = req.params.userId || req.body.userId || req.query.userId;
    
    // If no specific user ID requested, allow (user accessing their own data via token)
    if (!requestedUserId) {
      return next();
    }

    // Verify ownership
    if (authenticatedUserId !== requestedUserId && 
        authenticatedUserId !== req.params.id &&
        authenticatedUserId !== req.body.id) {
      console.warn('⚠️ Access denied: User', authenticatedUserId, 'attempted to access resource for', requestedUserId);
      return res.status(403).json({ 
        error: 'Access denied: You can only access your own data' 
      });
    }

    next();
  } catch (error) {
    console.error('❌ Access control error:', error);
    return res.status(500).json({ 
      error: 'Access control verification failed' 
    });
  }
}




/**
 * Middleware to ensure only admins can access admin endpoints
 */
export function requireAdmin(req, res, next) {
  try {
    // TODO: Implement admin role checking
    // For now, you can add an isAdmin field to User model
    const user = req.user;
    
    if (!user || !user.isAdmin) {
      return res.status(403).json({ 
        error: 'Admin access required' 
      });
    }

    next();
  } catch (error) {
    console.error('❌ Admin check error:', error);
    return res.status(500).json({ 
      error: 'Admin verification failed' 
    });
  }
}
