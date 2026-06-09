# Research Hub — Full System Reference

> **Purpose**: A self-hosted market intelligence portal that unifies three financial research tools behind a single localhost dashboard.
> **Architect**: MelawiGide (retail trader, macOS ARM, DeepSeek API user)
> **Stack**: Python 3.14 + Next.js 14 + Qt6 desktop + Apify scraping
> **Last updated**: 2026-06-09 (Changelog: see §12)

---

## 12. Changelog — 2026-06-09

### Phase 6 — Hub Proxy Fix (CRITICAL)
**`hub_server.py`** — Added `do_POST` handler + CA API POST/GET passthrough:
- `proxy_post()` function added to forward POST requests with 60s timeout
- `do_POST()` routes to CA API endpoints: `/api/research`, `/api/advisor`, `/api/insider`
- `do_GET()` now catches `/api/*` (non-hub-status) and proxies to `:3000`
- **Root cause**: CA loaded through `:9000/ca/` iframe could GET the page, but any POST to `/api/research` or `/api/advisor` hit the hub server which had no POST handler. Settings appeared to "not save" because the key was saved (localStorage) but API calls silently failed through the proxy.

### Phase 2 — Settings Save Feedback
**`chokepoint-atlas/components/SettingsPanel.tsx`** — Added "Saved!" confirmation:
- Save button shows a green "Saved!" checkmark for 800ms before closing
- Gives explicit visual feedback that settings persisted

### Phase 3 — Sector Rotation Cron Fix
**Hermes cron `d07f46d8d031`** — Two changes:
- Removed `browser` toolset (was `["web", "browser", "terminal"]` → `["web", "terminal"]`). Cron context has no headless browser — `web` tool does the same research via curl/API.
- Pinned model to `deepseek-v4-flash`/`deepseek` provider (was unset — inherited default, which could change)
- Next verification: scheduled 15:30 ET today

### Phase 5 — Insider-Tracker Enhancement
**`chokepoint-atlas/app/api/insider/route.ts`** — Rewrote with:
- **POST endpoint** (`/api/insider`) for async refresh with request body
- **Lockfile** (`.insider-scan.lock`) prevents concurrent runs, returns cached data if busy
- **Timeout** increased from 45s → 150s (SEC EDGAR scraping is slow)
- **`maxBuffer`** increased from 1MB → 10MB

**`chokepoint-atlas/components/InsiderPanel.tsx`** — Added:
- **AI mode toggle** — blue "AI" button next to "Scan Now" that sends DeepSeek key from settings for narrative analysis (POST with `deepseekKey`)
- On/off visual state for the AI button
- Locked-state handling (shows "Scan already running" instead of silent fail)
- Loads settings from localStorage (same pattern as RoboAdvisor)

### Services Running (as of now)
| Service | Port | Status |
|---------|------|--------|
| Hub Portal | :9000 | ✅ Running |
| TrendRadar | :8080 | ✅ Running |
| Chokepoint Atlas | :3000 | ✅ Running |
| Sector Rotation | cron | 🔄 Pending (next 15:30 ET) |
| Stock Basket | cron | ✅ Working (last run today) |
| Twitter Intel | cron | ⛔ Skipped per user request |

---

## 1. Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│                   Research Hub Portal                    │
│              http://localhost:9000                       │
│              Python http.server / proxy                  │
│              hub_server.py  (465 lines)                  │
├─────────────────────────────────────────────────────────┤
│                                                          │
│  /ca/*   ──proxy──►  Chokepoint Atlas  (:3000)          │
│                        Next.js / TypeScript              │
│                        ~/Downloads/chokepoint-atlas/      │
│                                                          │
│  /tr/*   ──proxy──►  TrendRadar          (:8080)        │
│                        Python 3.14 / uv / venv           │
│                        ~/TrendRadar/                     │
│                                                          │
│  /tr-api/* ──proxy──►  TrendRadar API   (:8080/api/)    │
│                                                          │
│  /twitter/ ──local──►  Twitter Intel Feed               │
│                        output/twitter/twitter_feed.html   │
│                                                          │
│  /api/hub-status ──►   Service health check             │
│                                                          │
│  FinceptTerminal tab ─► Desktop app (no embed)          │
│                        /Applications/FinceptTerminal.app │
│                                                          │
└─────────────────────────────────────────────────────────┘
```

### Port Map

| Port | Service | Type | Status |
|------|---------|------|--------|
| 9000 | Research Hub Portal | Python http.server | Hub — always start first |
| 8080 | TrendRadar Dashboard | Python http.server | Embedded via proxy |
| 3000 | Chokepoint Atlas | Next.js dev server | Embedded via proxy |
| 3333 | TrendRadar MCP | Python MCP server | AI tool integration |
| N/A  | FinceptTerminal | macOS .app bundle | Desktop app, no web |

---

## 2. Service 1: TrendRadar (`~/TrendRadar/`)

### What It Is
Fork of [sansan0/TrendRadar](https://github.com/sansan0/TrendRadar) v6.9.0 — multi-platform news aggregation, RSS feeds, and AI analysis. Repurposed for English financial news (all Chinese platforms deactivated).

### GitHub
- Remote: `git@github.com:MelawiGide/TrendRadar.git`
- Forked from `sansan0/TrendRadar`
- Commits: custom patches for English UI, frequency_words.txt, and hub integration

### Key Files

| File | Purpose |
|------|---------|
| `server.py` (220 lines) | HTTP server on :8080 — dashboard, status API, report viewer, `/editor` |
| `hub_server.py` (465 lines) | Unified portal on :9000 — proxy routing, tab UI, Twitter intel |
| `start-hub.sh` (47 lines) | Launch all services: Chokepoint Atlas + TrendRadar + MCP + Hub |
| `twitter_intel.py` (345 lines) | Apify-based Twitter scraper for 497 followed accounts |
| `twitter_following.txt` (496 lines) | List of @handles to monitor |
| `output/twitter/twitter_feed.html` | Rendered Twitter feed HTML |
| `output/twitter/twitter_feed.json` | Raw Twitter feed data |
| `output/news/*.db` | SQLite databases with scraped news data (per-date) |

### Configuration
- Config editor: `http://localhost:8080/editor`
- Frequency words: stored in `frequency_words.txt`, one keyword per line
- English-only mode: all Chinese platform sources deactivated
- Dependencies managed with `uv` — venv at `.venv/` (Python 3.14)
- Run analysis: Click "Run Analysis" button on dashboard

### API Endpoints (TrendRadar :8080)
- `GET /api/status` — DB stats, last report info, project version
- `GET /api/latest-report` — Full latest HTML report
- `GET /api/latest-raw-report` — Body-only HTML (for embedding)
- `GET /api/run-analysis` — Trigger analysis in background thread

### Known Issues
- Reports may render incorrectly in proxy iframe (relative paths break)
- "Run Analysis" can timeout if large dataset — 120s timeout in code
- MCP server on :3333 sometimes dies silently

---

## 3. Service 2: Chokepoint Atlas (`~/Downloads/chokepoint-atlas/`)

### What It Is
Supply chain bottleneck research dashboard built with Next.js 14 + TypeScript + Tailwind CSS. Supply chain thesis research tool.

### GitHub
- NO remote configured. Local-only.
- Not on GitHub yet.

### Tech Stack
- Next.js 14.2.5
- React 18 + TypeScript 5
- Tailwind CSS 3 + PostCSS
- D3.js for visualizations
- Lucide React icons
- OpenAI SDK (unused — prefers DeepSeek API)

### Key Files

| File | Purpose |
|------|---------|
| `app/page.tsx` (209 lines) | Main page with tabbed views |
| `app/layout.tsx` (20 lines) | Root layout with ResearchProvider |
| `components/TopBar.tsx` | Navigation bar with ticker search |
| `components/RoboAdvisor.tsx` | AI-powered investment analysis |
| `components/ResearchView.tsx` | SEC filings, research interface |
| `components/SignalsView.tsx` | Trading signals display |
| `components/EcosystemView.tsx` | Supply chain ecosystem graph (D3.js) |
| `components/CycleView.tsx` | Market cycle analysis |
| `components/InsiderPanel.tsx` | Insider trades display |
| `components/SettingsPanel.tsx` | API key + model settings |
| `components/ResearchInterface.tsx` | Main research query UI |
| `components/EcosystemPanel.tsx` | Sub-component of EcosystemView |
| `components/OutputPanel.tsx` | Research output display |
| `components/StepTracker.tsx` | Multi-step process tracker |
| `insider-tracker.py` (543 lines) | Standalone Python script: SEC EDGAR + congressional trades + yfinance + DeepSeek analysis |
| `insider-trades.json` | Cached output from insider-tracker.py |

### Launch
```bash
cd ~/Downloads/chokepoint-atlas
npx next dev --port 3000
```

### Known Issues
- **Settings / API key input buggy** — DeepSeek key entry often fails to save or validate
- **No git repo** — can't version or share changes
- **Next.js hot reload** sometimes breaks the proxy routing through hub
- **Yahoo Finance `yfinance`** calls blocked by Next.js SSR (needs client-side or proxy)
- **insider-tracker.py** runs independently, not integrated into the UI

---

## 4. Service 3: FinceptTerminal (`/Applications/FinceptTerminal.app`)

### What It Is
Native C++20/Qt6 financial desktop application with institutional-grade analytics.

### Details
- Notarized by Apple, dev ID: Tilak Patel 5Z2M47CJ3M
- Version: 4.0.3
- Features: DCF, portfolio optimization, VaR, Sharpe, derivatives pricing
- 37 AI agents (Buffett, Graham, Lynch — multi-provider: OpenAI, DeepSeek, Ollama)
- 100+ data connectors (Yahoo Finance, Polygon, FRED, IMF, Kraken, World Bank)
- 16 broker integrations, algo trading, paper engine
- Maritime tracking, geopolitical analysis
- QuantLab + node editor with 18 quant modules
- GitHub: `https://github.com/MelawiGide/FinceptTerminal`

### Launch
```bash
open /Applications/FinceptTerminal.app
```

### Note
This is a desktop app — cannot be embedded via iframe. The hub tab shows feature info and a launch button.

---

## 5. Service 4: Twitter Intel Feed

### What It Is
Scrapes tweets from 497 accounts followed by `@goatthatshiton` via Apify's Tweet Scraper V2.

### Infrastructure
- **CLI**: Apify CLI v1.6.2 (user: `sculptured_lozenge`)
- **Actor**: `apidojo/tweet-scraper`
- **Accounts**: `~/TrendRadar/twitter_following.txt` — 496 lines of @handles
- **Cron**: Hermes cron job `b10a7e0d` runs every 4 hours
- **Output**: `~/TrendRadar/output/twitter/twitter_feed.html` + `twitter_feed.json`

### Script
```bash
cd ~/TrendRadar && python3 twitter_intel.py
```

### Configuration
- `MAX_TWEETS = 1000` per run
- `TWEETS_PER_ACCOUNT = 3` max per account per batch
- Batches of 20 accounts at a time
- 2-second delay between batches for rate limiting
- Language filter: English only

### Known Issues
- **Cron job failing** — last_status: "error" (needs debug)
- **Apify credits** may be exhausted for anonymous tier
- **Tweet counts are 0** in latest feed (`"total_tweets": 0`)

---

## 6. Cron Jobs (Hermes Agent)

| Job ID | Name | Schedule | Delivery | Status |
|--------|------|----------|----------|--------|
| `d07f46d8d031` | Sector Rotation Watch | Mo-Fr 10:30, 15:30 ET | Telegram | Last: error |
| `547f79d945ec` | Stock Basket Valuation | Daily 08:30 ET | Telegram | Last: ok |
| `b10a7e0d7e9f` | Twitter Intel Feed | Every 4h | Local only | Last: error |

---

## 7. User Profile & Constraints

### Environment
- macOS Sequoia 26.3.1 on Apple Silicon (ARM64)
- User home: `/Users/melawigide`
- Shell: zsh
- Python: 3.14 via uv (`.local/share/uv/python/cpython-3.14-macos-aarch64-none`)
- Package managers: uv (Python), npm (Node), Homebrew (system)
- Editor: VS Code / Hermes TUI
- DeepSeek API key configured (provider: deepseek)

### Constraints & Preferences
1. **NO paid data APIs** — only free sources (yfinance, SEC EDGAR, RSS, Apify free tier)
2. **English-only** — all Chinese platforms in TrendRadar deactivated
3. **One-keyword-per-line** format for frequency words
4. **Local-only** — no deployment, no cloud, no Docker
5. **Functional over info** — if a tab just describes without running something useful, it's not enough
6. **Unified single-port experience** — prefers :9000 as single access point, not multi-port navigation
7. **FinceptTerminal stays as separate desktop app** — don't try to web-embed it
8. **Dead processes between sessions** — all servers die when user closes terminal; needs restart reminder

### Communication Style
- Concise, direct, actionable
- Prefers scored/ranked outputs with trade structure suggestions (strike, expiry, direction)
- Likes explicit narration + permission before side-effectful actions
- Responds well to thorough, well-structured builds

---

## 8. System Map — Directory Structure

```
/Users/melawigide/
├── TrendRadar/                          # Main project (hub + news + twitter)
│   ├── hub_server.py                    # Unified portal :9000
│   ├── server.py                        # TrendRadar dashboard :8080
│   ├── start-hub.sh                     # Launch all services
│   ├── twitter_intel.py                 # Twitter scraper
│   ├── twitter_following.txt            # 497 followed accounts
│   ├── .venv/                           # Python 3.14 venv (uv)
│   ├── trendradar/                      # Core TrendRadar module
│   ├── output/
│   │   ├── twitter/
│   │   │   ├── twitter_feed.html
│   │   │   └── twitter_feed.json
│   │   └── news/                        # SQLite databases per-date
│   ├── docs/
│   │   ├── index.html                   # Config editor
│   │   └── assets/
│   ├── RESEARCH_HUB_REFERENCE.md        # ← THIS FILE
│   └── README*.md                       # Original upstream docs
│
├── Downloads/
│   └── chokepoint-atlas/                # Next.js supply chain research
│       ├── app/
│       │   ├── page.tsx
│       │   └── layout.tsx
│       ├── components/                  # 14 React components
│       ├── lib/                         # Types, contexts, research engine
│       ├── public/
│       ├── insider-tracker.py           # Standalone SEC/yfinance scraper
│       ├── insider-trades.json          # Cached output
│       ├── package.json
│       ├── next.config.mjs
│       └── tailwind.config.ts
│
├── .hermes/
│   ├── config.yaml                      # Hermes agent config
│   ├── skills/                          # Custom skills
│   ├── stock-basket.txt                 # Watchlist for cron jobs
│   └── profiles/
│       └── default/                     # Active profile
│
└── Applications/
    └── FinceptTerminal.app              # Qt6 desktop app
```

---

## 9. Launch Procedure

### Full Startup
```bash
cd ~/TrendRadar && ./start-hub.sh
```
This starts: Chokepoint Atlas (:3000) → TrendRadar (:8080) → MCP (:3333) → Hub (:9000)

### Manual / Debug
```bash
# 1. Start Hub (port 9000)
cd ~/TrendRadar && source .venv/bin/activate && python hub_server.py

# 2. Start TrendRadar (port 8080) in separate terminal
cd ~/TrendRadar && source .venv/bin/activate && python server.py

# 3. Start Chokepoint Atlas (port 3000) in separate terminal
cd ~/Downloads/chokepoint-atlas && npx next dev --port 3000

# 4. Run Twitter scraper
cd ~/TrendRadar && source .venv/bin/activate && python twitter_intel.py

# 5. Run Insider Tracker
cd ~/Downloads/chokepoint-atlas && python3 insider-tracker.py
```

### Startup Issues
- Chokepoint Atlas can take 30-60s to compile on first launch
- `start-hub.sh` starts processes in background — no output visible after `sleep 3`
- Kill all: `pkill -f "hub_server.py" ; pkill -f "server.py" ; pkill -f "next dev"`

---

## 10. Roadmap / Pain Points (for Claude to Orchestrate)

### Critical Fixes Needed
1. **Twitter cron keeps failing** — debug Apify auth/credits, check error logs
2. **Chokepoint Atlas settings bug** — DeepSeek API key input not saving/persisting
3. **Twitter feed showing 0 tweets** — scraper runs but produces empty results
4. **Sector Rotation Watch cron error** — needs debug on what's failing

### Improvements Desired
5. **Chokepoint Atlas to GitHub** — create remote repo, push local code
6. **Better Chokepoint Atlas UI** — the tab is functional but ugly/buggy
7. **Integrate insider-tracker.py output** into the Chokepoint Atlas UI
8. **Startup reminder cron** — a daily notification to start the hub if it's down

---

## 11. Key Technical Details Summary

| Detail | Value |
|--------|-------|
| macOS version | 26.3.1 |
| Python version | 3.14 (via uv) |
| Node.js | system install |
| npm | system install |
| Apify CLI | v1.6.2 |
| User account | melawigide |
| Hub directory | `/Users/melawigide/TrendRadar/` |
| CA directory | `/Users/melawigide/Downloads/chokepoint-atlas/` |
| FT location | `/Applications/FinceptTerminal.app` |
| DeepSeek model | deepseek-chat / deepseek-v4-flash |
| Hermes model | deepseek-v4-flash via deepseek provider |
| Git remote (TR) | `git@github.com:MelawiGide/TrendRadar.git` |
| Git remote (CA) | None |
| Apify user | `sculptured_lozenge` |
| Twitter target | `@goatthatshiton` following list |
| Accounts monitored | 497 |
| Cron: sectors | d07f46d8d031 (broken) |
| Cron: basket | 547f79d945ec (working) |
| Cron: twitter | b10a7e0d7e9f (broken) |
| Python server base | `http.server.SimpleHTTPRequestHandler` |

---

*End of System Reference. Edit this document to update when the architecture changes.*
