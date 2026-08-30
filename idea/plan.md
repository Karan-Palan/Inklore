# Inkflow - Product and Build Plan

Status: superseded, 2026-08-30. Owner: Karan-Palan.

The active product, hackathon, architecture, and App Store plan is [`../PLAN.md`](../PLAN.md). This file is retained only as planning history and must not be used as an implementation contract.

## 0. Where we start from

This repository is a 10x-generated app (`tenx.yaml`, "Initial commit from 10x"). It already ships:

| Layer | What exists | State |
|---|---|---|
| iOS (`ios/`, SwiftUI, iOS 26, ~11k lines) | Sign-in (Apple / Google / email via 10x managed Better Auth), 7-step onboarding quiz, Library, Search (Gutenberg EPUB + Internet Archive text, Open Library covers), EPUB/PDF/TextKit readers with highlights + notes, on-device `AVSpeechSynthesizer` player with read-along, Stats (streak, goal ring), Notebook, daily-digest settings, cloud backups | Builds and runs on iPhone 17 Pro simulator |
| Backend (`backend/`, FastAPI, Python 3.13) | `/api/v1/daily-digest`, `/api/v1/digest/preferences`, daily cron job, OpenAI study notes, Resend email | Deployed via 10x Paid Backend runtime |
| Data (`services/db/migrations`) | `digest_*` tables and a full `library_books / library_highlights / library_notes / reading_sessions / reading_goals` schema with owner-scoped RLS | Migration 0002 authored, not yet applied to Neon |
| Storage | R2 buckets `photos`, `attachments`, `book_files` | Declared |
| Growth (`growth/app-store`) | Listing, keywords, privacy policy, review notes, 5 screenshots | Drafted |

So the job is not "build a reader"; it is **turn a competent Kindle clone into the product that wins the hackathon and ships to the App Store**: cloud narration with a full cast, generated chapter cold opens, AI margin notes, and sync.

## 1. Product

**One line:** Bring any book. Every chapter opens like a film, then reads itself to you - full cast, word by word - and your notes, streaks and progress follow you everywhere.

**Wedge vs Speechify / ElevenReader / Kindle:** none of them generate visuals per chapter, none do multi-voice on the user's own imports, none produce markdown margin notes and a weekly digest. Speechify's paywall sells a "100K+ books" shelf of AI-generated covers; we can generate ours on demand.

**Business model (Phase 1+, not today):** freemium. Free = 1 book with cold opens, on-device TTS unlimited, 30 min/mo of cloud voices. Pro = INR 699/mo or INR 3,999/yr, 7-day trial: unlimited cloud narration, cold opens on every chapter, ask-the-book, recap mail, Notion export. Unit cost per active Pro user ~USD 6-8/mo at list prices (see 6).

## 2. Full user flow (App Store scope)

1. **Launch** - splash, restore session (`AuthStore.restore()`), prefetch Discover.
2. **Sign in** (exists) - Apple primary, Google, email. Keep, but replace the copyrighted cover art on the hero with generated covers (App Store risk, contradicts `idea/brief.md` compliance rule).
3. **Onboarding** (exists, 7 steps) - trim to 5: welcome -> what brings you here -> read/listen/both -> daily goal -> genre. Drop "pick your narrator" (replaced by cloud voices) and "reminders" (ask at the moment of the first finished session instead). Copy and layout borrow from Speechify (see research doc).
4. **Paywall** - *skipped for now.* Slot after onboarding and at limits; RevenueCat + StoreKit 2 in Phase 1.
5. **Home / Library** (exists) - Continue-reading hero with generated key-frame art, goal ring + streak, "Discover" shelf of classics with generated covers, category pills, recent additions.
6. **Search** (exists) - Gutenberg + Internet Archive, download to library.
7. **Import** (exists) - PDF / EPUB from Files, paste link; add paste-text and Share Extension (Phase 2).
8. **Book detail** (exists as sheet) - add chapter list with media-status dots and "Start / Resume".
9. **Cold open** (new) - full-bleed 10 s generated video + narrator line + chapter title, skippable, dissolves into the reader. Prefetched for the next chapter while reading.
10. **Reader** (exists) - paginated TextKit / EPUB / PDF, themes, fonts, highlights, notes. Add sentence highlighting driven by cloud audio timestamps (today it is word-range from AVSpeech).
11. **Player** (exists) - Audible-style; swap engine from `AVSpeechSynthesizer` to a `NarrationEngine` protocol with two backends: `DeviceNarrator` (existing, offline, free) and `CloudNarrator` (ElevenLabs multi-voice via backend). Lock-screen controls, sleep timer, speed already there.
12. **Ask the book** (new) - long-press passage -> markdown margin note -> saved to Notebook.
13. **Notebook** (exists) - add markdown rendering and "Export to Notion" (Phase 2).
14. **You / Stats** (exists) - goal, streak, read-vs-listen split; daily-digest settings already wired to backend.
15. **Email** - daily recap (exists, needs deploy + Resend domain), weekly digest with LLM key points (new job).
16. **Settings** - account, delete account (exists per milestones), subscription (Phase 1), Notion (Phase 2).

## 3. Architecture (10x conventions)

Decision to confirm: **stay on the 10x-managed stack declared in `tenx.yaml`** (Neon Postgres + Better Auth + R2 + FastAPI on the 10x Paid Backend runtime) rather than re-platforming to Supabase/Vercel. Reasons: auth, DB, storage, jobs and client facades (`ios/Generated/*`) are already generated and wired; 10x's own monorepo conventions (router -> service -> DB helper, `NNN_name.sql` migrations with owner-scoped RLS, leased poller jobs, provider wrappers as one httpx module each) transfer 1:1. Vercel is used by 10x only for its own web app; a Inkflow web app can follow that later.

```
ios/ (SwiftUI)  --Bearer JWT-->  backend/ (FastAPI, tenx.yaml routes)
                                   |- Neon Postgres (services/db/migrations, RLS on owner_id)
                                   |- R2 (book_files, generated_media)
                                   |- jobs: generation worker, daily + weekly digest crons
                                   |- providers: OpenAI, ElevenLabs, fal, Resend, Notion (Phase 2)
ios/Generated/TenxData.swift  --PostgREST (read)-->  Neon data API (owner-scoped)
```

Rules we adopt verbatim from `docs/research/10x-conventions.md`:
- Views never fetch; per-surface `@Observable` stores call the client. Mock at the network boundary.
- Routers are thin; services own logic; DB access is helper functions (`app/db.py`), no ORM.
- Every route registered in `tenx.yaml` and described in `backend/openapi.yaml`; regenerate `ios/Generated/BackendClient.swift`.
- Provider wrappers: module constants for endpoint, key from env, one error class, `async` httpx functions, mocked at module boundary in tests.
- Secrets only in 10x backend secrets; `.env.example` lists names only.
- `AGENTS.md` canonical, `CLAUDE.md` = `@AGENTS.md`; docs updated in the same change.

### 3.1 Data model additions (`services/db/migrations/0003_narration_media.sql`)

Existing: `library_books`, `library_highlights`, `library_notes`, `reading_sessions`, `reading_goals`, `digest_*`.

```sql
-- shared, public-domain works generated once for everyone (owner_id NULL = shared)
works(id TEXT PK, source TEXT, source_ref TEXT, title, author, style_lock TEXT, chapter_count INT, created_at)
work_chapters(id TEXT PK, work_id FK, idx INT, title TEXT, word_count INT, text_object_key TEXT, UNIQUE(work_id, idx))
chapter_media(chapter_id PK FK, scene_prompt, narration_line, keyframe_key, video_key, narration_audio_key,
              status TEXT CHECK IN ('queued','generating','ready','failed'), cost_cents INT, generated_at)
paragraph_audio(id PK, chapter_id FK, paragraph_idx INT, speaker TEXT, voice_id TEXT, audio_key TEXT,
                sentences JSONB, UNIQUE(chapter_id, paragraph_idx))
generation_jobs(id PK, chapter_id FK, kind TEXT, status, attempts INT, lease_owner, lease_expires_at, error, created_at)

-- per-user
library_books + work_id TEXT NULL            -- link a private library row to a shared work
library_notes + kind TEXT DEFAULT 'note'     -- 'note' | 'ai_margin'
library_notes + markdown TEXT DEFAULT ''
usage(owner_id, month DATE, listen_seconds INT, coldopens INT, notes INT, PK(owner_id, month))
```
Private uploads (PDF/EPUB) get a `works` row with `owner_id` set; RLS: shared works readable by all authenticated users, private only by owner. Media keys point to R2 bucket `generated_media` (add to `tenx.yaml`).

### 3.2 Backend routes (`tenx.yaml` + `backend/app/routes/`)

| Route | Handler | Purpose |
|---|---|---|
| `POST /api/v1/works/import` | `routes/works.py` | `{source, ref|url|text|upload_key}` -> parse, split chapters, store text in R2, return work |
| `GET /api/v1/works/{id}/chapters/{idx}` | | chapter text + media status + signed URLs |
| `POST /api/v1/works/{id}/chapters/{idx}/generate` | | enqueue cold open + first N paragraphs (idempotent) |
| `POST /api/v1/works/{id}/chapters/{idx}/narrate?from&count` | | extend narration ahead of the listener |
| `POST /api/v1/notes/ask` | `routes/notes.py` | passage + question -> markdown |
| `GET /api/v1/discover` | `routes/discover.py` | curated classics with generated covers |
| `POST /api/v1/daily-digest`, `/digest/preferences` | exists | |
| `POST /api/v1/weekly-digest` + cron `0 8 * * 1` | `jobs/weekly_digest_job.py` | LLM key points from the week's highlights |
| job `generation_worker` (`python -m app.jobs.generation_worker`) | | leased poller over `generation_jobs`, SKIP LOCKED |

Services: `app/services/{works,chapters,narration,cold_open,notes,discover}.py`; providers: `app/providers/{openai,elevenlabs,fal,resend}.py`.

Generation pipeline per chapter: scene direction (LLM) -> key frame (fal FLUX schnell) -> video (fal MiniMax H3 Max, 10 s, 480p, image-to-video) -> narration line (ElevenLabs) -> speaker tagging (LLM) -> per-paragraph TTS with timestamps (ElevenLabs `with-timestamps`, folded to sentences). Public-domain chapters are generated once and shared.

### 3.3 iOS changes

- `Services/NarrationEngine.swift` protocol; `SpeechReader` becomes `DeviceNarrator`; new `CloudNarrator` plays per-paragraph audio from signed URLs and publishes `activeSentenceRange`.
- `Services/MediaClient.swift` over `BackendClient` (generated) for works/chapters/generate/narrate/notes.
- `Views/ColdOpenView.swift` (AVPlayerLayer, skippable), inserted by `BookReader` before chapter 1 and on chapter change.
- `ReaderView`: consume `activeSentenceRange` from the engine (already handles `spokenWordRange`).
- `Components/AskTheBookSheet.swift`; `NotebookView` renders markdown via `AttributedString(markdown:)`.
- `LibraryView`: Discover shelf; `SignInView`: replace covers.
- Theme: keep "Paper & Ink" tokens; cold open and player use the existing dark backdrop.
- Salvage from `/tmp/inkflow-scaffold`: `FalClient`, `ElevenLabsClient` (sentence folding), `ColdOpenView`, `ReadAloudPlayer` - port into the 10x layering (backend owns fal/ElevenLabs keys; iOS never calls providers directly).

## 4. Build phases

### Phase 0 - Hackathon, today (demo 16:30, pitch 17:15)

Build (real):
- Backend: migration 0003, `works/import` (Gutenberg text + pasted URL), `chapters/{idx}` + `generate` + `narrate`, `notes/ask`, generation worker, providers for OpenAI / ElevenLabs / fal. Deploy via 10x.
- iOS: `CloudNarrator`, `MediaClient`, `ColdOpenView`, sentence highlighting, Ask-the-book sheet, Discover shelf, cover swap on sign-in, onboarding trimmed to 5 steps.
- Precache *A Study in Scarlet* (14 chapters: cold open + narration line + first 12 paragraphs each) through the real pipeline, plus bundle the output in the app as offline fallback for the stage.
- Live path on stage: paste an article link -> cold open generates in ~15 s.

Fake / static today: goal ring uses local sessions only; Discover is a hardcoded list of 8 classics with covers generated once; weekly digest not run.

Skip today: paywall, RevenueCat, Notion, Share Extension, DOCX, account-linking polish.

Timeline: 12:15-13:15 migration + routes + worker skeleton, providers; 13:15-14:15 iOS engine + cold open + client; precache running; 14:15-15:15 ask-the-book, Discover, onboarding trim, sign-in covers; 15:15-16:00 rehearse x5, record backup video, bundle fallback; 16:00 freeze.

### Phase 1 - TestFlight (this week)
Apply migrations to Neon and deploy backend (open milestones in `idea/milestones.md`); library/highlights/notes sync via `TenxData`; RevenueCat + StoreKit 2 with server-side entitlement gating; paywall screens; Resend domain verified, daily + weekly digests live; PostHog + crash reporting on iOS (10x has none, add deliberately); offline chapter download; usage metering.

### Phase 2 - App Store (weeks 2-3)
Notion connector, Share Extension, DOCX, TOC-based EPUB chapters, notes search, stats calendar, privacy manifest, review demo account, screenshots from the cold open, landing page.

### Phase 3 - Growth
Narrator voice cloning, character casting UI, shareable cold-open clips, Android, Kindle import where permitted.

## 5. Conventions and repo hygiene to apply (from 10x)

- Add `AGENTS.md` (root, `ios/`, `backend/`), `CLAUDE.md` = `@AGENTS.md`, `CONTRIBUTING.md`, `.editorconfig`, `.nvmrc` 22, `.python-version`.
- `scripts/{bootstrap,dev,test,check}` wrappers; CI later.
- `backend/openapi.yaml` regenerated when routes change; `ios/Generated/BackendClient.swift` regenerated.
- Tests: `backend/tests/test_<x>_router.py` with `TestClient` + dependency overrides; iOS snapshot tests for new screens.
- Analytics event names registered before emitting.
- Never commit `.env`; `project.yml` scheme env currently contains the Supabase publishable key and preview URLs - fine (publishable), but move to xcconfig in Phase 1.

## 6. Costs and risks

- fal H3 Max: promotional pricing was USD 0.025/s at 480p as of 30 August; use the USD 0.05/s list price for budgeting -> a 10 s cold open is 0.50; 14 chapters ~ USD 7. ElevenLabs Flash ~ USD 0.10/1k chars; a 3k-word chapter ~ USD 1.7. Budget the demo at < USD 40.
- Slop risk: style lock per book + image-to-video from a consistent key frame; intros only, never inline.
- Stage risk: everything for the demo book is precached and bundled; live generation runs on a second, short article.
- Copyright: shared generation only for public-domain works; uploads are private; replace real covers on sign-in.
- App Store: Sign in with Apple (have), account deletion (have), restore purchases + terms (Phase 1), no 100 %-gated content.

## 7. Decisions needed from Karan

1. Confirm staying on the 10x-managed stack (Neon / Better Auth / R2 / 10x backend runtime) vs Supabase + Vercel.
2. Confirm demo book: *A Study in Scarlet* (backup: *Alice in Wonderland*).
3. Provide keys as 10x backend secrets: `OPENAI_API_KEY` (exists), `ELEVENLABS_API_KEY`, `FAL_KEY`.
4. Confirm the 5-step onboarding cut (drop narrator audition + reminders).
