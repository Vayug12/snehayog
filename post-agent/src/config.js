import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const AGENT_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

async function loadDotEnv() {
  try {
    const text = await fs.readFile(path.join(AGENT_ROOT, '.env'), 'utf8');
    for (const line of text.split(/\r?\n/)) {
      const match = line.match(/^\s*([A-Z][A-Z0-9_]*)\s*=\s*(.*?)\s*$/);
      if (!match || match[1].startsWith('#') || process.env[match[1]]) continue;
      process.env[match[1]] = match[2].replace(/^['"]|['"]$/g, '');
    }
  } catch (error) {
    if (error.code !== 'ENOENT') throw error;
  }
}

await loadDotEnv();

// The agent has lived both beside the project (../snehayog) and inside it (..),
// so the root is discovered instead of hardcoded: walk up from the agent and
// accept the first candidate that actually carries the context files.
const ROOT_MARKERS = ['backend/public/llm.txt', 'backend/public/monetization.json'];
const ROOT_SEARCH_DEPTH = 4;

async function hasMarker(candidate) {
  for (const marker of ROOT_MARKERS) {
    try {
      await fs.access(path.join(candidate, ...marker.split('/')));
      return true;
    } catch (error) {
      if (error.code !== 'ENOENT') throw error;
    }
  }
  return false;
}

async function resolveProjectRoot() {
  if (process.env.POST_AGENT_PROJECT_ROOT) {
    return path.resolve(process.env.POST_AGENT_PROJECT_ROOT);
  }

  let directory = AGENT_ROOT;
  for (let depth = 0; depth <= ROOT_SEARCH_DEPTH; depth += 1) {
    for (const candidate of [directory, path.join(directory, 'snehayog')]) {
      if (await hasMarker(candidate)) return candidate;
    }
    const parent = path.dirname(directory);
    if (parent === directory) break;
    directory = parent;
  }

  // Nothing matched; keep the historical default so context.js reports the path.
  return path.join(AGENT_ROOT, '..');
}

export const PROJECT_ROOT = await resolveProjectRoot();

export const OUTPUT_ROOT = path.join(AGENT_ROOT, 'output');
export const DATA_ROOT = path.join(AGENT_ROOT, '.data');
export const HISTORY_FILE = path.join(DATA_ROOT, 'history.jsonl');

export const PROVIDERS = ['opencode', 'codex', 'claude-code', 'claude'];
export const PLATFORMS = ['linkedin', 'x', 'reddit', 'substack'];

// Order matters: context.js loads these in sequence and trims the tail once the
// total budget is reached, so the audience-facing product facts come first.
// Internal architecture docs are deliberately excluded — posts are for creators,
// not engineers, and those docs used to crowd out llm.txt entirely.
export const PROJECT_FILES = [
  'backend/public/llm.txt',
  'backend/public/monetization.json',
  'README.md',
];

// Two jobs: the fallback rotation when live topic discovery fails, and the
// "angle territory" sample fed into buildTopicPrompt. Each entry goes straight
// into web search and into the post prompt as the assignment, so keep them
// problem-shaped and 5-12 words — not slogans, not feature names. Every entry
// should map to something documented in llm.txt or monetization.json.
export const TOPIC_BANK = [
  // Core positioning
  'creator monetization and fair revenue sharing',
  'one home for short-form and long-form video creators',
  'helping creators build an audience instead of chasing fragmented platforms',
  'a creator-first alternative to generic video platforms',
  'making video publishing and discovery simpler for creators',
  'the gap between uploading videos and earning sustainably',
  'building a healthier creator economy around video',

  // Monetization and payouts
  'why creators cannot see how their payout is calculated',
  'what an 80/20 ad revenue split changes for small creators',
  'the lag between earning ad revenue and getting paid',
  'UPI payouts versus slow international transfers for Indian creators',
  'monetization thresholds that lock out early-stage creators',
  'why creator earnings dashboards are so hard to trust',
  'revenue share versus the promise of guaranteed creator income',
  'creators depending entirely on brand deals for income',
  'monthly payout cadence and creator cash-flow planning',

  // Audience ownership and the subscriber relationship
  'creators renting their audience from recommendation algorithms',
  'why creators should be able to export their subscriber list',
  'what happens to a creator when an account is suddenly banned',
  'moving followers from a platform feed to a direct channel',
  'push notifications versus newsletters for reaching subscribers',
  'notification fatigue and limits on how often creators broadcast',
  'the real cost of platform dependence for full-time creators',
  'why organic target audience reach is paywalled behind Instagram boost ads',
  'letting creators target relevant viewer professions without paying for ads',
  'why creators must pay platforms just to reach their intended niche',

  // Short-form and long-form in one place
  'creators forced to split short-form and long-form audiences',
  'turning short-form viewers into long-form watch time',
  'why episodic series struggle inside an infinite scroll feed',
  'the creative cost of chasing short-form virality',
  'resuming a long video where you left off on mobile',
  'building a back catalogue that keeps earning after upload day',
  'mobile video platforms trapping viewers inside proprietary media players',
  'watching long-form videos inside your favorite external player on Android',

  // Discovery and recommendations
  'small creators being invisible in engagement-ranked feeds',
  'semantic search making older videos discoverable again',
  'why video metadata and tags decide who ever sees a video',
  'recommendation signals creators can actually influence',
  'discovery for regional-language video outside major languages',
  'the tradeoff between personalization and creator reach',

  // AI and language
  'what AI dubbing changes for regional-language creators',
  'auto-generated transcripts as an accessibility baseline for video',
  'AI summaries helping viewers decide what to watch',
  'where AI actually helps a creator workflow and where it does not',
  'translated captions versus synthetic voice dubbing for reach',
  'AI-assisted video generation and the authenticity question',
  'creators worrying that AI tools will flatten their voice',

  // Privacy, encryption, exclusive content
  'paywalled creator content the platform can still read',
  'end-to-end encrypted video for subscriber-only content',
  'what exclusive really means when hosting is not private',
  'sharing private content with subscribers without it leaking',
  'the security tradeoffs of subscriber-only video access',

  // Advertisers and the ad side
  'small advertisers priced out of self-serve video campaigns',
  'why brands cannot tell which creator content earned a click',
  'ad load and viewer tolerance on mobile video feeds',
  'connecting advertiser spend to creator earnings transparently',
  'local businesses advertising to regional-language audiences',

  // Creator workflow and publishing friction
  'the wait between hitting upload and a video going live',
  'video transcoding time as a hidden creator productivity cost',
  'creators re-editing the same video for every platform',
  'thumbnail and title decisions made under upload pressure',
  'running an entire creator business from a phone',
  'analytics that say what to do next, not just what happened',

  // Trust, safety, reliability
  'moderation decisions creators cannot appeal or understand',
  'reporting and safety flows that protect creators too',
  'platform outages and the creators who lose a launch day',
  'what creators deserve to know before uploading somewhere new',

  // Building in public
  'what building a video platform teaches about creator economics',
  'shipping a creator platform as a small independent team',
  'why new video platforms fail to attract their first creators',
  'designing creator monetization before you have scale',
  'India-first product decisions in a global video market',

  // Engagement and retention
  'in-video quizzes turning passive watching into participation',
  'comments and community as a creator retention tool',
  'referral loops as an honest growth channel for creators',
];

export const DEFAULT_PROVIDER = process.env.POST_AGENT_PROVIDER || 'opencode';

export const PROVIDER_MODELS = {
  opencode: process.env.POST_AGENT_OPENCODE_MODEL,
  codex: process.env.POST_AGENT_CODEX_MODEL,
  'claude-code': process.env.POST_AGENT_CLAUDE_CODE_MODEL,
  claude: process.env.POST_AGENT_CLAUDE_MODEL || 'claude-sonnet-5',
};

export const TRENDING_CATEGORIES = {
  ai: {
    name: 'AI & Machine Learning',
    queries: ['artificial intelligence news this week', 'AI startup trends latest', 'generative AI breakthroughs'],
    hashtags: ['#AI', '#MachineLearning', '#GenerativeAI', '#LLM', '#ArtificialIntelligence'],
  },
  technology: {
    name: 'Technology',
    queries: ['technology news today', 'tech industry trends', 'latest tech product launches'],
    hashtags: ['#Technology', '#TechNews', '#Innovation', '#DigitalTransformation'],
  },
  startup: {
    name: 'Startups',
    queries: ['startup funding news this week', 'new startup launches', 'founder stories startup'],
    hashtags: ['#Startup', '#Founders', '#VentureCapital', '#StartupLife'],
  },
  'indian startup': {
    name: 'Indian Startups',
    queries: ['Indian startup funding news', 'India tech startup news', 'Indian founders stories'],
    hashtags: ['#IndiaStartup', '#MadeInIndia', '#BharatTech', '#IndianFounders'],
  },
  'creator economy': {
    name: 'Creator Economy',
    queries: ['creator economy news', 'creator monetization trends', 'social media creator updates'],
    hashtags: ['#CreatorEconomy', '#CreatorMonetization', '#ContentCreators'],
  },
  'digital marketing': {
    name: 'Digital Marketing',
    queries: ['digital marketing trends latest', 'social media marketing news', 'SEO algorithm updates'],
    hashtags: ['#DigitalMarketing', '#MarketingTrends', '#SocialMediaMarketing'],
  },
  fintech: {
    name: 'Fintech',
    queries: ['fintech news this week', 'digital payments trends', 'neobank latest updates'],
    hashtags: ['#Fintech', '#DigitalPayments', '#BankingTech'],
  },
  edtech: {
    name: 'EdTech',
    queries: ['edtech news latest', 'online learning trends', 'education technology updates'],
    hashtags: ['#EdTech', '#OnlineLearning', '#FutureOfEducation'],
  },
  saas: {
    name: 'SaaS',
    queries: ['SaaS news this week', 'B2B software trends', 'SaaS company updates'],
    hashtags: ['#SaaS', '#B2B', '#SoftwareAsAService'],
  },
  web3: {
    name: 'Web3 & Blockchain',
    queries: ['web3 news latest', 'blockchain technology updates', 'crypto market trends'],
    hashtags: ['#Web3', '#Blockchain', '#Crypto', '#Decentralized'],
  },
  sustainability: {
    name: 'Sustainability',
    queries: ['sustainability news this week', 'green tech trends', 'climate tech updates'],
    hashtags: ['#Sustainability', '#GreenTech', '#ClimateAction'],
  },
};
