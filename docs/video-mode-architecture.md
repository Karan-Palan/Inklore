# Video mode implementation

Video mode is a durable backend pipeline, not a long mobile request:

`Book text → authenticated job → structured AI plan → ElevenLabs shots → polling → AVQueuePlayer`

The iOS app extracts plain text from its existing text/EPUB/PDF model and sends
at most 200,000 characters. The backend stores that source only while the job is
queued, asks the configured OpenAI model for a strict `VideoPlan`, validates the
orientation and scene durations, writes the scenes, then clears `source_text`.

The planner chooses `9:16` or `16:9` and creates 4–15 shots of 4, 6, or 8 seconds.
Therefore the script—not a UI duration control—determines the final runtime.
Each scene includes narration, a visual prompt, and a source-grounding note.

`video_summary_worker` runs every minute. It claims one queued plan, submits up
to eight shots per run to `POST /v1/flows/video`, and reconciles provider IDs via
`GET /v1/flows/video/{id}`. The API stays below the app backend's 10-second
request timeout. Duplicate taps return the active job instead of spending twice.

Required deployment steps:

1. Apply `services/db/migrations/0003_video_summaries.sql`.
2. Set `ELEVENLABS_API_KEY`; the key needs Image & Video API access (Pro or above).
3. Keep the default `veo-3.1-fast-generate-001`, or set
   `ELEVENLABS_VIDEO_MODEL=bytedance-seedance-v2.5` after ElevenLabs approves
   ByteDance access for the workspace.
4. Set `OPENAI_API_KEY` and `TENX_AUTH_JWKS_URL` as for the existing backend.

The first UI handoff deliberately adds only “Create video mode” and one status/
player sheet. Completed provider clips play as one continuous queue. A later UI
pass can add a library/history surface without changing the backend contract.

For permanent sharing/export, add a media-finalization worker that downloads
completed clips before ElevenLabs signed URLs expire, concatenates them, and
uploads the final MP4 to the private R2 bucket. Playback immediately after
generation is already implemented; permanent export is intentionally separate.
