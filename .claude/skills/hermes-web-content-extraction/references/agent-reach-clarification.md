# Agent-Reach Scope Clarification (2026-08-21)

## What Agent-Reach DOES (Free Channels)
| Channel | Tool | Notes |
|---------|------|-------|
| YouTube subtitles | `yt-dlp --write-auto-sub --sub-lang "pt,en" --skip-download --sub-format vtt` | Works without API key |
| YouTube transcription | `agent-reach transcribe <url>` | **Needs paid Groq key** → we don't use |
| RSS/Atom feeds | `curl <feed_url>` | Standard fetch |
| V2EX | Built-in | Chinese tech forum |
| GitHub | `gh` CLI | **Not installed**; needs `gh auth login` (Danilo action) |

## What Agent-Reach DOES NOT DO
- **Web page extraction** — NOT a channel
- **HTML → Markdown** — NOT a channel
- **Search engines** — NOT a channel

## Our Web Extraction Pipeline (Use This Instead)

### Primary: `readpage <url>`
```bash
# Wrapper at /usr/local/bin/readpage
readpage "https://example.com/article"
# → curl -s --max-time 60 "https://r.jina.ai/https://example.com/article"
# → Clean markdown (title, source, publish time, content)
```

### Fallback: `trafilatura` via `uv run`
```bash
uv run python3 -c "
import trafilatura
url = 'https://example.com/article'
d = trafilatura.fetch_url(url)
print(trafilatura.extract(d, output_format='markdown'))
"
```
- Installed: `uv pip install trafilatura` (persists in uv cache)
- Use when Jina blocks domain (paywall, anti-bot)

### Interactive: `browse "<url or task>"`
- Chromium on PC/VPS for JS-heavy sites, login, clicks

### Deep Research: `websearch` → `readpage`
1. `terminal: websearch "<query>"` → pick 3-5 best URLs
2. `terminal: readpage <url>` for each
3. Synthesize with sources

## Quick Decision Tree
```
Need to read a URL?          → readpage <url>
Jina 403/429?                → uv run trafilatura
Need JS/login/clicks?        → browse "<url>"
Search then read?            → websearch → readpage each
YouTube subtitles?           → yt-dlp (Agent-Reach)
RSS feed?                    → curl <feed_url>
```

## Related
- Skill: `web-content-extraction` (research) — full pipeline, validation, pitfalls
- Reference: `references/jina-reader-quickref.md`
- Reference: `references/trafilatura-patterns.md`