# Inkflow — the book that becomes a film as you read it

**One-liner (pitch):** Paste any book, article, or PDF. Every chapter opens with a
cinematic, AI-generated cold open — then the book reads itself to you, full cast,
with the words lighting up as you go.

**Why this wins a 6-hour 8x hackathon:** one hook, demoable in 60 seconds, uses
two sponsors' tech (ElevenLabs voices + fal video, credits from partners), and
nobody in the room has seen a book do this. It is NOT "Kindle + Audible +
Speechify"; it's a new format.

## The 60-second demo (this is the whole product)

1. Search "Sherlock Holmes" → Internet Archive / Open Library result → tap.
   (Fallback: paste a link or pick a bundled epub.)
2. Chapter 1 opens with a 15-second cinematic cold open (fal H3 Max, image→video,
   consistent art style per book) with ElevenLabs narration over it —
   "A Study in Scarlet. Chapter One." Feels like a Netflix intro.
3. Cold open dissolves into the reader. Play → the book reads aloud, narrator +
   distinct voices per character (ElevenLabs), sentence highlighting synced
   to audio (Speechify-style).
4. Long-press a paragraph → "Ask the book" → AI margin note rendered as markdown.
5. Swipe to chapter 2 → its cold open is *already generated* (we prefetch the
   next chapter's clip while you read).

Pitch line at the end: "Next: goals, daily recap emails, Notion export." One
sentence, no demo.

## Pipeline per chapter (runs in background on import)

```
chapter text
  → LLM: {scene_prompt, style_lock, narration_line, cast: [{name, voice_id}], segmented_sentences}
  → fal image model (one key frame in the book's locked style)
  → fal minimax/h3-max/image-to-video (15s, 480p)          ~9s
  → ElevenLabs TTS: narration_line (cold open)                ~2s
  → ElevenLabs TTS with timestamps: chapter body, per speaker  (streamed/prefetched)
```

Style lock = one prompt fragment generated once per book ("ink-wash Victorian
London, muted teal, film grain") reused for every chapter so it reads as one film.

## Scope: build / fake / skip

| Build (must work live) | Fake (hardcode / precache) | Skip |
|---|---|---|
| Reader with synced highlighting | Demo book fully precached (video + audio) so the pitch never waits on the network | Login / auth |
| ElevenLabs multi-voice playback | Second book "generating live" as the wow moment, with a fallback clip | Paywall |
| fal cold-open generation + prefetch of next chapter | Onboarding: 3 screens, Headspace/Calm style, no real prefs | Daily/weekly emails |
| Import: Archive search + paste link + epub | AI notes: one prompt, markdown render | Notion OAuth |
| Chapter picker | Reading goals: static ring on home | Reading targets logic |

## Risks and the answer

- **Video looks like slop** → style lock + image-to-video from a consistent key
  frame, and keep it to a 15s intro, never inline.
- **Live gen fails on stage** → every demo asset precached; live gen runs on a
  second book with a recorded fallback.
- **Voice-per-character is hard** → LLM tags speaker per sentence; cap at
  narrator + 3 voices; unknown → narrator.
- **Archive API** → 1 req/s unauth, 3 req/s with User-Agent + email; pre-download
  3 public-domain epubs.

## Assets to reuse

- `10xapp/10x-mono/ios` — SwiftUI iOS 26 scaffold, `TenXKit` Theme + primitives
  (Liquid Glass chrome). Lift Theme, spacing grid, nav pattern.
- `10xapp/app-screen-capture-research/apps/{headspace,calm,hallow,finch}` —
  onboarding references.
- Sponsor credits: ElevenLabs (voices), fal (video), Codex/Emergent (build).

## Demo book

*A Study in Scarlet* (public domain, dialogue-heavy, 14 short chapters, iconic
opening for a cold open). Backup: *The Great Gatsby* or *Alice in Wonderland*.
