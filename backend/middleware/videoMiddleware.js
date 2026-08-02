import multer from 'multer';
import fs from 'fs';

/**
 * Data validation middleware to ensure consistent types
 */
export const validateVideoData = (req, res, next) => {
  try {
    // Validate numeric fields in request body
    if (req.body.likes !== undefined) {
      req.body.likes = parseInt(req.body.likes) || 0;
    }
    if (req.body.views !== undefined) {
      req.body.views = parseInt(req.body.views) || 0;
    }
    if (req.body.shares !== undefined) {
      req.body.shares = parseInt(req.body.shares) || 0;
    }
    if (req.body.duration !== undefined) {
      req.body.duration = parseInt(req.body.duration) || 0;
    }
    if (req.body.aspectRatio !== undefined) {
      req.body.aspectRatio = parseFloat(req.body.aspectRatio) || 9 / 16;
    }

    next();
  } catch (error) {
    console.error('❌ Data validation error:', error);
    res.status(400).json({
      error: 'Invalid data types in request',
      details: 'Numeric fields must be valid numbers'
    });
  }
};

// Multer disk storage to get original file first
const tempStorage = multer.diskStorage({
  destination: (req, file, cb) => {
    // Ensure uploads directory exists
    const uploadDir = 'uploads/';
    if (!fs.existsSync(uploadDir)) {
      fs.mkdirSync(uploadDir, { recursive: true });
    }
    cb(null, uploadDir);
  },
  filename: (req, file, cb) => {
    // Generate unique filename with timestamp
    const uniqueSuffix = Date.now() + '-' + Math.round(Math.random() * 1E9);
    cb(null, uniqueSuffix + '-' + file.originalname);
  },
});

export const upload = multer({
  storage: tempStorage,
  limits: {
    fileSize: 100 * 1024 * 1024, // 100MB limit (Server-side fallback; frontend uses presigned URLs)
  },
  fileFilter: (req, file, cb) => {
    // Check file type
    const allowedMimeTypes = ['video/mp4', 'video/avi', 'video/mov', 'video/wmv', 'video/flv', 'video/webm'];
    if (allowedMimeTypes.includes(file.mimetype)) {
      cb(null, true);
    } else {
      cb(new Error('Invalid file type. Only video files are allowed.'), false);
    }
  }
});
