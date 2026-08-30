# Inkflow — Product & Build Plan

**Positioning:** The reading app where books come alive. Bring any book, article, PDF or EPUB; every chapter opens with a generated cinematic cold open, then reads itself to you with a full cast of voices and synced highlighting. AI margin notes, reading goals, daily/weekly recap mail, Notion export.

**Competitors:** Speechify (₹2,499 lifetime "100K books", TTS-first, ADHD tools), ElevenReader (best voices, free 10h/mo), Kindle (DRM library, Assistive Reader), Audible. None of them do generated visuals per chapter, none do multi-voice on *your own* imports, none do AI margin notes in markdown. That is the wedge.

**Monetisation:** Freemium. Free: 1 book with cold opens + 30 min/mo of listening. Pro: ₹499/mo or ₹2,999/yr (7-day trial): unlimited listening, cold opens on every chapter, ask-the-book, recap mail, Notion export.

---

## 1. Architecture

```
iOS app (SwiftUI, iOS 26)
   │  HTTPS (Supabase JWT)
   ▼
api.inkflow.app  — Next.js 16 route handlers on Vercel
   ├── Supabase Postgres (data) + Supabase Auth (Apple / Google / email OTP) + Storage (imports, generated media)
   ├── Vercel Queues / cron (chapter generation jobs, daily & weekly mail)
   ├── fal.ai        — FLUX schnell (key frame, covers) · MiniMax H3 Max (cold open video)
   ├── ElevenLabs    — TTS with timestamps (multi-voice, sentence alignment)
   ├── OpenAI        — scene direction, speaker tagging, margin notes, recaps
   ├── Open Library / Internet Archive — search + public-domain full text
   ├── RevenueCat    — StoreKit 2 subscriptions, entitlements, webhooks
   ├── Resend        — transactional + recap email
   ├── Notion API    — OAuth connector, export notes/highlights
   └── PostHog + Sentry — analytics, crashes
```

Why the API exists (not client-only): generation must run server-side so keys never ship in the binary, jobs survive the app being backgrounded, media is cached once per book for all users (a public-domain chapter's cold open is generated once, ever), entitlements are enforced server-side, and email/Notion need a server.

### 1.1 Data model (Supabase Postgres)

```sql
-- identity
profiles(id uuid pk = auth.users.id, name, email, timezone, daily_goal_min int default 20,
         mail_daily bool default true, mail_weekly bool default true, created_at)

-- catalogue (a "work" is shared across users; user-private imports have owner_id set)
books(id uuid pk, owner_id uuid null, source text check in ('archive','gutenberg','url','upload','paste'),
      source_ref text, title, author, language, cover_url, style_lock text,
      word_count int, chapter_count int, public bool, created_at)
chapters(id uuid pk, book_id fk, idx int, part text, number text, title text,
         word_count int, storage_path text /* paragraphs json */, unique(book_id, idx))
chapter_media(chapter_id pk fk, scene_prompt, narration_line, keyframe_url, video_url,
              narration_audio_url, status text check in ('queued','generating','ready','failed'),
              cost_cents int, generated_at)
paragraph_audio(id pk, chapter_id fk, paragraph_idx int, speaker text, voice_id text,
                audio_url, sentences jsonb /* [{text,start,end}] */, unique(chapter_id, paragraph_idx))

-- per-user
library(user_id fk, book_id fk, added_at, last_opened_at, pk(user_id, book_id))
progress(user_id, book_id, chapter_idx int, paragraph_idx int, percent numeric, updated_at, pk(user_id, book_id))
highlights(id pk, user_id, book_id, chapter_idx, paragraph_idx, text, color, created_at)
notes(id pk, user_id, book_id, chapter_idx, paragraph_idx, excerpt, markdown, created_at)
sessions(id pk, user_id, book_id, chapter_idx, started_at, ended_at, minutes int, mode text /* read|listen|both */)
goals(user_id pk, daily_minutes int, weekly_books int, streak int, best_streak int, last_hit_date date)

-- billing & integrations
entitlements(user_id pk, tier text check in ('free','pro'), source text, expires_at, rc_app_user_id)
usage(user_id, month date, listen_seconds int, coldopens int, notes int, pk(user_id, month))
connectors(user_id, provider text /* notion */, access_token_enc, workspace_id, target_page_id, pk(user_id, provider))
email_log(id, user_id, kind text /* daily|weekly */, sent_at, opened bool)
generation_jobs(id pk, chapter_id fk, kind text /* coldopen|narration */, status, attempts int, error, created_at)
```

RLS: every per-user table is `user_id = auth.uid()`. `books` readable when `public or owner_id = auth.uid()`. Media tables readable via book visibility.

### 1.2 API (Next.js route handlers, `/api/v1/...`)

| Route | Purpose |
|---|---|
| `POST /auth/apple` (via Supabase) | Sign in with Apple / Google / email OTP |
| `GET /me` · `PATCH /me` | Profile, goals, mail prefs |
| `GET /search?q=` | Open Library search, normalised results |
| `POST /books/import` | `{source, ref | url | text | upload_id}` → parses, splits chapters, stores; returns book |
| `POST /uploads` | Signed URL for PDF/EPUB upload to Supabase Storage |
| `GET /books/:id` · `GET /books/:id/chapters/:idx` | Metadata + paragraphs |
| `POST /chapters/:id/generate` | Enqueue cold open + first N paragraphs narration (idempotent) |
| `GET /chapters/:id/media` | Media status + signed URLs; client polls or receives push |
| `POST /chapters/:id/narrate?from=&count=` | Extend narration ahead of the listener |
| `PUT /progress` · `POST /sessions` | Reading progress & time tracking |
| `POST /highlights` · `POST /notes` · `POST /notes/ask` | Highlights; ask-the-book returns markdown |
| `GET /library` · `POST /library` · `DELETE /library/:book` | User shelf |
| `GET /discover` | Curated classics shelf with generated covers |
| `POST /connectors/notion/oauth` · `POST /export/notion` | Notion connect + export |
| `POST /webhooks/revenuecat` | Entitlement sync |
| `POST /cron/daily-mail` · `POST /cron/weekly-mail` (Vercel cron) | Recap emails |

Generation worker: `generation_jobs` consumed by a Vercel background function (or Queue). Pipeline per chapter: scene direction (LLM) → key frame (FLUX) → video (H3 Max, 10s 480p, ≈$0.25 promo / $0.50 list) → narration line (ElevenLabs) → speaker tagging (LLM) → per-paragraph TTS with timestamps. Everything stored in Supabase Storage, public-domain chapters shared across users.

### 1.3 iOS app (SwiftUI, iOS 26, Liquid Glass)

Screens, in user-flow order:

1. **Splash / launch** — logo, prefetch `/discover`.
2. **Onboarding (5 screens)** — hero "Books that come alive"; how it works; what do you read (genres → seeds discover); daily goal picker (10/20/30/45 min); notification permission (with soft prompt first).
3. **Paywall** — trial-first ("Try Pro free for 7 days"), yearly preselected, monthly secondary, "Continue with limits" link. RevenueCat Paywalls v2 or native StoreKit view. Shown after onboarding and again when a free limit is hit.
4. **Sign in** — Apple (primary), Google, email OTP. Anonymous Supabase session before this so onboarding data isn't lost.
5. **Home** — Continue reading card (key frame art), goal ring + streak, Discover shelf (classics with generated covers), Library grid, glass bottom bar: Home · Library · Notes · Profile; floating search + import.
6. **Search** — Open Library results, cover, year, "Add" → import.
7. **Import sheet** — paste link, paste text, upload PDF/EPUB/DOCX (Files), Share Extension from Safari.
8. **Book detail** — cover, blurb, chapters list with media status dots, "Start" / "Resume", download for offline.
9. **Cold open** — full-bleed video + narrator line + chapter title; skippable; auto-dissolves to reader.
10. **Reader** — serif typography, theme (paper/sepia/night), font size, line spacing, margins; sentence highlighting synced to audio; tap to hide chrome; double-tap paragraph to play from there; long-press → highlight colours + Ask the book; page/scroll modes.
11. **Player** — glass bar in reader; expanded Audible-style player (art, scrub, speed 0.8–2×, sleep timer, chapter list, voice cast); lock-screen / CarPlay controls via MPNowPlayingInfoCenter; background audio.
12. **Ask the book / Notes** — sheet with suggested prompts, markdown answer, save; Notes tab lists notes by book, search, export to Notion.
13. **Goals & Stats** — daily ring, streak calendar, minutes by week, books finished.
14. **Profile / Settings** — account, subscription (manage / restore), mail preferences, Notion connector, voice preferences, delete account (App Store requirement).
15. **Email** — Daily "Yesterday you read 18 min of *A Study in Scarlet* — 2 more to hit your goal" with the day's best highlight; Weekly digest with minutes, streak, and LLM-summarised key points from highlights/notes.

App Store readiness: privacy manifest, sign-in-with-Apple (required when offering Google), account deletion, subscription terms text, restore purchases, offline behaviour, no third-party payment, review-safe demo account.

---

## 2. Build phases

### Phase 0 — Hackathon (today, until 4:30 PM demo)

Goal: win with one unforgettable demo, on a real architecture we keep.

**Build now**
- iOS: onboarding (3 screens), home (continue card, goal ring, library, discover shelf), search, import (link / text / PDF / EPUB), cold open, reader with synced highlighting, multi-voice player, ask-the-book note sheet, chapter list. *(Scaffold exists and compiles.)*
- Backend (Vercel, `api/` in this repo): Next.js route handlers for `search`, `books/import`, `chapters/:id/generate`, `chapters/:id/media`, `chapters/:id/narrate`, `notes/ask`. Supabase project with the `books`, `chapters`, `chapter_media`, `paragraph_audio` tables and Storage bucket. Keys live only on Vercel. The iOS app calls the API instead of providers directly.
- Precache: *A Study in Scarlet* all 14 chapters (cold open + narration + first 12 paragraphs each) generated through the same API and stored in Supabase Storage, plus bundled in the app as an offline fallback for the stage.
- Live generation demo path: paste an article link on stage → cold open generates in ~15 s → plays.
- Basic anonymous Supabase session so progress/notes persist.

**Fake / static today**
- Paywall screen exists and is designed, but "Start trial" just dismisses (no StoreKit yet).
- Goal ring shows real session minutes but streak is computed client-side only.
- Discover shelf is a hardcoded list of 8 classics with covers generated once via FLUX.

**Not today**
- Real auth providers, RevenueCat, email, Notion, share extension, offline downloads, stats screens, account deletion, DOCX.

**Timeline**
- 11:30–12:30 Supabase project + schema + Vercel API skeleton; iOS switches to API client.
- 12:30–13:30 Precache job running; reader/player polish; paywall + discover UI.
- 13:30–15:00 Live import path end-to-end; ask-the-book; onboarding polish.
- 15:00–16:00 Rehearse demo ×5, record backup video, bundle fallback assets.
- 16:00–16:30 Freeze. Pitch deck: 5 slides (problem, demo, how it works, business, roadmap).

### Phase 1 — TestFlight beta (this week)
- Supabase Auth: Apple, Google, email OTP; anonymous → linked account.
- RevenueCat + StoreKit 2: products, trial, entitlements webhook, server-side gating of cold opens / listening minutes.
- Full onboarding (5 screens) and paywall variants.
- Progress, sessions, highlights, notes synced; goals + streaks server-side.
- Generation worker as a queued job with retries and cost logging; shared media for public-domain works.
- Expanded player: lock-screen controls, sleep timer, speed, background audio, offline chapter download.
- PostHog events, Sentry.
- Resend: daily and weekly recap mail via Vercel cron.

### Phase 2 — App Store launch (weeks 2–3)
- Notion connector (OAuth, export notes + highlights as a page per book).
- Share Extension (send any URL from Safari), DOCX import, better EPUB parsing (TOC-based chapters).
- Reader settings (themes, fonts, page mode), highlight colours, notes search.
- Stats screen, streak calendar.
- Account deletion, privacy manifest, App Store screenshots and preview video (the cold open sells itself), review notes with demo account.
- Landing page on Vercel (`inkflow.app`) with waitlist → App Store link.

### Phase 3 — Growth (post-launch)
- Voice cloning for narrator (ElevenLabs IVC) — "read to me in my own voice".
- Character voice casting UI; regenerate a cold open with your own prompt.
- Social: shareable cold-open clips with watermark (TikTok loop), reading clubs.
- Android (Expo) once iOS retention is proven.
- Kindle import (Speechify's moat) via Amazon "Download & transfer" EPUB where legally permitted.

---

## 3. Unit economics (per Pro user, month)

| Item | Assumption | Cost |
|---|---|---|
| Cold opens | 30 chapters × $0.50 (list price 480p) | $15 worst case — but public-domain chapters are generated once and shared; effective ≈ $2–4 |
| Listening | 6 h × ElevenLabs Flash ≈ $0.10/1k chars ≈ 60k chars/h | ≈ $3.6 |
| LLM | notes + tagging + recaps | < $0.3 |
| Total | | ≈ $6–8 vs ₹499 (≈ $6) monthly / ₹2,999 yearly |

Levers: 480p on mobile is fine; 5-second cold opens for non-first chapters; cache everything public-domain; cap free tier hard. Pricing should land at ₹699/mo or push annual.

---

## 4. Risks

- **Slop perception** — style lock per book + image-to-video from a consistent key frame + 10-second intros only. Never inline mid-chapter.
- **fal H3 Max promotional pricing was active as of 30 August** — budget on list price.
- **ElevenLabs with-timestamps char limit** — per-paragraph requests, already how the pipeline works.
- **Internet Archive OCR quality** — prefer Gutenberg text when available; OCR cleanup pass via LLM for Archive texts.
- **App Store review** — must have sign-in-with-Apple, restore purchases, account deletion, and not gate all content behind paywall with no free path.
- **Copyright** — user uploads are private to the user; only public-domain works are shared/generated once.
