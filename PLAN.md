# ruby.news — Plan (PHP → Lua on nginx)

## Goal

Convert 68k.news (a retro-computer-friendly HTML Google News aggregator) from PHP to Lua running on nginx with the [lua-nginx-module](https://github.com/openresty/lua-nginx-module). All output remains the same: minimal, Netscape-compatible HTML. The site name becomes "ruby.news" instead of "68k.news".

**Not OpenResty.** Plain nginx compiled with `--with-http_lua_module` (or installed via `nginx-extras` / `openresty` deb which bundles the module). Uses standalone `lua-resty-*` libraries, not the full OpenResty ecosystem.

---

## Architecture Overview

```
User → nginx (lua-nginx-module) → Lua handlers
                                  ├── Fetch Google News RSS (cached)
                                  ├── Decode Google News URLs (API call)
                                  ├── Fetch & extract article content (heuristic parser)
                                  └── Proxy images
```

**Runtime:** nginx + [lua-nginx-module](https://github.com/openresty/lua-nginx-module) + LuaJIT. No PHP, no web framework. Everything is nginx config + pure Lua modules using standalone `lua-resty-*` libraries.

---

## Project Structure

```
/home/ruby/Code/ruby-news/
├── nginx.conf                    # Main nginx config (with lua-nginx-module)
├── sites/
│   └── ruby.news.conf            # Server block (can be included)
├── lua/
│   ├── init.lua                  # Module loader / setup
│   ├── handlers/
│   │   ├── index.lua             # /index.php equivalent
│   │   ├── article.lua           # /article.php equivalent
│   │   ├── image.lua             # /image.php + /image_compressed.php equivalent
│   │   └── choose_edition.lua    # /choose_edition.php equivalent
│   ├── googlenews/
│   │   └── decoder.lua           # GoogleNewsDecoder class → Lua module
│   ├── rss/
│   │   └── fetcher.lua           # RSS feed fetching + parsing (SimplePie replacement)
│   ├── readability/
│   │   └── extract.lua           # Heuristic article content extractor
│   └── utils/
│       ├── string.lua            # clean_str(), common helpers
│       └── html.lua              # strip_tags, tag whitelisting
├── cache/                        # Optional file-based cache directory
├── README.md
└── Makefile                      # Build/deploy convenience commands
```

---

## Component Breakdown

### 1. nginx.conf (Server)

Single server block with location routing:

```
location /          → index.lua (default: US edition, all news)
location ~ ^/index$ → index.lua (with ?section=, ?loc=, ?lang= params)
location ~ ^/article$ → article.lua (with ?loc=, ?a= params)
location ~ ^/image$   → image.lua (with ?loc=, ?i= params)
location ~ ^/image_compressed$ → image.lua (compressed mode)
location ~ ^/choose_edition$ → choose_edition.lua
```

All routes serve the same minimal HTML output. No static files needed — everything is dynamic Lua.

### 2. `lua/handlers/index.lua` — Main news feed page

**What it does:**
- Accepts query params: `section`, `loc`, `lang` (from original `$_GET`)
- Builds Google News RSS URL based on section/loc/lang
- Fetches & parses the RSS feed via `lua/rss/fetcher.lua`
- Loops through items and renders HTML list of headlines + descriptions
- Navigation bar: TOP, WORLD, NATION, BUSINESS, TECHNOLOGY, etc.
- Edition selector link

**Key changes from PHP:**
- SimplePie → `lua/rss/fetcher.lua` (custom RSS parser using lua-xml-parser or built-in cjson for Google's JSON feed)
- Add caching: store RSS response in `ngx.shared.DICT` for configurable TTL (e.g., 5-10 min)
- Template rendering stays minimal — direct `ngx.say()` calls to output HTML

**Caching strategy:**
```lua
local cache = ngx.shared.news_cache  -- configured in nginx.conf
local cached = cache:get(feed_key)
if cached then
    return send_cached_response(cached)
end
-- fetch from Google News...
cache:set(feed_key, response_body, ttl)  -- e.g. 300 seconds
```

### 3. `lua/handlers/article.lua` — Article detail page

**What it does:**
- Accepts query params: `loc`, `a` (article URL)
- Validates URL starts with `https://news.google.com`
- Calls `lua/googlenews/decoder.lua` to decode the Google News URL → real article URL
- Fetches the article page via HTTP
- Runs it through `lua/readability/extract.lua` to extract the main article content
- Strips tags to whitelisted set, converts `<strong>` → `<b>`, `<em>` → `<i>`
- Lists images as numbered links pointing to `/image.php?i=`

**Key changes from PHP:**
- `file_get_contents()` → `resty.http` library
- Content extraction: `lua/readability/extract.lua` — heuristic-based approach (not a full Readability port)
- Google News URL decoding stays the same logic (base64 extraction → params fetch → batchexecute POST)

### 4. `lua/handlers/image.lua` — Image proxy

**What it does:**
- Accepts query param: `i` (image URL), `loc`, and optional `compressed` mode
- Validates image is jpg/jpeg/png and starts with http
- Fetches the image from the source URL
- In compressed mode: optionally resize/downscale for slow connections
- Streams image data back as `image/jpeg` or `image/png`

**Note:** The original `image_compressed.php` appears to just proxy images. Compression (resizing) can be added later if needed — start with direct proxy first.

### 5. `lua/handlers/choose_edition.lua` — Country selector

**What it does:**
- Static page listing all supported country editions as links
- Very simple — no dynamic data fetching

**Key change from PHP:**
- Entirely static HTML, no HTTP calls needed. Can even be a template file served directly by nginx if desired.

### 6. `lua/googlenews/decoder.lua` — Google News URL decoder

**What it does:** (direct port of `php/googlenews.php`)
- `getBase64Str($url)` — extract base64 string from Google News article URL path
- `getDecodingParams($base64Str)` — fetch the page, extract `data-n-a-sg` and `data-n-a-ts` attributes
- `decodeUrl($sig, $ts, $base64Str)` — POST to Google's `batchexecute` endpoint with signature + timestamp
- `decodeGoogleNewsUrl($url)` — orchestrates all three steps

**Implementation:**
- Use `resty.http` for all HTTP calls
- Regex matching for HTML attribute extraction (same as PHP `preg_match`)
- JSON decode via `cjson`
- Same request headers, same payload format, same response parsing

### 7. `lua/rss/fetcher.lua` — RSS feed fetching & parsing

**What it does:**
- Fetches Google News RSS/Atom feeds from various URLs
- Parses the XML to extract: title, items (each with title, link, description, date, images)

**Approach options:**

**Option A — Use Google's JSON endpoint instead of RSS:**
Google News also offers a JSON feed format. This would simplify parsing massively since we'd use `cjson` directly. The URL pattern is slightly different but covers the same data.

**Option B — Parse XML with lua-xml-parser:**
Use an existing Lua XML library to parse the standard Google News RSS feeds (same URLs as PHP app).

**Option C — Hybrid:**
Try JSON first, fall back to XML parsing.

**Recommendation: Option A** if the JSON endpoint is stable, otherwise Option B.

### 8. `lua/readability/extract.lua` — Heuristic article content extractor

**What it does:**
- Takes raw HTML of an article page
- Extracts the main article content using heuristics (no full Readability port)
- Returns: title, content (HTML), images list

**Why not a full Readability port?**
Readability's DOM manipulation and scoring algorithm is complex (~2000+ lines in PHP). For Google News articles from major publishers, we can do much better with simple heuristics.

**Approach — two-tier extraction:**

**Tier 1: Named container detection (most reliable)**
- Search for common article content containers using string matching / regex:
  - `<article class="...">` — HTML5 semantic tag
  - Elements with classes like `article-body`, `entry-content`, `post-body`, `story-body`, `content-body`, `article__body`, `.content`, `.article-content`
  - Elements with IDs like `article_body`, `storytext`, `post_content`
- First match wins — most publishers use one of these patterns consistently

**Tier 2: Highest text-density heuristic (fallback)**
- If no named container found, scan all block-level elements (`<div>`, `<section>`, `<p>`, `<main>`)
- For each candidate element, score it by:
  - Word count (more words = more likely to be article)
  - Paragraph count (articles have multiple paragraphs)
  - Link density — exclude elements where links > 30% of text (nav/sidebar)
  - Headings — prefer elements containing `<h1>` or `<h2>`
- Return the element with highest composite score

**Implementation:**
- Use **lua-html5lib** for proper HTML5 parsing → DOM tree
- Walk the DOM to find candidate containers (string match on class/id/tagName)
- If no named container found, use the density heuristic
- Strip all tags except whitelisted ones from the extracted content
- Extract images list

This is vastly simpler than Readability and works well enough for news articles. For edge cases where it fails, the raw page text still renders (with extra markup) — acceptable tradeoff.

### 9. `lua/utils/string.lua` — String helpers

Direct port of PHP functions:
- `clean_str(str)` — replace curly quotes, dashes, `&nbsp;` with ASCII equivalents

### 10. `lua/utils/html.lua` — HTML helpers

- `strip_tags(html, allowed)` — strip all HTML tags except those in the whitelist
- Tag whitelist from original PHP: `<a><ol><ul><li><br><p><small><font><b><strong><i><em><blockquote><h1>...<h6>`

---

## Caching Layer (Critical)

Since every request currently triggers live HTTP calls, caching is essential for performance.

### Memory-based cache (`ngx.shared.DICT`)
- **RSS feeds:** TTL of 5 minutes (300 seconds). News doesn't change that fast, and this prevents hammering Google News on each visitor.
- **Decoded article URLs:** TTL of 1 hour. The decoded URL rarely changes.
- **Article content:** TTL of 30 minutes. Articles are static once published.

### File-based cache (optional fallback)
- Store cached responses in `/cache/` directory
- Useful if memory cache fills up or as a persistence layer
- Not needed for initial version

### Cache keys
```lua
-- RSS feed: based on loc + lang + section
"feed:" .. loc .. ":" .. lang .. ":" .. (section or "all")

-- Article URL decode: based on the base64 string
"decoded:" .. base64_str

-- Article content: based on the real article URL hash
"article:" .. ngx.md5(real_url)
```

---

## nginx.conf Configuration Notes

Key directives needed in nginx config (all standard lua-nginx-module directives):

```nginx
# Shared memory zones for caching
http {
    lua_shared_dict news_cache 10m;     # RSS feeds + decoded URLs
    lua_shared_dict article_cache 20m;  # Article content
    lua_shared_dict image_cache 5m;     # Image data
    
    # Lua package paths
    lua_package_path '/path/to/lua/?.lua;;';
    
    init_by_lua_block {
        -- Pre-load modules at startup
    }
}

server {
    location / {
        content_by_lua_file /path/to/lua/handlers/index.lua;
    }
    
    location /article {
        content_by_lua_file /path/to/lua/handlers/article.lua;
    }
    
    # ... other routes
}
```

**Note:** All directives (`lua_shared_dict`, `lua_package_path`, `content_by_lua_file`, etc.) are standard [lua-nginx-module](https://github.com/openresty/lua-nginx-module) features — available in plain nginx, not just OpenResty.

---

## Dependencies & Libraries

| Library | Purpose |
|---------|---------|
| **nginx + lua-nginx-module** | Core runtime (compile nginx with `--with-http_lua_module` or use `nginx-extras` package) |
| `lua-resty-http` | HTTP client for fetching feeds, articles, images (standalone library from OpenResty ecosystem) |
| `cjson` | JSON encoding/decoding (built into LuaJIT) |
| **lua-html5lib** | HTML5 parsing → DOM tree for article extraction and tag stripping |
| `lua-xml-parser` or manual XML parsing | RSS feed parsing (optional — may not need if using JSON endpoint) |
| `lua-resty-core` | Core nginx Lua API (`ngx.shared.DICT`, etc.) |

All libraries are standalone — no OpenResty distribution needed. Install the lua module into nginx, then drop the `.lua` files into the package path.

---

## File Size Considerations for 68k Audience

The original PHP app outputs HTML designed for vintage computers (Netscape 1.1-4, Mac SE/30). The Lua version should maintain this:
- Same minimal HTML structure (`<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 2.0//EN">`)
- Same font tags, `<small>`, `<center>` etc.
- No JavaScript, no CSS files, no modern markup
- Output size stays roughly the same or smaller (no PHP overhead)

---

## Migration Steps (Recommended Order)

1. **`nginx.conf`** — main config file for the user to drop into their existing nginx+lua setup
2. **`choose_edition.lua`** — easiest: static HTML, no dependencies
3. **`utils/string.lua` + `utils/html.lua`** — shared helpers needed by everything
4. **`googlenews/decoder.lua`** — self-contained, no external parsing needed
5. **`rss/fetcher.lua`** — RSS fetching + parsing (the big one)
6. **`index.lua`** — tie together fetcher + templates + navigation
7. **`readability/extract.lua`** — heuristic content extractor with lua-html5lib
8. **`article.lua`** — tie together decoder + extract + templates
9. **`image.lua`** — image proxy handler
10. **Caching layer** — add `ngx.shared.DICT` caching to each handler
11. **User deploys** — copy everything to web server, reload nginx, test live

---

## Risks & Unknowns

- **Google News API stability:** The `batchexecute` endpoint could change without notice (it already has). Same risk in both PHP and Lua versions.
- **Content extraction accuracy:** Heuristic approach may miss some article containers on unusual publisher pages. Test against a variety of article sources. Fallback (highest-density element) should still produce readable output even if it includes extra markup.
- **lua-html5lib availability:** Need to verify the library works well with lua-nginx-module (not just OpenResty). May need to build from source or fork.
- **Concurrent requests:** nginx's event model handles this well, but each concurrent request to Google News means more simultaneous HTTP connections. Rate limiting may be needed.

---

## What Stays the Same

- All URLs and query parameters (backward compatible)
- HTML output format (retro-compatible with Netscape/Mac SE/30)
- Navigation structure (WORLD, NATION, BUSINESS, etc.)
- Country edition selection
- Article image linking pattern
- `noindex, nofollow` header behavior

## What's Different / Improved

- **Caching** — RSS feeds cached server-side instead of fetched every request
- **Performance** — LuaJIT is significantly faster than PHP for this workload
- **Memory footprint** — nginx + Lua uses far less memory than PHP-FPM
- **No OpenResty required** — works with plain nginx compiled with lua-nginx-module
- **No PHP/Composer** — no autoloaders, no vendor directory, just nginx config + Lua files
- **Config file** — entire app in one `nginx.conf` + a directory of Lua files
