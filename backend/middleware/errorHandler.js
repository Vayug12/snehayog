// Centralized error handling middleware

export const errorHandler = (err, req, res, next) => {
  console.error('❌ Error occurred:', {
    message: err.message,
    stack: err.stack,
    url: req.url,
    method: req.method,
    timestamp: new Date().toISOString()
  });

  // Handle specific error types
  if (err.name === 'ValidationError') {
    return res.status(400).json({
      error: 'Validation Error',
      details: Object.values(err.errors).map(e => e.message)
    });
  }

  if (err.name === 'CastError') {
    return res.status(400).json({
      error: 'Invalid ID format',
      details: 'The provided ID is not valid'
    });
  }

  if (err.name === 'MulterError') {
    if (err.code === 'LIMIT_FILE_SIZE') {
      return res.status(400).json({
        error: 'File too large',
        details: 'File size exceeds the allowed limit'
      });
    }
    if (err.code === 'LIMIT_FILE_COUNT') {
      return res.status(400).json({
        error: 'Too many files',
        details: 'Only one file is allowed'
      });
    }
  }

  // Handle file type errors
  if (err.message && err.message.includes('Invalid file type')) {
    return res.status(400).json({
      error: 'Invalid file type',
      details: err.message
    });
  }

  // Default error response
  const statusCode = err.statusCode || 500;
  const message = err.message || 'Internal Server Error';

  res.status(statusCode).json({
    error: message,
    ...(process.env.NODE_ENV === 'development' && { stack: err.stack })
  });
};

// Async error wrapper to catch async errors
export const asyncHandler = (fn) => {
  return (req, res, next) => {
    Promise.resolve(fn(req, res, next)).catch(next);
  };
};

// Not found handler
export const notFoundHandler = (req, res) => {
  res.status(404).json({
    error: 'Route not found',
    url: req.url,
    method: req.method
  });
};

// Validation middleware for ad data
export const validateAdData = (req, res, next) => {
  const { title, description, targetAudience, budget, duration } = req.body;
  
  if (!title || !description || !targetAudience || !budget || !duration) {
    return res.status(400).json({
      error: 'Missing required fields',
      details: 'Title, description, target audience, budget, and duration are required'
    });
  }
  
  if (budget < 1 || budget > 1000) {
    return res.status(400).json({
      error: 'Invalid budget',
      details: 'Budget must be between ₹1 and ₹1000'
    });
  }
  
  next();
};
