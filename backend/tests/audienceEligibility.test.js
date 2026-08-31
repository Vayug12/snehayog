import {
  PROFESSIONS,
  isValidProfessionId,
  normalizeProfessionIds,
} from '../constants/professions.js';
import {
  buildProfessionEligibilityClause,
  isVideoEligibleForProfession,
} from '../services/audienceEligibilityService.js';

describe('profession catalogue', () => {
  test('contains more than 100 unique stable IDs', () => {
    const ids = PROFESSIONS.map((profession) => profession.id);
    expect(PROFESSIONS.length).toBeGreaterThan(100);
    expect(new Set(ids).size).toBe(ids.length);
    expect(isValidProfessionId('software_engineer')).toBe(true);
  });

  test('normalizes duplicate IDs and drops unknown values', () => {
    expect(normalizeProfessionIds([
      'software_engineer',
      'software_engineer',
      'unknown_role',
      'doctor',
    ])).toEqual(['software_engineer', 'doctor']);
  });
});

describe('profession feed eligibility', () => {
  test('untargeted and legacy videos are eligible for everyone', () => {
    expect(isVideoEligibleForProfession({}, null)).toBe(true);
    expect(isVideoEligibleForProfession({ targetProfessionIds: [] }, null))
      .toBe(true);
  });

  test('targeted video requires an exact profession match', () => {
    const video = { targetProfessionIds: ['software_engineer', 'doctor'] };
    expect(isVideoEligibleForProfession(video, 'software_engineer')).toBe(true);
    expect(isVideoEligibleForProfession(video, 'lawyer')).toBe(false);
    expect(isVideoEligibleForProfession(video, null)).toBe(false);
  });

  test('query clause only filters candidates and contains no scoring fields', () => {
    const clause = buildProfessionEligibilityClause('software_engineer');
    expect(clause).toEqual({
      $or: [
        { 'targetProfessionIds.0': { $exists: false } },
        { targetProfessionIds: 'software_engineer' },
      ],
    });
    expect(JSON.stringify(clause)).not.toMatch(/score|boost/i);
  });
});

