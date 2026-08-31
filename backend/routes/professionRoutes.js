import express from 'express';
import { PROFESSIONS } from '../constants/professions.js';

const router = express.Router();

router.get('/', (req, res) => {
  res.set('Cache-Control', 'public, max-age=3600, stale-while-revalidate=86400');
  return res.json({ professions: PROFESSIONS });
});

export default router;
