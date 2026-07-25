import jwt from 'jsonwebtoken';
// import { OAuth2Client } from 'google-auth-library'; // LAZY loaded — sirf Google ID token pe load
import { config } from '../config.js';
import User from '../models/User.js';

// Ensure we're using the correct Google Client ID
const GOOGLE_CLIENT_ID = process.env.GOOGLE_CLIENT_ID || '406195883653-qp49f9nauq4t428ndscuu3nr9jb10g4h.apps.googleusercontent.com';

// LAZY: OAuth2Client sirf tab load jab Google ID token verify karna ho
let _googleClient = null;
const getGoogleClient = async () => {
  if (!_googleClient) {
    const { OAuth2Client } = await import('google-auth-library');
    _googleClient = new OAuth2Client(GOOGLE_CLIENT_ID);
  }
  return _googleClient;
};

// **OPTIMIZATION: Cache for verified Google tokens (5 min TTL)**
const googleTokenCache = new Map();
const CACHE_TTL = 5 * 60 * 1000; // 5 minutes

// **HIGH-PERFORMANCE: Cache MongoDB _id mapping (10 min TTL)**
const userObjectIdCache = new Map();
const ID_CACHE_TTL = 10 * 60 * 1000;

const getMemoizedUserExtras = async (googleId) => {
    if (!googleId) return null;
    const cached = userObjectIdCache.get(googleId);
    if (cached && (Date.now() - cached.timestamp < ID_CACHE_TTL)) {
        return cached.data;
    }
    const user = await User.findOne({ googleId }).select('_id appVersion').lean();
    if (user) {
        const data = { _id: user._id.toString(), appVersion: user.appVersion || 'unknown' };
        userObjectIdCache.set(googleId, { data, timestamp: Date.now() });
        return data;
    }
    return null;
};

export const verifyGoogleToken = async (idToken) => {
    // 1. Check cache first
    const cached = googleTokenCache.get(idToken);
    if (cached && (Date.now() - cached.timestamp < CACHE_TTL)) {
        return cached.payload;
    }

    const googleClient = await getGoogleClient();
    const ticket = await googleClient.verifyIdToken({
        idToken,
        audience: GOOGLE_CLIENT_ID,
    });
    const payload = ticket.getPayload();
    
    // 2. Update cache
    googleTokenCache.set(idToken, {
        payload,
        timestamp: Date.now()
    });

    // 3. Periodic cleanup (optional, but good for memory)
    if (googleTokenCache.size > 1000) {
        const now = Date.now();
        for (const [key, value] of googleTokenCache.entries()) {
            if (now - value.timestamp > CACHE_TTL) {
                googleTokenCache.delete(key);
            }
        }
    }
    
    return payload;
};

export const generateJWT = (userId, expiresIn = '1m') => {
    const JWT_SECRET = process.env.JWT_SECRET || config.auth.jwtSecret;
    const payload = { id: userId };
    const token = jwt.sign(payload, JWT_SECRET, { expiresIn });
    
    return token;
};

// NOTE: Refresh tokens are now handled by the RefreshToken MongoDB model
// with device-binding and secure hashing. See models/RefreshToken.js

// Verify JWT access token (used internally)
export const verifyJWT = (token) => {
    try {
        const JWT_SECRET = process.env.JWT_SECRET || config.auth.jwtSecret;
        const decoded = jwt.verify(token, JWT_SECRET);
        return decoded;
    } catch (error) {
        return null;
    }
};

// **NEW: Helper to update lastActive timestamp**
// Updates asynchronously without blocking the request
// Only updates if more than 5 minutes have passed to reduce DB load
const updateLastActive = async (googleId) => {
    try {
        if (!googleId) return;
        
        // Update only if lastActive is older than 5 minutes
        const fiveMinutesAgo = new Date(Date.now() - 5 * 60 * 1000);
        
        await User.updateOne(
            { 
                googleId,
                $or: [
                    { lastActive: { $lt: fiveMinutesAgo } },
                    { lastActive: { $exists: false } }
                ]
            },
            { $set: { lastActive: new Date() } }
        );
    } catch (error) {
        // Silently fail - don't block request if lastActive update fails
        console.log('⚠️ Failed to update lastActive:', error.message);
    }
};

// Middleware to verify Google access token
// **OPTIMIZED: Reduced logging - only log specific errors to prevent log spam**
export const verifyToken = async (req, res, next) => {
    try {
        const token = req.headers.authorization?.split(' ')[1];
        
        if (!token) {
            return res.status(401).json({ error: 'Access token required' });
        }

        const JWT_SECRET = process.env.JWT_SECRET || config.auth.jwtSecret;

        // **HIGH-PERFORMANCE AUTH: Check for local JWT first (< 1ms)**
        try {
            const decoded = jwt.verify(token, JWT_SECRET);
            
            const userExtras = await getMemoizedUserExtras(decoded.id);
            req.user = {
                ...decoded,
                googleId: decoded.id, 
                _id: userExtras?._id,
                appVersion: userExtras?.appVersion
            };
            
            // **NEW: Track user activity**
            updateLastActive(decoded.id).catch(() => {}); // Fire and forget
            
            return next(); // Fast-path: Skip Google API call
        } catch (jwtError) {
            // Log specific JWT verification errors for debugging
            if (jwtError.name === 'TokenExpiredError') {
                console.log('⚠️ JWT Token expired:', jwtError.expiredAt);
                return res.status(401).json({ error: 'Invalid or expired token', code: 'TOKEN_EXPIRED' });
            } else if (jwtError.name === 'JsonWebTokenError') {
                console.log('❌ JWT Token invalid signature/malformed:', jwtError.message);
                // If it looks like a JWT but is malformed, return 401 immediately
                if (token.startsWith('ey')) {
                    return res.status(401).json({ error: 'Invalid or expired token', code: 'TOKEN_INVALID' });
                }
            } else {
                console.log('❓ JWT Token verification failed (Generic):', jwtError.message);
            }
        }

        // Second, try to verify as Google access token using Google People API (850ms+)
        try {
            // Use the token to get user info from Google
            const response = await fetch(`https://www.googleapis.com/oauth2/v2/userinfo?access_token=${token}`);
            
            if (response.ok) {
                const userInfo = await response.json();
                const userExtras = await getMemoizedUserExtras(userInfo.id);
                req.user = { 
                    id: userInfo.id,
                    googleId: userInfo.id,
                    _id: userExtras?._id,
                    appVersion: userExtras?.appVersion,
                    email: userInfo.email,
                    name: userInfo.name
                };
                
                // **NEW: Track user activity**
                updateLastActive(userInfo.id).catch(() => {});
                
                return next();
            } else {
                const errorData = await response.text();
                // Don't throw yet, try ID token next
            }
        } catch (accessTokenError) {
            // Fail silently and try ID token next
        }

        // Fallback: try to verify as Google ID token
        try {
            const googleClient = await getGoogleClient();
            const ticket = await googleClient.verifyIdToken({
                idToken: token,
                audience: GOOGLE_CLIENT_ID,
            });
            
            const payload = ticket.getPayload();
            const userExtras = await getMemoizedUserExtras(payload.sub);
            req.user = { 
                id: payload.sub,
                googleId: payload.sub,
                _id: userExtras?._id,
                appVersion: userExtras?.appVersion,
                email: payload.email,
                name: payload.name
            };
            
            // **NEW: Track user activity**
            updateLastActive(payload.sub).catch(() => {});
            
            return next();
        } catch (idTokenError) {
            // All verification methods failed
            console.log('❌ Token verification failed - all methods exhausted');
            console.log('🔍 Token prefix:', token.substring(0, 15) + '...');
            console.log('🔍 JWT Secret configured:', !!JWT_SECRET);
            console.log('🔍 ID Token Error:', idTokenError.message);
            
            return res.status(401).json({ error: 'Invalid or expired token' });
        }
    } catch (error) {
        console.log('❌ Token verification error:', error.message);
        return res.status(401).json({ error: 'Invalid or expired token' });
    }
};


// **NEW: Passive Token Verification**
// Does NOT block request if token is missing/invalid.
// Just tries to set req.user so rate limiter can use it.
export const passiveVerifyToken = async (req, res, next) => {
    try {
        const token = req.headers.authorization?.split(' ')[1];
        
        if (!token) {
            return next(); // No token, just proceed as guest
        }

        // **HIGH-PERFORMANCE AUTH: Local JWT check first**
        try {
            const JWT_SECRET = process.env.JWT_SECRET || config.auth.jwtSecret;
            const decoded = jwt.verify(token, JWT_SECRET);
            const userExtras = await getMemoizedUserExtras(decoded.id);
            req.user = {
                ...decoded,
                googleId: decoded.id,
                _id: userExtras?._id,
                appVersion: userExtras?.appVersion
            };
            return next();
        } catch (e) { /* Fallback to Google */ }

        // Try Google Access Token (People API)
        try {
            const response = await fetch(`https://www.googleapis.com/oauth2/v2/userinfo?access_token=${token}`);
            if (response.ok) {
                const userInfo = await response.json();
                const userExtras = await getMemoizedUserExtras(userInfo.id);
                req.user = { 
                    id: userInfo.id,
                    googleId: userInfo.id,
                    _id: userExtras?._id,
                    appVersion: userExtras?.appVersion,
                    email: userInfo.email,
                    name: userInfo.name
                };
                return next();
            }
        } catch (e) { /* Ignore */ }

        // Try ID Token
        try {
            const googleClient = await getGoogleClient();
            const ticket = await googleClient.verifyIdToken({
                idToken: token,
                audience: GOOGLE_CLIENT_ID,
            });
            const payload = ticket.getPayload();
            const userExtras = await getMemoizedUserExtras(payload.sub);
            req.user = { 
                id: payload.sub,
                googleId: payload.sub,
                _id: userExtras?._id,
                appVersion: userExtras?.appVersion,
                email: payload.email,
                name: payload.name
            };
            return next();
        } catch (e) { /* Ignore */ }

        // If all fail, just proceed without req.user
        return next();

    } catch (error) {
        // Safety net - never block in passive mode
        return next();
    }
};

export default verifyToken;
