---
name: hermes-web-content-extraction
description: "Standard pipeline for extracting clean text/markdown from web pages. Covers the toolchain (readpage/Jina Reader, trafilatura, readability), validation patterns, and the Agent-Reach scope clarification."
category: research
tags:
  - web
  - extraction
  - jina-reader
  - trafilatura
  - agent-reach
  - readpage
  - research-pipeline
---

# Web Content Extraction — Standard Pipeline

## Trigger
Any task that needs to read a specific URL or search the web and extract clean content for analysis.

## The Pipeline (in order)

### 1. `readpage <url>` — **Primary extractor**
- Location: `/usr/local/bin/readpage` (shell wrapper)
- Backend: `https://r.jina.ai/<url>` (Jina Reader API)
- Cost: Free, no API key
- Output: Clean markdown with title, source URL, publish time
- Use for: **All single-URL reads** — news, blogs, docs, HN, etc.
- Example: `terminal: readpage "https://example.com/article"`

### 2. `trafilatura` via `uv run` — **Python fallback**
- Installed: `uv pip install trafilatura` (persists in uv cache)
- Call: `uv run python3 -c "import trafilatura; url='...'; d=trafilatura.fetch_url(url); print(trafilatura.extract(d, output_format='markdown'))"`
- Use when: Jina blocks a domain (paywall, anti-bot), or you need programmatic control
- Handles: Better main-content detection on some article sites

### 3. `readability-lxml` — **Installed but weak**
- `uv pip install readability-lxml requests`
- Extracts `doc.short_title()` and `doc.summary()` (HTML)
- **Pitfall:** Often returns empty body on JS-heavy or list pages (e.g., HN front page). Prefer trafilatura.

### 4. `websearch "<query>"` → `readpage` — **Deep research**
1. `terminal: websearch "<topic>"` → pick 3–5 best URLs
2. `terminal: readpage <url>` for each
3. Synthesize with sources cited
4. If too large/complex → `terminal: pc "<research task>"` (delegates to Claude Code)

## Agent-Reach Clarification (Critical)
**Agent-Reach does NOT extract web pages.** Its free channels:
- YouTube (subtitles via `yt-dlp`, transcription needs paid Groq key)
- RSS/Atom feeds (via `curl`)
- V2EX
- GitHub (needs `gh` CLI + auth — not installed)

Do NOT call `agent-reach` for web page extraction. Use `readpage` / `trafilatura`.

## Validation Pattern
Always test a new extractor on a known page before trusting it:
```bash
# Quick sanity check
readpage "https://news.ycombinator.com" | head -20
uv run python3 -c "import trafilatura; print(trafilatura.extract(trafilatura.fetch_url('https://news.ycombinator.com'), output_format='markdown')[:200])"
```

## Common Pitfalls
| Situation | What Happens | Fix |
|-----------|--------------|-----|
| Paywall (NYT, WSJ) | Jina returns 403 AbuseAlleviationError | Try trafilatura; if blocked, accept limitation |
| Cloudflare challenge | Both Jina and trafilatura may fail | No free workaround — flag as unextractable |
| JS-rendered content | Static fetch misses data | Use `browse` (Chromium on PC/VPS) for interactive pages |
| Rate limit | Jina returns 429 | Back off, retry; trafilatura as alternative |

## References
- `references/jina-reader-quickref.md` — Jina Reader endpoints, params, rate limits
- `references/trafilatura-patterns.md` — Common trafilatura call patterns, output formats

## Quick Reference Card
```
Need to read ONE url?     → readpage <url>
Need to search + read?    → websearch "query" → readpage each
Jina blocked?             → uv run trafilatura
Need JS/interaction?      → browse "<url or task>"
Deep research/report?     → pc "<research task>"
YouTube subtitles?        → yt-dlp (Agent-Reach)
RSS feed?                 → curl <feed_url>
```