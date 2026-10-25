# Jina Reader Quick Reference

## Endpoint
```
https://r.jina.ai/<FULL_URL>
```
- No API key required
- Returns markdown with: Title, URL Source, Published Time, Markdown Content

## Parameters (append as query string)
| Param | Values | Description |
|-------|--------|-------------|
| `format` | `text`, `markdown` (default) | Output format |
| `timeout` | `10`-`60` (default 30) | Fetch timeout seconds |
| `no-cache` | `true` | Bypass cache, fetch fresh |
| `with-links` | `true` | Preserve links in markdown |
| `with-images` | `true` | Preserve images in markdown |
| `selector` | CSS selector | Extract only matching element |

## Example Calls
```bash
# Basic
curl -s "https://r.jina.ai/https://example.com/article"

# Fresh fetch, keep links
curl -s "https://r.jina.ai/https://example.com/article?no-cache=true&with-links=true"

# Extract only main content
curl -s "https://r.jina.ai/https://example.com/article?selector=article.main-content"
```

## Rate Limits
- Free tier: generous, undocumented burst
- 429 = back off 30-60s
- No hard quota published

## Error Codes
| Code | Meaning |
|------|---------|
| 200 | OK |
| 400 | Bad URL |
| 403 | AbuseAlleviationError (domain blocked for abuse) |
| 404 | Jina couldn't fetch |
| 429 | Rate limited |
| 5xx | Jina internal error |

## Domains Known to Block Jina
- nytimes.com, wsj.com, ft.com (paywalls)
- Some Cloudflare-protected sites
- Heavy anti-bot sites

## Our Wrapper
`/usr/local/bin/readpage`:
```sh
#!/bin/sh
if [ -z "$1" ]; then echo "uso: readpage <url>"; exit 2; fi
exec curl -s --max-time 60 "https://r.jina.ai/$1"
```
Usage: `readpage "https://example.com"`