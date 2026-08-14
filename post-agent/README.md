# Snehayog/Vayug Post Agent

A standalone, research-first content agent for the Snehayog/Vayug project. It lives beside `snehayog`, reads the project context, searches the web for the current problem, maps that problem to documented product capabilities, and generates a copy-ready post.

The default provider is **OpenCode**. This matches the MastUI pipeline pattern and can be changed per command.

## Setup

```powershell
cd C:\Users\sanje\apps\Vayu\post-agent
Copy-Item .env.example .env
```

No npm dependency install is required. Node 18+ is enough.

For generation, log in to at least one provider CLI:

```powershell
opencode auth login
codex login
claude login
```

### Set a Tavily key — this is the biggest quality lever

Web research works with no key through DuckDuckGo, but that path scrapes the HTML results page and returns thin, truncated snippets. Thin evidence produces generic posts. Tavily returns full structured summaries and publication dates, and it is what the prompt is written for:

```powershell
$env:TAVILY_API_KEY = "..."
```

Everything still runs without it — the output is just noticeably more generic.

## Commands

Generate one post:

```powershell
node generate.js linkedin
node generate.js linkedin "creator monetization"
node generate.js reddit "video discovery for creators"
node generate.js --platform substack --topic "building a creator-first video platform"
```

When no topic is provided, the selected AI provider automatically suggests a fresh project-relevant topic using the project context and previous post history. It then researches that topic on the web before writing the post.

Select a provider. If omitted, it is `opencode`:

```powershell
node generate.js x "short-form creator revenue" --provider opencode
node generate.js linkedin "creator monetization" --provider codex
node generate.js reddit "video discovery" --provider claude-code
node generate.js substack "creator economy" --provider claude
```

Generate a loop, using MastUI-style count and interval flags. `--interval` is in seconds:

```powershell
node auto-generate.js --loop --count 10 --interval 50
node auto-generate.js --loop --count 8 --interval 60 --platform all --provider opencode
```

`--platform all` rotates through LinkedIn, X, Reddit, and Substack. Without a topic, the agent rotates through a built-in topic bank and avoids recent topics using `.data/history.jsonl`.

Copy the generated post directly to the clipboard:

```powershell
node generate.js reddit "creator monetization" --copy
```

Skip the editor pass. Every post is normally reviewed by a second provider call that checks it for invented facts, unsourced numbers, weak hooks, and engineering detail that does not belong in a creator-facing post. `--no-critique` halves the provider calls at the cost of that check:

```powershell
node generate.js linkedin --no-critique
```

Inspect which project files are being used:

```powershell
npm run context
```

## Output

Every run creates a timestamped directory under `output/` containing:

- `post.md` — clean text to copy and paste
- `research.md` — search queries, evidence, and source URLs
- `metadata.json` — platform, provider, context files, and source metadata

The agent does not publish automatically.

## Grounding rules

The prompt instructs the provider to use only documented Snehayog/Vayug facts, distinguish planned capabilities from proven outcomes, avoid invented metrics and customer stories, and use web research to understand the problem rather than to falsely claim product impact.

Project context comes from `backend/public/llm.txt`, `backend/public/monetization.json`, and `README.md` — the audience-facing canonical facts. Internal architecture docs are deliberately excluded: posts are written for creators, viewers, and advertisers, and those docs used to crowd out the actual product facts and leak implementation detail into the output. If you add files to `PROJECT_FILES` in `src/config.js`, put them **after** the existing entries, since the context budget trims from the tail.

Each post is then reviewed by a second editor pass (`buildCritiquePrompt` in `src/prompt.js`) before it is saved. If that call fails for any reason, the original draft is kept rather than lost.

The project root defaults to `..\snehayog`. If the layout changes:

```powershell
$env:POST_AGENT_PROJECT_ROOT = "C:\path\to\snehayog"
```
