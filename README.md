# ReadSync

Built with [10x](https://10x.app). Edit this README freely — 10x
will not overwrite it once you've made changes.

## Run it

Open `ios/ReadSync.xcodeproj` in Xcode (16.0+, iOS 26 SDK) and
press ⌘R to build and run.

## Project layout

| Folder | What's there |
|--------|--------------|
| `tenx.yaml` | Source-controlled 10x desired state for app services and backends |
| `ios/` | The Swift app source and Xcode project |
| `services/` | Optional managed auth, database, and storage config |
| `backend/` | Optional user-owned backend app code |
| `idea/` | Product brief, build plan, and any market research |
| `growth/` | App Store listing, screenshots, social posts, press kit |
| `release/` | CHANGELOG, per-version release notes, build manifest |
| `.tenx/` | Internal 10x state — chats, snapshots, settings (you can ignore this) |

## Bundle

`app.10x.readsync`

## AI and narration configuration

Provider credentials are server-only. Copy `backend/.env.example` to a local
`backend/.env` or add the same values to the Vercel/10x runtime environment.
Never add these keys to the Xcode scheme or app bundle.

- All reading-summary and study-note prompts use the OpenAI Responses API with
  `OPENAI_MODEL=gpt-5.6-luna` and `OPENAI_REASONING_EFFORT=xhigh`.
- ElevenLabs narration uses the speech-with-timestamps API so character timing
  can drive synchronized highlighting. Set `ELEVENLABS_API_KEY`, then choose
  `ELEVENLABS_VOICE_ID` and `ELEVENLABS_MODEL_ID` when the voice is approved.
- Until provider keys are present, summaries retain their grounded on-device
  fallback and audiobook playback retains the on-device system voices.

## Neon and Vercel

Deploy `backend/` as the Vercel project root. Set `DATABASE_URL` to the pooled
Neon connection string, add the provider variables from `backend/.env.example`,
then apply the SQL files under `services/db/migrations/` with:

```bash
DATABASE_URL='postgresql://…-pooler…' python backend/scripts/apply_migrations.py
```



<!-- 10x:generated-readme -->
