// Test the fixed DDG search
import { runSearch, research } from './src/research.js';

console.log('=== Test 1: Single DDG query ===');
try {
  const results = await runSearch('startup funding news 2026');
  console.log(`Got ${results.length} results`);
  results.forEach((r, i) => console.log(`  ${i + 1}. ${r.title}`));
} catch (e) {
  console.error('FAILED:', e.message);
}

console.log('\n=== Test 2: Full research flow ===');
try {
  const res = await research({ topic: 'startup funding', projectName: 'Snehayog/Vayug' });
  console.log(`Got ${res.results.length} unique results from ${res.provider}`);
  res.results.slice(0, 3).forEach((r, i) => console.log(`  ${i + 1}. ${r.title}`));
} catch (e) {
  console.error('FAILED:', e.message);
}
