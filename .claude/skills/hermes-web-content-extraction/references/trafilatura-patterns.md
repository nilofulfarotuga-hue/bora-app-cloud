# Trafilatura Patterns — Quick Reference

## Installation
```bash
uv pip install trafilatura
# Persists in uv cache, survives container recreate
```

## Basic Extraction
```python
import trafilatura

url = "https://example.com/article"
downloaded = trafilatura.fetch_url(url)
markdown = trafilatura.extract(downloaded, output_format='markdown')
print(markdown)
```

## With Metadata
```python
result = trafilatura.extract(
    downloaded,
    output_format='markdown',
    include_metadata=True,
    include_comments=False,
    include_tables=True,
    include_images=True,
    no_fallback=False
)
# Returns dict with: title, author, date, categories, tags, fingerprint, etc.
```

## Via uv run (one-liner for terminal)
```bash
uv run python3 -c "
import trafilatura
url = 'https://news.ycombinator.com'
d = trafilatura.fetch_url(url)
print(trafilatura.extract(d, output_format='markdown')[:1000])
"
```

## Feed Extraction (RSS/Atom/sitemap)
```python
# Get all article URLs from a feed
feed_urls = trafilatura.extract_feed("https://example.com/feed.xml")
# feed_urls is a list of dicts: {url, title, date, ...}

# Extract all articles
for item in feed_urls:
    d = trafilatura.fetch_url(item['url'])
    text = trafilatura.extract(d, output_format='markdown')
    # process...
```

## Sitemap Discovery
```python
sitemap_urls = trafilatura.extract_sitemap("https://example.com/sitemap.xml")
# Returns list of URLs
```

## Common Options
| Option | Default | Description |
|--------|---------|-------------|
| `output_format` | `'txt'` | `'txt'`, `'markdown'`, `'json'`, `'xml'` |
| `include_metadata` | `False` | Include title, author, date in output |
| `include_comments` | `False` | Include comments section |
| `include_tables` | `True` | Convert HTML tables to markdown |
| `include_images` | `True` | Keep image references |
| `no_fallback` | `False` | Skip readability fallback |
| `target_language` | `None` | Filter by language (e.g., 'pt', 'en') |
| `url_blacklist` | `[]` | List of URL patterns to skip |

## Output Formats
- **txt**: Plain text, no formatting
- **markdown**: Clean markdown (best for LLM consumption)
- **json**: Structured dict with all fields
- **xml**: TEI XML (academic/archival)

## When to Prefer Over Jina
| Scenario | Why trafilatura |
|----------|-----------------|
| Jina 403/429 | Local fetch, no shared IP reputation |
| Need metadata | Rich metadata dict (author, date, tags) |
| Feed/sitemap crawling | Built-in `extract_feed`, `extract_sitemap` |
| Programmatic control | Full Python API, post-processing |
| Offline/cached HTML | `extract(html_string, ...)` works on raw HTML |

## Pitfalls
- **JS-rendered content**: Won't work (static fetch only) → use `browse`
- **Heavy Cloudflare**: May fail on challenge pages
- **List/index pages**: Extracts main content area, may miss sidebar links
- **Encoding**: Handles most, but rare edge cases need `response.encoding` fix

## Quick Test
```bash
# Should return clean article text
uv run python3 -c "
import trafilatura
print(trafilatura.extract(trafilatura.fetch_url('https://www.bbc.com/news/articles/cx2k1k9l9lvo'), output_format='markdown')[:300])
"
```