// Validation middleware for common input validation

export const validateCampaignData = (req, res, next) => {
  const { name, objective, startDate, endDate, dailyBudget } = req.body;

  // Validate required fields
  if (!name || !objective || !startDate || !endDate || !dailyBudget) {
    return res.status(400).json({ 
      error: 'Missing required fields',
      required: ['name', 'objective', 'startDate', 'endDate', 'dailyBudget']
    });
  }

  // Validate dates
  const start = new Date(startDate);
  const end = new Date(endDate);
  
  if (isNaN(start.getTime()) || isNaN(end.getTime())) {
    return res.status(400).json({ error: 'Invalid date format' });
  }
  
  if (start >= end) {
    return res.status(400).json({ error: 'End date must be after start date' });
  }

  // Validate budget
  if (dailyBudget < 100) {
    return res.status(400).json({ error: 'Daily budget must be at least ₹100' });
  }

  const { totalBudget } = req.body;
  if (totalBudget && totalBudget < 1000) {
    return res.status(400).json({ error: 'Total budget must be at least ₹1000' });
  }

  next();
};

export const validateAdData = (req, res, next) => {
  const { title, description, adType, budget, uploaderId } = req.body;

  // Validate required fields
  if (!title || !description || !adType || !budget || !uploaderId) {
    return res.status(400).json({ 
      error: 'Missing required fields',
      required: ['title', 'description', 'adType', 'budget', 'uploaderId']
    });
  }

  // Validate budget
  if (budget < 100) {
    return res.status(400).json({ error: 'Budget must be at least ₹100' });
  }

  next();
};

export const validatePagination = (req, res, next) => {
  const { page = 1, limit = 10 } = req.query;
  
  const pageNum = parseInt(page);
  const limitNum = parseInt(limit);
  
  if (isNaN(pageNum) || pageNum < 1) {
    return res.status(400).json({ error: 'Page must be a positive number' });
  }
  
  if (isNaN(limitNum) || limitNum < 1 || limitNum > 100) {
    return res.status(400).json({ error: 'Limit must be between 1 and 100' });
  }
  
  req.pagination = { page: pageNum, limit: limitNum };
  next();
};
