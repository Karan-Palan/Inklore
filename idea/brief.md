## Inkflow — App Clone Brief (Kindle-inspired)

A native SwiftUI ebook + audiobook reading app, structurally faithful to Amazon Kindle's reading experience, differentiated by (1) a strong reading-stats layer (streaks, goals, reading vs listening minutes), (2) a pro audiobook player with read-along, and (3) a daily notes-email digest. Books come from free sources (Project Gutenberg EPUB, Internet Archive text) OR from the user importing their own PDF/EPUB. No store or DRM.

### Authentication (NEW — account-first)
- The app is gated behind sign-in. `AuthStore` (`@Observable`, GoTrue REST, no SDK) owns the session; tokens persist in the Keychain via `AuthKeychain` and auto-refresh.
- `SignInView`: Sign in with Apple (primary, native id-token exchange), Continue with Google (web OAuth + PKCE via ASWebAuthenticationSession), and expandable email/password (sign in / create account).
- Launch flow: restoring → SignInView (signed out) → onboarding (if not completed) → main tabs.
- You tab shows the signed-in name/email and a sign-out menu. The daily-email screen auto-fills the recipient from the signed-in account.
- Provider readiness is external: Supabase Auth must enable Apple + Google with credentials, list redirect `inkflow://auth-callback`, and (for frictionless email) disable Confirm Email. Apple requires the Sign in with Apple entitlement on the bundle ID.

### Reading sources
1. Search free libraries — Project Gutenberg (full EPUBs) + Internet Archive (plain-text), unified search with filters. Cover artwork URLs saved on download.
2. Import your own — any PDF or EPUB from Files (multi-select) or a pasted direct link, type-sniffed by magic bytes, saved locally.

### Onboarding & discovery
- Personalization quiz → personalized reveal. No books seeded; chosen genre drives recommendations.
- Real covers via Open Library covers API with genre-tinted gradient fallback.
- Genre-aware, refreshing recommendations; selected genre persists in UserDefaults.
- AppRouter routes empty-library/onboarding CTAs into a pre-filled Search.

### Formats & readers
- EPUB → pure-Swift unzip + WKWebView render. PDF → PDFKit. Plain text → paginated TextKit with highlights/notes.
- Single `BookReader` routes each book to the right reader.

### Audiobook
- On-device AVSpeechSynthesizer narration, multi-voice, pro player (waveform, sleep timer, speed/pitch, read↔listen switch, read-along). Progress synced across read/listen.

### Daily notes email
- In-app settings on the You tab (`DigestSettingsView`): email address (auto-filled from account), on/off toggle, "send a sample now", and a preview of next email contents.
- `DigestSync` mirrors on-device highlights/notes + in-progress books to Supabase. Auto-syncs when enabled.
- Supabase Edge Function `daily-digest`: emails saved highlights/notes; if none, generates 5–10 study notes via OpenAI and emails those. Delivery via Resend. `last_sent_at` prevents duplicate same-day sends. Scheduled by pg_cron daily at 08:00 UTC.

### Screens
1. Sign in · 2. Library · 3. Search · 4. Reader · 5. Player · 6. You/Stats (Daily notes email card) · 7. Notebook

### Data & Integration Stance
- Local-first SwiftData for books/progress/highlights/notes/sessions/goals.
- Auth + daily email require Supabase (connected). Daily email also needs backend secrets `RESEND_API_KEY`, `DIGEST_FROM_EMAIL`, `OPENAI_API_KEY` (configured).

### Compliance
- No Amazon/Kindle logos or copyrighted covers bundled. Covers fetched at runtime; imports are the user's own files.

### Selected Design System
- Reference: Amazon Kindle · traits clean, content-first, light, pill-filters, cover-grid · seed Clean.
- Palette: Paper & Ink (primary #1A1A1A, accent #1A98C9, background #FFFFFF, surface #F5F6F7).