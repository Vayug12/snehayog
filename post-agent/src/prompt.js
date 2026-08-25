const HISTORY_LIMIT = 20;

const PLATFORM_RULES = {
  linkedin: `Write a thoughtful LinkedIn post. Start with a strong observation or hook, explain the problem, connect it to the project, and end with a conversational question or restrained CTA. Use short paragraphs. Avoid corporate jargon. Target 180-300 words.`,
  x: `Write an X post or short thread. Make the first line stand alone as a hook. Use concise, conversational language. If a thread helps, number it clearly with 1/, 2/, etc. Target 1-5 short posts and stay within normal X post length.`,
  reddit: `Write a natural Reddit-style post. Use an honest title followed by a useful, non-promotional body. Discuss the problem, what the project is trying, and invite criticism or experience from the community. Do not sound like an advertisement. Target 180-350 words.`,
  substack: `Write a Substack-style mini-essay with a clear title, a strong opening, a few descriptive section headings, and a reflective conclusion. Explain the problem and how the project approaches it. Target 500-800 words.`,
};

const PLATFORM_AUDIENCE = {
  linkedin: `Founders, operators, and creators building a business. They care about the economics and the decision behind a product, not its implementation.`,
  x: `Creators and indie builders scrolling fast. They will read the first line and nothing else unless it earns them.`,
  reddit: `Working creators who will smell a pitch instantly and downvote it. They reward honesty about what does not work yet.`,
  substack: `Readers who opted in for the argument, not the announcement. They will follow a longer line of reasoning if it goes somewhere.`,
};

function recentTopics(history, emptyMessage) {
  const recent = history.slice(-HISTORY_LIMIT);
  return recent.length
    ? recent.map((item) => `- ${item.platform}: ${item.topic || item.title}`).join('\n')
    : emptyMessage;
}

// A random slice rather than the whole bank: it keeps the model inside the
// project's real problem space without letting one run's angles repeat the next.
export function sampleTopicTerritory(bank, count = 12) {
  const pool = [...bank];
  for (let i = pool.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [pool[i], pool[j]] = [pool[j], pool[i]];
  }
  return pool.slice(0, count);
}

export function buildTopicPrompt({ platform, context, history, territory = [] }) {
  const previous = recentTopics(history, 'No previous topics are available.');
  const territoryBlock = territory.length
    ? `PROBLEM TERRITORY
These are the kinds of problems this project sits in. Treat them as territory to explore, not phrases to copy. Pick a specific angle inside or adjacent to one of them.

${territory.map((item) => `- ${item}`).join('\n')}`
    : '';

  return `You are the topic strategist for the Snehayog/Vayug project.

Suggest one fresh, specific content angle for a ${platform} post. Think about a real creator or video-platform problem that is relevant to this project, then turn it into a concise topic for research. Choose a different angle from the recent topics below.

AUDIENCE
${PLATFORM_AUDIENCE[platform]}

PROJECT CONTEXT
${context.text}

${territoryBlock}

RECENT TOPICS TO AVOID
${previous}

Pick a problem a real creator, viewer, or advertiser would recognise, and one this project's documented features actually speak to. Do not propose a topic about internal engineering, architecture, or infrastructure.

Return only one concise topic phrase, between 4 and 12 words. Do not write the post, explain your choice, or invent a feature or result.`;
}

export function buildPrompt({ platform, topic, context, research, history }) {
  const sources = research.results
    .map((item, index) => `${index + 1}. ${item.title}\nURL: ${item.url}\nEvidence: ${item.snippet || 'No snippet available'}${item.published ? `\nDate: ${item.published}` : ''}`)
    .join('\n\n');
  const previous = recentTopics(history, 'No previous posts are available.');

  return `You are the research-first social content writer for the Snehayog/Vayug project.

PLATFORM
${PLATFORM_RULES[platform]}

AUDIENCE
${PLATFORM_AUDIENCE[platform]}

ASSIGNMENT
Create a fresh post about: ${topic}

PROJECT FACTS
Use only facts supported by the project context below. The app is currently being built; do not claim user growth, revenue results, adoption, or completed functionality unless the context explicitly supports it. Say "is building", "is designed to", or "aims to" when describing intended outcomes.

${context.text}

WEB RESEARCH
Use the research to understand the real-world problem and current conversation. Do not copy wording. Do not treat an external source as proof that Snehayog has solved the problem. Explain the honest connection between the researched problem and the project's documented features.

${sources}

RECENT POST TOPICS TO AVOID REPEATING
${previous}

OUTPUT RULES
- Return only the final post. No analysis, source list, markdown fences, or preamble.
- Do not invent features, metrics, customer stories, quotes, or statistics.
- Prefer qualitative findings from web research. Do not include exact external numbers, market-size claims, or statistics unless the post itself names or links the source; otherwise leave them out.
- Do not write phrases such as "2026 data shows" or "research proves" without an inline source. Avoid asserting the absence of algorithms, fees, or platform limitations unless the project context documents that fact.
- Do not imply that web research measured Vayug's impact.
- Write for the audience above, not for engineers. Do not describe internal architecture, database models, caching, feature flags, deployment, or other implementation details.
- Make the project connection concrete and specific: name the actual capability, not "the platform".
- Keep the tone human, clear, and useful.

HASHTAG RULES
- End every post with 3-5 relevant hashtags on a new line after the main content.
- Hashtags must be specific to the post's topic, not generic.
- Use a mix of broad and niche hashtags. At least one hashtag should reference the creator economy, video, or the platform's space (e.g., #CreatorEconomy, #VideoPlatform, #CreatorMonetization). The rest should relate to the specific problem or theme discussed.
- Never repeat the same hashtag combination across different posts. Vary them based on the topic.
- Keep hashtags concise (1-3 words each). Do not use hashtag phrases longer than 4 words.
- Example format at the end of a post:
\n#CreatorEconomy #FairPayouts #VideoCreators
`;
}

export function buildCritiquePrompt({ platform, topic, context, post }) {
  return `You are the editor for the Snehayog/Vayug project's social content. Review the draft post below and return a corrected version.

PLATFORM
${PLATFORM_RULES[platform]}

AUDIENCE
${PLATFORM_AUDIENCE[platform]}

TOPIC
${topic}

PROJECT FACTS
Every product claim in the post must be supported by this context. Nothing else is verified.

${context.text}

DRAFT POST
${post}

CHECK EACH OF THESE
1. Does the first line stand alone as a hook, or is it a throat-clearing preamble?
2. Does the post state any feature, metric, customer story, quote, or statistic that the PROJECT FACTS do not support? Remove or soften it.
3. Does it give an external number, market-size claim, or research finding without naming its source inline? Remove it.
4. Does it claim proven results, adoption, usage, or revenue for a product still being built? This includes any phrasing that implies existing users or activity — "creators on Vayug are using X", "users report", "we've seen", "X is helping creators". No such claim is supported. Rewrite in terms of what the capability is designed to do for a creator, using "is building", "is designed to", "aims to", or "lets creators".
5. Does it describe internal architecture, database models, caching, feature flags, or deployment? That is wrong for this audience. Replace it with what the capability means for the reader.
6. Is the project connection concrete, naming an actual documented capability, rather than a generic reference to "the platform"?
7. Does it fit the platform's length and tone rules above?
8. Does the post end with 3-5 relevant, topic-specific hashtags? If missing or generic, add appropriate ones. If hashtags are repetitive or too broad, replace with more specific ones.

Fix every problem you find. If the draft already passes all eight checks, return it unchanged.

Return only the final post text. No commentary, no scores, no list of changes, no markdown fences.`;
}

export function buildTrendingPrompt({ platform, category, topic, newsItems, suggestedHashtags, context, research, history }) {
  const sources = research.results
    .map((item, index) => `${index + 1}. ${item.title}\nURL: ${item.url}\nEvidence: ${item.snippet || 'No snippet available'}${item.published ? `\nDate: ${item.published}` : ''}`)
    .join('\n\n');

  const newsContext = newsItems
    .map((item, index) => `${index + 1}. ${item.title}\n${item.snippet || ''}`)
    .join('\n\n');

  const previous = recentTopics(history, 'No previous posts are available.');

  const projectFactsBlock = context.text
    ? `PROJECT FACTS
Use only facts supported by the project context below. The app is currently being built; do not claim user growth, revenue results, adoption, or completed functionality unless the context explicitly supports it. Say "is building", "is designed to", or "aims to" when describing intended outcomes.

${context.text}

`
    : '';

  return `You are a research-first social content writer.

PLATFORM
${PLATFORM_RULES[platform]}

AUDIENCE
${PLATFORM_AUDIENCE[platform]}

CATEGORY
${category}

ASSIGNMENT
Create a post about this trending topic in ${category}: ${topic}

Use the trending news below as context and inspiration. Connect the trending topic to the creator economy and video platforms. Make the post timely and relevant.

TRENDING NEWS
${newsContext}

${projectFactsBlock}WEB RESEARCH
Use the research to understand the real-world problem and current conversation. Do not copy wording. Do not treat an external source as proof that any single platform has solved the problem.

${sources}

RECENT POST TOPICS TO AVOID REPEATING
${previous}

OUTPUT RULES
- Return only the final post. No analysis, source list, markdown fences, or preamble.
- Do not invent features, metrics, customer stories, quotes, or statistics.
- Prefer qualitative findings from web research. Do not include exact external numbers.
- Make the post timely - reference current events or trends.
- Connect the trending topic to the creator economy and video platforms.
- Keep the tone human, clear, and useful.

HASHTAG RULES
- End every post with 3-5 relevant hashtags on a new line.
- Use these suggested hashtags as a starting point: ${suggestedHashtags.join(', ')}
- Add 1-2 topic-specific hashtags like #CreatorEconomy or #VideoPlatform.
- Vary hashtags based on the specific topic.
`;
}
