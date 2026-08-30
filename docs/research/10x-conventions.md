---
title: 10x-mono conventions (research for Readsync)
owner: Readsync Engineering
status: research (dated snapshot of 10x-mono as read on 2026-08-30)
last_verified: 2026-08-30
---

# 10x-mono conventions

Source repository: `/Users/neo/Desktop/10xapp/10x-mono` (the `worktrees/` folder and sibling `10x-mono-*` / `10x-macos-*` checkouts were ignored). Every claim below cites the file it was read from. Paths are relative to that root unless absolute.

10x-mono is a polyglot monorepo (ADR 0001, `docs/adr/0001-monorepo.md`) with independent deployables: `backend/` (FastAPI), `web/` (Next.js), `admin/` and `creator/` (Vite/React 18), `macos/`, `ios/` (SwiftUI + `TenXKit`), `website/` (legacy), `contracts/`, `packages/`, `scripts/`, `docs/`, `evals/`, `tools/` (`README.md`, `AGENTS.md` "Repository map").

---

## 1. Agent workflow rules

### 1.1 Instruction files and their hierarchy

- `AGENTS.md` is canonical and applies repository-wide. Every project subtree (`backend/`, `web/`, `ios/`, `contracts/`, `packages/`, `scripts/`, `macos/`, `admin/`, `creator/`, `website/`, `packages/portal-ui/`, `backend/runtime/`, `backend/managed-better-auth/`) has its own `AGENTS.md` that "may add stricter or more specific controls but may never weaken or contradict root requirements" (`AGENTS.md` "Instruction scope").
- Every `CLAUDE.md` contains exactly the text `@AGENTS.md` and nothing else. Root `CLAUDE.md` is literally 11 bytes: `@AGENTS.md`. This is machine-enforced: `scripts/docs-check` fails if any scope's `CLAUDE.md` is not exactly `@AGENTS.md`, if `AGENTS.md`/`CLAUDE.md` is missing in a scope, or if a scope lacks `docs/README.md` (`scripts/docs-check` lines 8-24).
- Every `.md` file directly under a project's `docs/` must be listed by filename in both that project's `AGENTS.md` and its `docs/README.md`; every root `docs/*.md` must be listed in root `AGENTS.md` and `docs/README.md` (`scripts/docs-check` lines 26-46). Explanations, diagrams and runbooks go in `docs/`, not in `AGENTS.md` ("Keep instructions concise and enforceable", `AGENTS.md`).
- Durable documents carry YAML front-matter `title`, `owner`, `status`, `last_verified` (`docs/README.md` "Maintenance standard"; validated by `scripts/docs-validator.mjs`, invoked from `scripts/docs-check`). Unknown facts are written as `TBD(owner, target date)`.

### 1.2 `AGENTS.md` (root) - key content

- **Mission + canonical domains** block at top (`10x.app`, `api.10x.app`, `admin.10x.app`, `runtime.10x.app`, `fleet.10x.app`, `downloads.10x.app`, `creators.10x.app`).
- **Cold-start routing**: fetch remote state, diff against `origin/main`, read root and nearest `AGENTS.md`, route via `docs/features/README.md` (user journeys) or `docs/systems/README.md` (outages/providers), then `docs/runbooks/incident-triage.md`; reproduce, baseline, fix, run focused + project gates, update docs in the same PR.
- **Identity and Git authority**: only exact `gh api user --jq .login` handles `Timmy0x`, `Karan-Palan`, `Alby-code` are developers; everyone else is a contributor. Contributors branch as `contrib/<github-login>/<short-description>`, never push `main`, never force-push, open draft PRs, request developer review. Developers merge with `./scripts/merge-pr <n> --confirm-approval-bypass --squash` (helper validates identity, non-draft, targets main, CI green, current with main, no unresolved conversations before `gh pr merge --admin`). Full policy in `docs/contribution-policy.md`.
- **Sources of truth**: `docs/product.md` for intended behavior; FastAPI routes/models + `contracts/openapi/*.json` for HTTP; migrations + deployed DB for schema; `packages/design-tokens/tokens.json` for tokens (ADR 0002); live billing catalog for prices; deployed config for runtime values. "When authoritative sources disagree, identify the conflict and owner. Do not silently select or normalize one."
- **Standard commands** (all root wrappers): `./scripts/bootstrap [--check]`, `./scripts/doctor`, `./scripts/dev <project>`, `./scripts/test <project>`, `./scripts/check <project|design|contracts|docs|all>`, `./scripts/affected [base-ref]`, `./scripts/generate <artifact> [--check]`, `./scripts/docs-check`, `./scripts/docs-impact-check [base-ref]`, `./scripts/openapi-compat [base-ref]`, `./scripts/governance-check`, `./scripts/evals`, `./scripts/merge-pr`.
- **Required workflow** (verbatim list): 1) inspect `git status`, this file, nearest project `AGENTS.md`, relevant docs and existing tests; 2) identify affected projects and whether the change crosses API/event/data/design/fixture/auth/deployment/billing boundaries; 3) smallest coherent change, no combined migration + rewrite + cleanup; 4) update tests, contracts, generated artifacts, docs, runbooks when source behavior changes; 5) targeted checks first, then `./scripts/affected`; 6) report changed behavior, exact verification, deployment/migration impact, residual risk, unverified assumptions.
- **Architecture and dependency rules**: deployables talk only via declared HTTP/WebSocket/event/file/generated-code contracts and never import another deployable's private source; browser and iOS clients are thin ("Server state belongs in TanStack Query or project stores backed by API calls"); serialized cross-project data needs a canonical schema/fixture owner; "Change the schema/source first, regenerate consumers, and update affected tests in the same change"; never hand-edit generated files (generated paths must name their generator in nearest `AGENTS.md`/README); shared packages only with two current consumers, no `utils` dumping grounds; UI stays platform-native, React and SwiftUI never cross platform boundaries.
- **Safety**: never commit secrets/`.env`/customer data/build outputs; explicit human approval for API breaks, destructive migrations, auth, billing, privacy, production deps, signing, deployment workflows; expand/migrate/contract for DB changes; preserve unrelated working-tree changes; provider calls in tests are opt-in.
- **Testing expectations**: behavior changes need tests at the lowest useful level; bug fixes need a regression test; API changes need server tests plus contract and client verification; never delete/skip/loosen assertions to pass CI; "Treat generated-artifact drift as a failure."
- **Documentation expectations**: update docs in the same change; every behavior change updates the owning feature packet/system page/runbook or supplies the PR-template no-impact reason; ADRs for durable cross-project decisions; dated plans/audits labeled non-authoritative.
- **Completion checklist**: nearest instructions followed; tests run and reported accurately; contracts/fixtures/generated/docs consistent; secrets/privacy/migration risk reviewed; new files have clear ownership and durable location.

### 1.3 `docs/agent-workflow.md` (the public operating standard)

Sections and rules, condensed:
- **Start from evidence**: sync remote, read nearest `AGENTS.md`, reproduce through the user-facing path, establish a baseline ("A plausible explanation is not [evidence]"), label claims confirmed/disproven/inferred.
- **Diagnose before changing**: follow the real request path, form a falsifiable hypothesis, read-only inspection first, change one variable at a time, "If the result does not move, say the hypothesis was wrong."
- **Scope and product decisions**: smallest coherent change; never silently reduce scope; confirm net-new product behavior before implementing; "Long collections default to 50 items per page with pagination unless the feature contract explicitly defines another limit."
- **Implementation standard**: comments explain durable mechanisms only (no incident stories, dates, names); security fails closed; generated files change through generators; warnings/lint/flaky tests are defects; no credentials in code/docs/fixtures/screenshots; "Use a plain hyphen. Do not use Unicode em dashes in prose, UI copy, comments, commit messages, or pull requests."
- **Verification standard**: focused test first, then project gate, then closest safe E2E; "A unit test is not E2E evidence. A local mock is not live-service evidence."; UI work inspected at representative sizes/states (spacing, typography, focus, loading, empty, error, disabled, dark/light, accessibility); "Merged is not deployed."; record exact commands and what was not run.
- **Documentation is part of the change**: run `./scripts/docs-impact-check <base-ref>` and `./scripts/docs-check`. Adding an HTTP route decorator requires the regenerated `contracts/openapi/*.json` in the same change and the path named in a contract document (feature packet `system-and-code-map.md`, `docs/systems/*/README.md`, `docs/api-and-contracts.md`, or project `docs/`); overriding requires `Route docs unchanged reason: <20+ chars>` in the PR body.
- **Commits, review, and delivery**: stage only intended files; "Never add an agent name as a co-author."; "Use a concise scoped commit subject. The body should explain the root cause, the durable change, and exact verification"; deliver verified increments; sync with `origin/main` before handoff.
- **Working with parallel agents**: give evidence + a question, partition by non-overlapping ownership, independently review their diff, require handoff to state source authority/deployment unit/verification/unverified assumptions.
- **What stays outside the repository**: secrets, account identifiers that create risk, customer data, machine-specific state, incident narratives.

Observed commit subject style in `git log` (e.g. `fix(billing): stop plan upgrades failing on the current plan's cadence (#781)`, `docs: navigate cloud preview/build/billing subsystem and E2E verification (#788)`, `Fix publishing signing-team persistence (#784)`): mix of conventional-commit `type(scope): imperative` and plain imperative sentence subjects; squash-merged with PR number suffix.

### 1.4 `CONTRIBUTING.md`

Six-step change process: focused branch; confirm affected project/contract/data/design/deployment/doc boundaries; smallest coherent change with tests; run project check and `./scripts/affected`; update docs, generated artifacts, migration/runbook steps in the same PR; describe user impact, verification, rollout, rollback, remaining risk. Breaking API/auth/billing/DB/infra/signing/prod-config changes require owners in `docs/ownership.md`. "Do not commit `.env` files, secrets, provider exports, customer data, build artifacts, or generated caches. Use each project's `.env.example` as the key catalog."

### 1.5 PR template (`.github/pull_request_template.md`)

Sections: What and why; Contribution authority (handle, role, source branch, developer approver, privileged-operation declaration); Affected areas checklist; Contract, data, and security impact (admin data access, synthetic fixtures, `Intentional breaking API change` + reason, `./scripts/openapi-compat origin/main`); Verification performed; Design and user-interface impact (a11y, states, light/dark evidence, cross-platform mappings); Deployment and rollback; Documentation updated (affected systems/features, docs changed, E2E path used, live boundary not verified, `Docs unchanged reason:` / `Route docs unchanged reason:`); Known risks and assumptions.

### 1.6 Documentation structure (`docs/README.md`, `docs/features/README.md`)

- Root `docs/` is a flat set of cross-project documents each summarized in `docs/README.md` (agent-workflow, architecture, business, product, unit-economics, design-system, domains-and-environments, data-and-analytics, api-and-contracts, agent-statistics, security-and-privacy, development, testing-strategy, evals, deployment-and-releases, deployment-inventory, observability, incident-response, contribution-policy, ownership, glossary).
- Subfolders by class: `features/` (user-journey packets), `systems/` (deployable maps), `adr/`, `design/`, `runbooks/`, `proposals/`, `audits/`, `migration/`, `external-systems/`, `archive/`.
- **Feature packet contract** (`docs/features/README.md` "Packet contract"): each feature dir has exactly `README.md`, `user-journey.md`, `system-and-code-map.md`, `testing-and-e2e.md`, `operations-and-release.md`; a `_template/` exists (`docs/features/_template/README.md` with `feature_id` front-matter and sections Outcome and users / Scope and boundaries / Production authority / First response to a report / Packet map / Known gaps); `registry.yml` is the machine-checked inventory of code roots, test roots, deployment units, E2E readiness. Status vocabulary: `active`, `partial`, `planned`, `deprecated`.
- ADRs (`docs/adr/README.md`): numbered `NNNN-kebab-title.md`, `0000-template.md`, one-line index entries; later ADRs supersede explicitly.

### 1.7 Testing gates (`docs/testing-strategy.md`, `.github/workflows/ci.yml`)

Path-aware minimums table: `backend/**` -> backend compile/test + specialized gates; `web/**` -> typecheck, lint, Vitest, Next build; `ios/**` -> package validation, Xcode tests, snapshots; API contract -> server tests + affected consumer tests; `packages/design-tokens/**` -> token drift + all consuming checks; shared component/content semantics -> every affected platform check + visual evidence per `docs/design/visual-qa.md`.

CI (`.github/workflows/ci.yml`) has a `changes` job that pipes `git diff --name-only` through `scripts/classify-paths` and fans out to jobs: `docs`, `docs_impact`, `governance`, `design_tokens`, `analytics_events`, `admin_metrics`, `openapi`, `asyncapi`, `realtime_protocol`, `backend`, `web`, `portal_ui`, `admin`, `creator`, `website`, `macos`, `ios`. The docs job also runs `bash -n scripts/*` and `git diff --check`. Default tests never mutate production or paid providers; live E2E is workflow-dispatch with spend bounds; snapshot updates require visual review; flaky tests are quarantined with owner/reason/removal date, never retried away.

### 1.8 Ownership and security

`docs/ownership.md` maps areas to accountable roles and required specialist reviews (e.g. iOS client -> Native engineering, review by Design/accessibility/release). `SECURITY.md`: never commit secrets; `.env.example` is names-and-docs only; auth/billing/migration/prod-workflow changes require security review.

---

## 2. Backend

### 2.1 Language, framework, boot

- Python `3.12.7` pinned in `.python-version` and `backend/runtime.txt` (`python-3.12.7`); `docs/development.md` says bootstrap uses `uv venv --seed --python 3.12.7` when available (`scripts/bootstrap` lines 36-50).
- FastAPI `==0.141.1`, pydantic `==2.13.4` (both `==`-pinned so the OpenAPI export is deterministic, ADR 0024), `uvicorn>=0.32.0`, `orjson`, `httpx`, `websockets`, `redis`, `posthog>=7.12.0`, `supabase>=2.10.0`, `PyJWT[crypto]`, `psycopg[binary,pool]`, `boto3`, `anthropic==0.120.2`, `openai>=1.0.0` (`backend/requirements.txt`). Dev adds `pytest>=8.3,<10`, `pytest-asyncio`, `pytest-xdist` (`backend/requirements-dev.txt`).
- Entry: `backend/app.py` is one line `from api.main import app`; `backend/vercel.json` declares `"framework": "fastapi"` (the production API is deployed on Vercel, see 2.10). `api/main.py` configures root logging with `logging.basicConfig(..., force=True)` to stdout, uses `ORJSONResponse`, CORS middleware, a streaming-safe GZip middleware (`api/gzip_middleware.py`), includes versioned routers via `build_versioned_router(version_name)` for each version plus an unversioned legacy alias router (`api/main.py` lines 187-189), and calls `apply_docstring_summaries(app)` last (line 489).
- Local run: `./scripts/dev backend` -> `backend/scripts/dev.sh`, which pins `backend/.venv/bin/python`, sources `backend/.env` with `set -a`, preflights `boto3, psycopg, cryptography`, then `exec python -m uvicorn api.main:app` without `--reload` ("reload can interrupt streaming requests", `backend/docs/local-development.md`). Port 8000.

### 2.2 Project layout under `backend/` (`backend/AGENTS.md` "Layout", `backend/docs/architecture.md`)

| Path | Role |
|---|---|
| `api/` | FastAPI app: `main.py`, `config.py` (settings), `dependencies.py` (auth deps), `versioning.py`, `versions/v1`, `versions/v2` (version routers), `routers/` (one file per domain: `admin.py`, `billing.py`, `builder.py`, `feedback.py`, `notifications.py`, `onboarding.py`, `paywalls.py`, `paywall_templates.py`, `projects.py`, `publishing.py`, `experiments.py`, `sessions.py`, `supabase.py`, `superwall.py`, ...), `schemas/` (pydantic response models shared across routers: `admin*.py`, `common.py`, `publishing.py`, `user_backends.py`), `services/` (~150 domain/integration modules incl. `billing.py`, `billing_payments.py`, `email_sender.py`, `analytics.py`, `supabase_direct.py`, `feedback.py`, subpackages `app_research/`, `builder/`, `user_apps/`), `generated/` (generated constants e.g. `analytics_events.py`), `assets/`, `http.py` (shared httpx client), `gzip_middleware.py`, `billing_units.py` |
| `shared/` | Backend-only primitives shared across service processes: `openapi_summaries.py`, `logging_privacy.py`, `client_ip.py`, `runtime_bus.py`, `tenx_contract/` (generated realtime vocab) |
| `realtime/`, `runtime_gateway/`, `runtime/`, `artifact_viewer/`, `eval_runtime/` | Separate deployable processes (fleet control plane, runtime gateway, packaged agent runtime, isolated HTML viewer, eval harness) |
| `supabase/migrations/` | 232 ordered SQL migrations `NNN_snake_description.sql` (e.g. `012_create_feedback_submissions.sql`, `205_user_onboarding_plan.sql`, `241_admin_journey_turn_milestones.sql`) |
| `tests/` | 426 entries, flat `test_*.py` files plus `conftest.py` and `admin_payload_fixtures.py` |
| `scripts/` | dev/verification/maintenance/worker entrypoints: `dev.sh`, `export_openapi.py`, `openapi_compat.py`, `export_asyncapi_schemas.py`, `run_notification_worker.py`, `run_publishing_worker.py`, `run_backend_maintenance_worker.py`, `run_runtime_gateway.py`, `run_backend_db_auth_test_gate.sh`, `sync_bundled_skills.py`, `check_primitives.py`, `check_app_templates.py` |
| `skills/`, `inspirations/`, `archetypes/`, `primitives/`, `app-templates/`, `paywall-templates/` | Agent-facing content catalogs (10x-specific) |
| `managed-better-auth/`, `limrun-bridge/` | TypeScript/Express side services with their own `AGENTS.md` |
| `render.yaml`, `render.runtime.yaml`, `render.notifications.yaml`, `fly.*.toml`, `Dockerfile.*`, `vercel.json` | Provider service definitions |
| `docs/` | Backend docs indexed in `docs/README.md` and `AGENTS.md` (architecture, local-development, testing, deployment, security, ops-alerting, pricing-system, ...) |
| `.env.example` | 311 env var names with comments; the only tracked env file |

### 2.3 Router / service / model organization

Binding rules from `backend/AGENTS.md` "Architecture rules":
- "Routers validate transport concerns; business rules live in services; shared persistence access remains explicit and testable."
- "Give every route handler a one-line docstring: its first line is the OpenAPI summary (`shared/openapi_summaries.py`), so keep it under 80 chars."
- "Validate tenant ownership and authorization at every object boundary. Never trust a client-provided user, project, backend, or organization identifier without server-side resolution."
- Additive response/schema changes preferred; migrations ordered, reversible, safe against deployed app, covered by tests.
- "Provider SDKs and network calls stay behind service boundaries and are mocked by default in tests."

Example router (`backend/api/routers/feedback.py`):

```python
router = APIRouter(prefix="/feedback", tags=["feedback"])

class FeedbackSubmissionRequest(BaseModel):
    source: str = Field(..., min_length=1, max_length=40)
    category: str = Field(..., min_length=1, max_length=40)
    message: str = Field(..., min_length=2, max_length=5_000)
    ...

@router.post("", response_model=FeedbackSubmissionResponse)
async def create_feedback_submission(
    payload: FeedbackSubmissionRequest,
    request: Request,
    user: AuthenticatedUser = Depends(get_current_user),
) -> FeedbackSubmissionResponse:
    row = await feedback.submit_feedback(request=request, user=user, ...)
    return FeedbackSubmissionResponse(id=str(row["id"]))
```

Request/response pydantic models live either inline in the router (small) or in `api/schemas/*.py` (shared/admin). Services are plain async module functions (`api/services/feedback.py: async def submit_feedback(*, request, user, source, ...)`) that normalize input, raise `HTTPException(status_code=422, ...)` for validation, call persistence helpers, and emit analytics. Versioning: `api/versioning.py` composes `/api/v1` and `/api/v2` prefixes from `api/versions/v1` and `v2` routers; `CURRENT_API_VERSION = v1`; `/api/...` without a version is a legacy alias to current.

### 2.4 Supabase usage

- **Auth**: `api/dependencies.py` defines `security = HTTPBearer(auto_error=False)`, `@dataclass(frozen=True) class AuthenticatedUser(id, email, raw_jwt, auth_method="supabase", is_readonly=False, ...)`, `class AdminUser(AuthenticatedUser)`, and dependencies `get_current_user`, `get_current_user_low_latency` (verifies the Supabase JWT locally via cached JWKS, `SUPABASE_JWKS_CACHE_TTL_SECONDS = 3600`), `get_optional_current_user`. Remote verification hits Supabase `/auth/v1/user` with retry (`_AUTH_VERIFY_ATTEMPTS = 3`), an identity cache (`AUTH_CACHE_TTL_SECONDS = 300`, max 2048 entries) and single-flight locks per JWT. Admin API keys (`tenx_admin_*`, `tenx_agent_*`) are a separate opt-in principal type.
- **Postgres access**: the API talks to Supabase PostgREST over httpx using the service-role key; helpers live in `api/services/billing.py` (`_rest_url -> f"{settings.supabase_url}/rest/v1/{path}"`, `_select`, `_select_all`, `_select_all_keyset`, `_rpc`, `_insert_rows(table, payload, *, on_conflict, upsert, ignore_duplicates, return_representation, select)` using `Prefer: return=representation|minimal` and `resolution=merge-duplicates`). Other services import these (`feedback.py` calls `billing._insert_rows("feedback_submissions", payload)`). A direct-Postgres lane via `psycopg` pool exists only for runtime-critical RPCs when `SUPABASE_DB_URL` is set (`api/services/supabase_direct.py`), falling back to PostgREST.
- **RLS**: 58 of 232 migrations enable RLS; policies like `CREATE POLICY "Users can CRUD own projects"` exist, but `docs/security-and-privacy.md` states "Database RLS is defense in depth; service-role code still scopes queries." Backend uses `SUPABASE_SERVICE_ROLE_KEY`; clients get `SUPABASE_ANON_KEY` for auth only.
- **Storage**: buckets referenced by env (`APP_RESEARCH_STORAGE_BUCKET=app_research`, `PUBLISHING_SMOKE_STORAGE_BUCKET=publishing-artifacts`, private `agent-runtime-artifacts` with signed URLs per `docs/security-and-privacy.md`); inference helper `api/services/storage_bucket_inference.py`.
- **Env names**: `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, optional `SUPABASE_DB_URL`, plus a prod-from-local guard `TENX_ALLOW_PROD_FROM_LOCAL` / `TENX_PRODUCTION_SUPABASE_PROJECT_REFS` (`backend/.env.example`, `api/config.py`).

### 2.5 Migrations tooling

- Files: `backend/supabase/migrations/NNN_snake_case.sql`, three-digit zero-padded sequence, wrapped in `BEGIN; ... COMMIT;`, idempotent DDL (`CREATE TABLE IF NOT EXISTS`, `DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_constraint ...)`), `ENABLE ROW LEVEL SECURITY` on user tables, FKs to `auth.users(id) ON DELETE CASCADE` (`012_create_feedback_submissions.sql`).
- Applied with the Supabase CLI (`supabase db push` appears in `backend/docs/credit-normalization-rollout.md`); `backend/supabase/.temp` is the CLI's state dir. Policy: expand/migrate/contract; "Apply additive migration `201_user_onboarding_plan.sql` before shipping a client that depends on the field" (`docs/api-and-contracts.md`). Migrations are referenced by number in docs and covered by `tests/test_*_migration.py` files.

### 2.6 Config / env loading

`api/config.py`: plain `class Settings` with `@property` accessors reading `os.getenv(...)` (not pydantic-settings), e.g. `def supabase_service_role_key(self) -> str`. `python-dotenv` loads `backend/.env` at import unless `VERCEL` is set (`_should_load_dotenv`), with a narrow allowlist of explicit env overrides preserved across the load. A single module-level `settings = Settings()` is imported everywhere (`from api.config import settings`). Env naming: `UPPER_SNAKE`, product-prefixed `TENX_*` for internal toggles, provider-prefixed otherwise (`STRIPE_*`, `POSTHOG_*`, `RESEND_*`, `OPENAI_*`). `.env.example` documents every name with a comment and a blank or obviously fake value.

### 2.7 Background jobs / queues / workers

No Celery/RQ. Pattern is **durable rows in Postgres + long-running poller processes with leases**:
- `scripts/run_notification_worker.py` (Render worker declared in `render.notifications.yaml`): declares `REQUIRED_ENVIRONMENT`, polls notification facts, fans out leased per-channel deliveries, retries (`backend/docs/architecture.md`, ADR 0018).
- `scripts/run_publishing_worker.py` (Render Docker worker `tenx-publishing-worker`, `Dockerfile.publishing-worker`): claims one run at a time with `PUBLISHING_WORKER_LEASE_SECONDS`, `PUBLISHING_WORKER_ID`, idle/error sleep env vars (`backend/render.yaml`).
- `scripts/run_backend_maintenance_worker.py` on Fly (`fly.backend-maintenance.toml`, `Dockerfile.maintenance`).
- Render `cron` services run `scripts/run_app_research_daily.py` on `"15 7 * * *"` (`backend/render.yaml`).
- Redis is used only by the runtime gateway/controller for wake pub/sub with bounded pools (`TENX_RUNTIME_REDIS_*`); it fails open to DB polling.
- Rule: "Long-running or externally retried work uses idempotency keys and durable state rather than relying on a single HTTP request." (`backend/docs/architecture.md` "Boundary rules").

### 2.8 Third-party provider wrappers

Pattern: one small service module per provider, direct `httpx` calls against the provider REST API (not always the SDK), keys read from `settings`, a module-specific error class, mocked at the module boundary in tests.
- **Email (Resend)**: `api/services/email_sender.py` - `RESEND_ENDPOINT`, `class EmailSendError(RuntimeError)`, `async def send_email(*, to, subject, text, from_email=None, reply_to=None, html=None, attachments=None, idempotency_key=None) -> str`. Inbound webhooks verified by Svix signature in `api/services/inbound_email.py` (`routers/feedback.py`). Auth emails via SES (`AUTH_EMAIL_PROVIDER=ses`).
- **Stripe**: `api/services/billing_payments.py` - `STRIPE_API_BASE = "https://api.stripe.com/v1"`, `STRIPE_API_VERSION = "2026-07-29.dahlia"`, `_stripe_headers()`, `async def _stripe_request(...)` with timing logs; test/live key pairs selected by `STRIPE_MODE` (`STRIPE_TEST_SECRET_KEY`, `STRIPE_LIVE_SECRET_KEY`, webhook secrets, portal config IDs in `.env.example`).
- **Model providers**: `anthropic` and `openai` SDKs; routing is server-owned via OpenRouter (ADR 0006); keys `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `OPENROUTER_API_KEY`, `CEREBRAS_API_KEY`.
- **PostHog (server)**: `api/services/analytics.py` - guarded import (`try: from posthog import Posthog except: Posthog = None`), best-effort, an `_EVENT_PROPERTY_ALLOWLIST: dict[str, frozenset[str]]` per event name that drops unlisted properties, environment from `APP_ENV|VERCEL_ENV|ENVIRONMENT`, gated by `POSTHOG_ENABLED` (off by default). Event names come from `api/generated/analytics_events.py`.
- **Slack ops notifications**: `api/services/slack_notifications.py`, silenced globally in tests by an autouse fixture.
- **ElevenLabs / fal**: not present anywhere in the repo (grep for `elevenlabs`, `fal_client`, `fal.ai` returned nothing). Readsync will need to add these following the `email_sender.py` shape.
- **Sentry (backend)**: not used; there is no `sentry` in `requirements.txt` or `api/main.py`. Backend error tracking is PostHog's exception capture from the global `Exception` handler in `api/main.py` (`docs/observability.md` line 97).

### 2.9 OpenAPI contract (`contracts/`)

- `contracts/openapi/product-api.json`, `runtime-gateway.json`, `realtime.json` are rendered **in-process** by `backend/scripts/export_openapi.py` via `app.openapi()` (never served: `/openapi.json`, `/docs`, `/redoc` return 404 in production). Output is deterministic: sorted keys, two-space indent, trailing newline, `info.x-tenx-generated` with generator name, pinned `fastapi`/`pydantic` versions, source module; refuses duplicate `operationId` or undescribed router tags (ADR 0024, `contracts/openapi/README.md`).
- Commands: `./scripts/generate openapi [--check]` (drift gate), `./scripts/openapi-compat <base-ref>` (`backend/scripts/openapi_compat.py`; fails on removed path/operation/property, added required field/param, changed type, removed enum value, added security requirement; escape hatch is the PR checkbox `Intentional breaking API change` + reason).
- Non-FastAPI HTTP surfaces get hand-authored documents marked `info.x-tenx-generated.mode: hand-authored` (`limrun-bridge.json`, `managed-better-auth.json`, `web-routes.json`, `website-routes.json`), gated by `./scripts/generate openapi-handwritten --check`.
- Consumers: web generates `web/src/lib/api/schema.d.ts` with `openapi-typescript@7.13.0` via `./scripts/generate web-api` (= `npm run gen:api`); `web/src/lib/api/types.ts` is the hand-named seam. **iOS has no generated client**: "iOS has handwritten Codable models/API client under `ios/Sources/TenXKit/API/`" and "No Swift client is generated yet" (`docs/api-and-contracts.md`).
- Other contract registries in the same folder, each with `README.md`, `scripts/generate.mjs`, `--check` mode and a `node --test` suite: `analytics-events/events.json` (PostHog names -> `web/src/lib/generated/analytics-events.ts`, `backend/api/generated/analytics_events.py`), `realtime-protocol/protocol.json`, `asyncapi/` + `fixtures/realtime/` (one fixture per payload schema decoded by backend, web, mac tests), `admin-metrics/metrics.json`, `api-portal/`, `evals/`.
- `contracts/AGENTS.md`: "Every generated artifact must identify its generator, pinned tool version, source, command, and consumers."; "Never hand-edit generated output or put private/customer/provider data in a fixture."; "Prefer additive compatibility."

### 2.10 Deployment split: Vercel vs Render vs Fly

From `docs/deployment-inventory.md`, `docs/domains-and-environments.md`, `backend/docs/deployment.md`, `backend/render.yaml`:
- **Vercel** (team `10x-teams-projects`): `api.10x.app` = project `10x-api-v2`, root `backend`, `framework: fastapi` (`backend/vercel.json`) - the main FastAPI control plane runs as a Vercel Python function; `10x.app` = `10x-web` root `web`; `admin.10x.app`, `creators.10x.app`, `downloads.10x.app`, `apps.10x.app` (hosted paywall HTML).
- **Render**: long-lived and stateful processes that cannot run on Vercel functions - `tenx-runtime-control` (runtime WebSocket gateway, `runtime.10x.app`, `Dockerfile.runtime-control`), `tenx-runtime-controller`, publishing API staging + publishing workers, `tenx-managed-better-auth` (Node), `limrun-bridge` (Node), notification worker, app-research cron jobs. Blueprints set `rootDir: backend`, `autoDeployTrigger: "off"` (manual deploys), secrets as `sync: false`, shared `envVarGroups`.
- **Fly**: backend maintenance worker, runtime Sprites, publishing smoke app (`fly.backend-maintenance.toml`, `fly.publishing-worker.toml`).
- **AWS EC2**: fleet control plane `fleet.10x.app`.
- **`packages/vercel-api-origin`**: a tiny dependency-free ESM package (`src/index.js`, `index.d.ts`, `tests/index.test.mjs`) exporting `resolveVercelApiOrigin(options)` + the canonical Vercel project name. It reads Vercel **Related Projects** data so each frontend Git preview targets the API preview for the same branch and production targets the API production alias; explicit `NEXT_PUBLIC_API_URL` is only the local/CLI fallback and a build without either fails closed (ADR 0015). Consumed in `web/next.config.ts` (`env: { NEXT_PUBLIC_API_URL: apiOrigin }`) and `web/vercel.json` (`"relatedProjects": ["prj_..."]`).
- Rollback on Vercel = promote previous immutable deployment; DB changes follow expand/migrate/contract (`backend/docs/deployment.md`).

### 2.11 Testing approach

- `./scripts/test backend` = `cd backend && PYTHONPATH=backend:backend/runtime/src python -m pytest -q` (`scripts/test`). `./scripts/check backend` additionally runs `python -m compileall -q api realtime runtime_gateway shared` and content-catalog checks (`scripts/check`). Fast gate: `backend/scripts/run_backend_db_auth_test_gate.sh`.
- No `pytest.ini`/`pyproject.toml`; config is in `tests/conftest.py` autouse fixtures that silence Slack notifications and clear module-global caches between tests.
- Router tests use `fastapi.testclient.TestClient(app)`, `app.dependency_overrides[get_current_user] = _fake_user` with a frozen `AuthenticatedUser`, `unittest.mock.patch(...)`/`AsyncMock` on the service function imported into the router module, and `self.addCleanup(app.dependency_overrides.clear)` (`tests/test_feedback_router.py`). Style is `unittest.TestCase` classes run under pytest.
- Contract tests: `tests/test_openapi_export.py`, `tests/test_openapi_compat.py`, `tests/test_asyncapi_contracts.py`, `tests/test_admin_event_name_contract.py`.
- "Tests must isolate remote providers and time, avoid production credentials, and clean up local resources." Files named `*real_cloud*`, `*smoke*`, `e2e_*` are opt-in (`backend/docs/testing.md`).

### 2.12 Observability (backend)

`docs/observability.md` "Standards": logs include service, environment, request/turn/project correlation IDs, stable error code, duration, no secrets; `backend/shared/logging_privacy.py` logs exception class + file/line/function, never a traceback with raw values; health endpoints split liveness/readiness (`/healthz`, `GET /healthz/stream-probe`); metrics have owners/units/bounded labels; deployment markers include commit SHA.

---

## 3. iOS

### 3.1 Layout (`ios/AGENTS.md` "Layout", `ios/README.md`)

```
ios/
  AGENTS.md, CLAUDE.md (=@AGENTS.md), README.md
  Package.swift, Package.resolved
  App/TenXApp.xcodeproj            # thin launch shell
  App/TenXApp/TenXAppApp.swift     # @main; calls MockHandlers.install(); hosts RootView
  Sources/TenXKit/
    API/        APIClient.swift, Models.swift, Stores.swift
    Theme/      Theme.swift, Generated/DesignTokens.swift   (generated, never edited)
    Primitives/ TenXPrimitives.swift, TenXIconButton.swift, TenXViewHeader.swift,
                PipelineStepper.swift, FlowLayout.swift, UserAvatarView.swift
    Glass/      GlassChrome.swift
    Mocks/      MockTransport.swift, MockHandlers.swift, Fixtures.swift
    Resources/Fixtures/*.json      (exported from web, never hand-edited)
    Gallery/    GalleryView.swift  (primitive specimen gallery)
    Views/      RootView, ProjectsView, CreateView, AccountView,
                Workspace/{WorkspaceView, ChatView, PreviewView, ReleaseView, MoreView, SurfaceHeader,
                           Backend/{BackendOverviewScreen, BackendUsersScreen, EnvironmentScreen},
                           Chat/{ChatComponents, DecisionCard}}
  Tests/TenXKitTests/ FixtureParityTests.swift, MockTransportTests.swift, ScreenSnapshotTests.swift, __Snapshots__/
  scripts/export-fixtures.mjs
  docs/ README, architecture, local-development, testing, design-system, navigation, deployment
```

`Package.swift`: `swift-tools-version: 6.2`, `platforms: [.iOS(.v26)]`, one library product `TenXKit`, dependency `pointfreeco/swift-snapshot-testing from: "1.17.0"` (resolved 1.19.3 in `Package.resolved`; the only external dependency, test-only), target `TenXKit` with `resources: [.process("Resources")]` and `.swiftLanguageMode(.v5)`, test target `TenXKitTests` depending on `SnapshotTesting`.

Xcode project (`App/TenXApp.xcodeproj/project.pbxproj`): a plain hand-checked pbxproj (no xcodegen/`project.yml`, no `.xcconfig`, no `Info.plist` - `INFOPLIST_KEY_*` generation), linking the local package. Settings: `PRODUCT_BUNDLE_IDENTIFIER = app.tenx.ios`, `IPHONEOS_DEPLOYMENT_TARGET = 26.0`, `CODE_SIGN_STYLE = Automatic`, `MARKETING_VERSION = 0.1.0`, `CURRENT_PROJECT_VERSION = 1`, `SWIFT_VERSION = 5.0`, `TARGETED_DEVICE_FAMILY = 1` (iPhone only), portrait only. One shared scheme `TenXApp` with no launch arguments; tests run through the auto-generated `TenXKit` package scheme. `ios/.claude/launch.json` defines a `serve-sim` launch config (`npx -y serve-sim -p 3200`) used for visual verification of glass surfaces.

### 3.2 "Architecture rules (binding)" - `ios/README.md`, verbatim

1. **Views never fetch.** Screens consume per-surface `@Observable` stores; stores call `APIClient`; nothing else touches the network.
2. **Mock at the network boundary.** Screens, stores, and `APIClient` are byte-identical in mock and live mode. Wiring a surface live = deleting its route from `Mocks/MockHandlers.swift`. `liveHandlers` (endpoints that exist on api.10x.app) pass through in hybrid mode; `fixtureHandlers` (endpoints not yet migrated) always serve fixtures.
3. **Interactive mocks, not read-only.** Mutation handlers write into mock state so post-mutation refetches round-trip the change (the `usageBillingState` pattern from 10x-web).
4. **Fixtures derive from real shapes.** JSON is exported from 10x-web's fixtures and decoded by the same Codable models the live client uses - a drifted fixture fails the parity test loudly.
5. **Tokens only.** All styling through `Theme`; spacing snaps to the 2/4/8/12/16/24/32 grid; touch targets >= `Theme.controlHeightTouch` (44pt). Glass is floating chrome only (nav pills, circular top controls) - content stays solid; Reduce Transparency falls back to opaque `Theme.chromeBar`.
6. **Adapt shared intent natively.** Preserve product hierarchy, contracts, status meaning, and shared component semantics from `../docs/design/` while using iOS-native navigation, disclosure, touch, focus, scaling, and layout. macOS can provide product-behavior context, but its source topology and raw metrics are not iPhone requirements.

### 3.3 `ios/AGENTS.md` "Binding rules", verbatim

- Views render state and dispatch intent. Per-surface observable stores call `APIClient`; nothing else touches the network.
- Mock at the URL loading boundary. Screens and stores do not branch on mock/live mode.
- Mutation mocks update shared mock state so refetch behavior matches a server round trip.
- Selected JSON fixtures are generated from `../web/src/mocks/fixtures/`; never hand-edit exported fixture output to hide drift.
- Use `Theme` and TenXKit primitives. Preserve semantic design intent from macOS while implementing native iOS navigation and touch behavior.
- Keep the app target thin; reusable product logic belongs in TenXKit, not the launch shell.
- Treat tokens, deep links, attachments, URLs, model output, and decoded server data as untrusted.

Commands: `./scripts/test ios` / `./scripts/check ios` (= `swift package dump-package` + `xcodebuild -scheme TenXKit -destination "${IOS_DESTINATION:-platform=iOS Simulator,name=iPhone 17 Pro}" test`, `scripts/test`, `scripts/check`). "UI changes require snapshot or visual verification plus accessibility checks. API and fixture changes require affected backend/web verification. Never access signing credentials or submit a build without explicit approval."

### 3.4 Theme and design tokens

- Pipeline: `packages/design-tokens/tokens.json` -> `node packages/design-tokens/scripts/generate.mjs` (`./scripts/generate design-tokens [--check]`) -> `ios/Sources/TenXKit/Theme/Generated/DesignTokens.swift` (same Swift text is also written to the macOS path, `generate.mjs` lines 16-17, 640-647). CI job `design_tokens` and `./scripts/check design` fail on drift; `scripts/classify-paths` treats the token source and all generated outputs as one artifact that triggers every consuming project's checks.
- Generated file header: `// GENERATED FILE - DO NOT EDIT. // Source: packages/design-tokens/tokens.json // Generator: packages/design-tokens/scripts/generate.mjs`; `enum GeneratedDesignTokens { static let version = "1.2.0"; struct AdaptiveHex { light, dark: String }; struct AdaptiveOpacity; struct FixedAlpha; struct RGB; struct TypeStyle { size: CGFloat; weight: Int }; struct ShadowValue; struct CubicBezier; enum Color { static let accent = AdaptiveHex(light: "111111", dark: "F5F5F4") ... }; enum Dimension { enum Spacing, Radius, Control, Menu, Code, Ratio }; enum Typography; enum Control; enum Shadow; enum Motion }`. Data only; internal (not public).
- `Theme.swift` is the public adapter: `public enum Theme` with `Color.dynamic(light:dark:)` wrappers over the generated hex/opacity pairs (`Theme.accent`, `surface`, `surfaceElevated`, `surfaceInset`, `chromeBar`, `separator`, `hairline`, `controlHoverFill`, `controlActiveFill`, `textPrimary = Color.primary`, `textSecondary = Color.secondary`, `textTertiary`, `textOnAccent`, `success`, `error`, `warning`, `info`, `surfaceSubtle`, `strokeWeak`, ...), `spacingXXS...spacingXXL` (2/4/8/12/16/24/32), `radiusXXS/SM/MD/LG/XL`, `controlHeight/Compact/Large` (34/28/40), `controlHeightTouch: CGFloat = 44` (iOS addition), `shadowHud/Button/Chat/DevicePreview/Soft/Popover/Floating/Modal`, `controlPressedOpacity`, `controlDisabledOpacity`, `Theme.appFont(size, weight:)`. Native overlays (system colors, Dynamic Type, `chromeSelectedFill` grayscale) stay in the adapter (`packages/design-tokens/docs/token-model.md` "Platform adaptation").
- Token source categories (`tokens.json`): `colors.adaptiveHex` (accent, surface, surfaceElevated, surfaceInset, chatBackground, previewBackground, chromeBar, chromeSelectedFill, textOnAccent, success, error, warning, info, menuBackground, sidebarBackground), `colors.adaptiveOpacity` (accentSubtle, accentLight, separator, hairline, controlHoverFill, controlActiveFill, textTertiary, textOnAccentSecondary, textOnLightControl, surfaceSubtle, strokeWeak, strokeStrong), `fixedAlpha` (scrim family), `fixedRGB` (terminal), `categoryPalette`, `dimensions.spacing {xxs:2, xs:4, sm:8, md:12, lg:16, xl:24, xxl:32}`, `dimensions.radius {xxs:4, sm:6, card:8, md:10, lg:16, xl:20, composer:20, menu:12, menuItem:10, glass:16, glassSmall:10}`, `dimensions.control {workspaceChrome:46, compact:28, standard:34, large:40, auth:44}`, `typography.styles` (appText 14/400, appTextEmphasis 14/500, largeTitle 28/700, title 20/600, title2 17/600, title3 15/600, headline 14/600, body 13/400, bodyStrong 13/600, subheadline 12/500, label 12/400, labelStrong 12/600, caption 11/400, caption2 10/400, display 30/700, displayLarge 40/700, mono*), `controls {pressedOpacity 0.86, disabledOpacity 0.48}`, `shadows`, `motion.curves {enter, exit, hover, springWeb}`, `motion.durationsMs {interaction:150, pane:300}`, `web`, `portal`.

### 3.5 Primitives (`ios/Sources/TenXKit/Primitives/`)

| Name | File | Purpose / signature |
|---|---|---|
| `TenXPrimaryButtonStyle`, `TenXSecondaryButtonStyle`, `TenXDangerButtonStyle` | `TenXPrimitives.swift` | `ButtonStyle`s for the "Action button" semantic job (emphasis / neutral / destructive) |
| `TenXRule` | same | Divider; `init()` |
| `TenXSpinner` | same | `init(compact: Bool = false, tint: Color? = nil)` |
| `SkeletonBlock` | same | `init(width: CGFloat? = nil, height: CGFloat = 10, cornerRadius: CGFloat = Theme.radiusXXS)` |
| `TenXLoadingState` | same | `init(label: String = "Loading project")` |
| `TenXEmptyState` | same | Explains why empty + next safe action |
| `TenXCardView<Content>` | same | Content card, `init(padding:..., content:)` |
| `TenXListRow<Leading, Trailing>` | same | Leading/title/subtitle/trailing row; `init(title:subtitle:isLast:action:)` plus builder variants |
| `TenXSection<Content, Trailing>` | same | Grouped content under a heading; `init(eyebrow: String, spacing: CGFloat = Theme.spacingMD, content:)` |
| `TenXBadge` | same | `init(label: String, tint: Color = Theme.textSecondary, ornament: Ornament = .dot)` - status pill with non-color cue |
| `TenXErrorBanner` | same | `severity` (error/warning/info/success), `message`, optional `actionTitle` + action |
| `TenXSegmentedControl` | same | `init(segments: [Segment], selection: Binding<String>)` |
| `TenXIconButton` | `TenXIconButton.swift` | Icon-only action; requires accessibility label |
| `TenXViewHeader<Leading, Trailing>` | `TenXViewHeader.swift` | `init(title:subtitle:showsDivider:)` with leading/trailing builders |
| `PipelineStepper` | `PipelineStepper.swift` | `init(steps: [Step])`, steps expose current/completed/failed/blocked |
| `FlowLayout` | `FlowLayout.swift` | `Layout` wrapping chips; `init(spacing: CGFloat = Theme.spacingSM, alignment:)` |
| `UserAvatarView` | `UserAvatarView.swift` | `init(url: URL?, initials: String, size: CGFloat = 32)` |
| `GlassCircleButton`, `GlassPillBar`, `GlassTab`, `.tenXGlass(in:interactive:)` | `Glass/GlassChrome.swift` | Floating glass chrome (see 3.6) |
| `DecisionCard` | `Views/Workspace/Chat/DecisionCard.swift` | Approval composite |

These map 1:1 to the cross-platform catalog rows in `docs/design/component-catalog.md` (iOS column).

### 3.6 Glass chrome rules

From `ios/Sources/TenXKit/Glass/GlassChrome.swift` header comment and `ios/docs/design-system.md`:
- "Glass is floating chrome ONLY (nav pills, circular top controls); content stays solid so text never sits on glass. Under Reduce Transparency every glass surface falls back to an opaque `Theme.chromeBar` fill - same shape and shadow, no blur."
- One recipe: `struct GlassSurface<S: Shape>: ViewModifier` reads `@Environment(\.accessibilityReduceTransparency)`; if on -> `background(shape.fill(Theme.chromeBar)).overlay(shape.stroke(Theme.separator)).themeShadow(Theme.shadowFloating)`, else -> `.glassEffect(interactive ? .regular.interactive() : .regular, in: shape)`. Exposed as `public func tenXGlass(in shape: some Shape = Capsule(), interactive: Bool = true)`.
- `GlassCircleButton` (44pt hit target, `.tenXGlass(in: Circle())`, requires `accessibilityLabel`) for workspace exit/overflow/search.
- `GlassPillBar` uses `GlassEffectContainer` + `glassEffectID` morphing; two rhythms: `.iconsOnly` (app tier) and `.activeExpands` (project tier, only selected tab shows label).
- App tier uses the native iOS 26 `TabView` (system Liquid Glass tab bar); the custom pill is used only inside the full-screen workspace (`Views/RootView.swift` doc comment).
- Snapshot tests exclude glass surfaces because the material does not render byte-identically; glass is verified visually (`Tests/TenXKitTests/ScreenSnapshotTests.swift` header).
- `docs/design/foundations.md`: "Glass/translucency is reserved for floating navigation or control chrome. Content and forms require stable readable surfaces and opaque reduced-transparency fallbacks."

### 3.7 Navigation rules (`ios/docs/navigation.md`, `Views/RootView.swift`)

- "The macOS builder is a multi-pane workspace; iPhone uses a focused, progressive hierarchy. A primary tab or project context opens one task surface at a time, secondary panels become pushed destinations or sheets, and persistent desktop sidebars become explicit navigation controls."
- "Navigation state belongs to the app/surface coordinator, not leaf views. Deep links resolve through the same typed destination model. Back behavior must be predictable, preserve unsaved input, and never dismiss destructive work without confirmation."
- "prefer native iOS navigation bars, sheets, search, toolbars, and touch ergonomics. Verify compact/regular widths, keyboard presentation, VoiceOver order, safe areas, and state restoration."
- Implementation: there is **no `Route` enum and no Router/Coordinator type**; navigation state is plain SwiftUI state lifted to the tier-owning view. `RootView` holds `@State private var tab: AppTab` (`enum AppTab: Hashable { case projects, create, account }`), a `TabView(selection:)` with `Tab("Projects", systemImage:..., value:)` items, `.tint(Theme.accent)`, and `.fullScreenCover(item: $openedProject) { WorkspaceView(project:) }` for the project tier ("it's a mode, not a page"). `Views/Workspace/WorkspaceView.swift` is a second `TabView` with string tab ids `"preview" | "chat" | "release" | "more"`, owns the project's `ChatStore`/`ReleaseStore`/`BackendStore`, and overlays a `WorkspaceTopBar` (`GlassEffectContainer` with two `GlassCircleButton`s) using `.contentMargins(.top, 56, for: .scrollContent)`. Pushed destinations use `NavigationStack(path: $path)` with `[String]` paths and `.navigationDestination(for: String.self)` (`MoreView.swift` ids `backend | users | env | paywalls | market | social | dashboard`; `AccountView.swift` ids `plan | billing | spending | connections | asc | appearance | gallery`); drill-ins hide native chrome with `.toolbar(.hidden, for: .tabBar)` / `.toolbar(.hidden, for: .navigationBar)` and use the `.surfaceHeader("Title")` modifier (`Views/Workspace/SurfaceHeader.swift`, back chevron via `@Environment(\.dismiss)`). No `.sheet` usage exists in `Sources/`; the only modal is the workspace `fullScreenCover`. DEBUG-only deep links are `-KEY value` launch args read from `UserDefaults`: `OPEN_APP_TAB`, `OPEN_PROJECT <id>`, `OPEN_TAB`, `OPEN_MORE_SURFACE <id>`, `OPEN_ACCOUNT_ROUTE plan|billing` (e.g. `simctl launch <udid> app.tenx.ios -OPEN_PROJECT prj_h4bt29`). No URL scheme or universal-link handling exists.

### 3.8 Mock-first pattern

- `Mocks/MockTransport.swift`: `MockRequest {method, url, pathParams, body; jsonBody<T>()}`, `MockResponse {status, body; .json(_:status:), .encodable(_:), .fixture(name), .fixture(name, envelope:)}`, `MockRoute(method, pattern, handler)` with `:param` segment capture, and `public final class MockTransport: URLProtocol` with `static var routes`, `static var latency: Duration = .milliseconds(180)`, `register(in: URLSessionConfiguration)`; `canInit` returns false for unmatched routes so they hit the real network ("that is hybrid mode in one line").
- `Mocks/MockHandlers.swift`: `public enum MockHandlers` with mutable static state seeded from fixtures (`projects`, `envVars`, `releaseOverrides`, `chats`, `messageCounter`), `resetState()`, route groups `liveRoutes` (exist on real API; omitted in hybrid mode) and per-surface fixture groups (`backendRoutes`, `paywallRoutes`, `releaseRoutes`, `chatRoutes`, `projectRoutes`). Mutations write into state so refetch round-trips. Mode selection:

```swift
public enum Mode: String { case enabled, hybrid, disabled }
public static func modeFromEnvironment() -> Mode {
    let value = UserDefaults.standard.string(forKey: "MOCKING")
        ?? ProcessInfo.processInfo.environment["MOCKING"]
    if let value, let mode = Mode(rawValue: value) { return mode }
    #if DEBUG
    return .enabled
    #else
    return .disabled
    #endif
}
public static func install(mode: Mode = modeFromEnvironment()) {
    let hybrid = mode == .hybrid
    switch mode {
    case .enabled, .hybrid:
        MockTransport.routes = (hybrid ? [] : liveRoutes) + backendRoutes + paywallRoutes + releaseRoutes + chatRoutes + projectRoutes
    case .disabled:
        MockTransport.routes = []
    }
}
```

  `install()` is called once from `App/TenXApp/TenXAppApp.swift` `init()`. Toggle with the `-MOCKING hybrid` launch argument or the `MOCKING` env var; Release builds default to `disabled`. `Tests/TenXKitTests/MockTransportTests.swift` (`@Suite(.serialized)`) calls `MockHandlers.install(mode: .enabled)`, `resetState()`, and sets `MockTransport.latency = .zero`, then exercises the real `URLSession` + `APIClient` (fixture served, 404 branch, PUT round-trip, hybrid pass-through via `MockTransport.route(for:) == nil`).
- `Mocks/Fixtures.swift`: `Bundle.module` loader (`url`, `data`, `decode<T>`) and an explicit `allNames` list so the parity test fails when an export adds an unbundled file.
- `scripts/export-fixtures.mjs`: `node --experimental-strip-types scripts/export-fixtures.mjs Sources/TenXKit/Resources/Fixtures` imports `web/src/mocks/fixtures/{workspace,billing}.ts` and writes each exported const to `<name>.json` (root wrapper: `./scripts/generate ios-fixtures`).

### 3.9 Store / APIClient pattern

- `API/APIClient.swift`: `public final class APIClient: Sendable` with `baseURL` (default `https://api.10x.app`), `authToken: (@Sendable () -> String?)?`, `static let shared`, an `ephemeral` `URLSession` whose configuration always has `MockTransport.register(in:)`, `struct HTTPError: Error {status, body}`, `get<T: Decodable>(_ path, as:)` and `send<Body: Encodable, T: Decodable>(_ method, _ path, body:, as:)` (sets JSON content type, Bearer header, `.iso8601` dates, throws on non-2xx, decodes with `JSONDecoder.tenX`).
- `API/Stores.swift`: `public enum LoadState<Value>: idle | loading | loaded(Value) | failed(String)` with `value`/`isLoading`; one `@Observable @MainActor public final class XStore` per surface (`ProjectsStore`, `BillingStore`, `ChatStore`, ...) with `public private(set) var state: LoadState<...>`, `init(client: APIClient = .shared)`, `func load() async`, mutation funcs that call `send(...)` then `await load()`; user-facing failure strings like `"Couldn't load projects."`. "Stores are deliberately thin: load / mutate / expose state. No view logic, no formatting."
- `API/Models.swift`: `public struct Project: Codable, Identifiable, Hashable, Sendable` with explicit `CodingKeys` mapping snake_case wire keys (`created_at`, `thumbnail_url`); shapes mirror the OpenAPI/web schema.
- Views receive stores by init (`ProjectsView(store: projectsStore)`, declared `@Bindable var store`); the tier-owning view creates them with `@State` (`RootView` creates `ProjectsStore`; `WorkspaceView.init` creates the three project stores via `State(initialValue:)`; `AccountView` creates `BillingStore`). Views `switch store.state { case .idle, .loading: skeleton; case .failed(let msg): TenXErrorBanner(... "Retry") { Task { await store.load() } }; case .loaded(let v): ... }` and trigger loads with `.task { await store.load() }` plus `.refreshable`. DI is constructor injection with `client: APIClient = .shared` defaults; there is no `AppContainer`, `Dependencies` struct, or custom `EnvironmentKey`. `JSONDecoder.tenX` (`Models.swift`) is the one shared decoder with an ISO-8601 date strategy; models use explicit `CodingKeys` rather than `keyDecodingStrategy`.
- Theme mode: `public enum ThemeMode: String, CaseIterable, Identifiable, Codable { case system, light, dark }` with `static let storageKey = "appThemeMode"` in `Theme.swift`; the app root binds it with `@AppStorage(ThemeMode.storageKey)` and applies `.preferredColorScheme(themeMode.preferredColorScheme)`.
- `Gallery/GalleryView.swift` is a DEBUG-only catalog of every primitive, both glass pills over scrolling content, glass fallbacks and Dynamic Type; reachable from `AccountView` under `#if DEBUG` as the "TenXKit Gallery" row. Not shipped in release UI.
- Auth: **not implemented** in the mono iOS app. `authToken` is an optional closure on `APIClient` that `.shared` never supplies; there is no Keychain, Supabase SDK, login screen or session storage in `ios/` (`AccountView.swift`: "No signed-in identity in the mock"). The README's hybrid-mode "real JWT" is aspirational. There is also no PostHog/Sentry ("`ios/` has no telemetry of any kind", `docs/observability.md`).

### 3.10 Testing (`ios/docs/testing.md`, `Tests/TenXKitTests/`)

- `FixtureParityTests.swift` (Swift Testing `@Suite`/`@Test`/`#expect`): every fixture in `Fixtures.allNames` is bundled and decodes through the live Codable models.
- `MockTransportTests.swift`: route matching / interception.
- `ScreenSnapshotTests.swift` (XCTest + `SnapshotTesting`): `withSnapshotTesting(record: SNAPSHOT_RECORD == "1" ? .all : .missing)`, helper `assertBoard(view, named:)` rendering a `UIHostingController` at width 390, `.image(size: 390x720)`, once per `("light", .light)` and `("dark", .dark)` with `overrideUserInterfaceStyle`; snapshots under `__Snapshots__/ScreenSnapshotTests/`. Re-record with `SNAPSHOT_RECORD=1 xcodebuild -scheme TenXKit ... test`.
- Policy: API changes need decoding/transport regression tests; fixture changes need regeneration + parity tests; UI changes need snapshots or captured visual evidence and Dynamic Type/VoiceOver/contrast/reduced-motion/safe-area/keyboard/44pt checks.
- Deployment: `ios/docs/deployment.md` is `status: draft` - no release pipeline documented; CI runs unsigned simulator tests only; iOS CI "selects an available simulator dynamically" (`docs/testing-strategy.md`).

---

## 4. Design system (`docs/design-system.md`, `docs/design/`)

### 4.1 Authority and core decisions (`docs/design-system.md`)

Authority table: token values -> `packages/design-tokens/tokens.json` + `schema.json`; product components -> `docs/design/component-model.md` + `component-catalog.md` with platform-native primitives; portal React primitives -> `packages/portal-ui`; product behavior and language -> `docs/product.md`, `platform-parity.md`, `content-and-voice.md`. Core decisions: semantic names generated from tokens, no independent palettes; React/macOS/iOS components stay native and share contracts/terminology/fixtures, not source; "A new primitive needs a distinct semantic job and at least two credible usages or an approved foundational role"; exceptions are explicit, local, owned, removable. Authority order when sources disagree (`docs/design/README.md`): 1) accepted requirements/safety/ADRs, 2) design policy, 3) platform `AGENTS.md`, 4) implemented primitives/tests, 5) dated audits/screenshots.

### 4.2 Foundations (`docs/design/foundations.md`)

- Character: "capable, calm, direct, and trustworthy ... clarity and recoverability outrank visual novelty"; "one clear primary action, stable layout, quiet neutral surfaces, purposeful status color, and motion that explains change."
- Token naming: reference values (internal) -> semantic tokens (`surface.raised`, `text.secondary`, `status.error`, `space.md`, `motion.enter`) -> component tokens only when unavoidable; "Names describe role, not appearance: use `text.secondary`, not `gray-500`"; light/dark is one token with modes.
- Color: surface hierarchy base / inset-sunken / content / raised-floating / chrome; text primary/secondary/tertiary/inverse/status; "Status color always has a label, icon, shape, or position cue"; user content palettes are content, not chrome.
- Typography: three proportional recipes - title (20/600), app emphasis (14/500), app text (14/400); tabular figures for numbers; monospace only for code/identifiers/logs; must scale with platform accessibility.
- Spacing: 2/4/8/12/16/24/32; controls compact/regular/large.
- Shape/elevation: radius by role (control, card, menu/dialog, sheet, pill); prefer contrast and borders before shadows; glass only for floating chrome.
- Icons: known action/category, accessible names, platform-appropriate licensed sets.
- Motion: named timing/easing tokens; never required to understand state; reduced motion removes nonessential movement.
- Exceptions require `theme-exempt: <reason>`.

### 4.3 Component model and catalog (`component-model.md`, `component-catalog.md`)

- Layers: Foundations -> Primitives (Button, Card, Field, Badge, EmptyState, Dialog) -> Composites (decision card, usage meter, pipeline stepper) -> Feature views -> Shells. Dependency flows downward; primitives never import features.
- Required contract for every primitive/composite: semantic name/job, anatomy, inputs named by meaning (`variant`, `tone`, `size`, `disabled`, `isSelected`), interaction states, loading/empty/error/disabled/destructive/success/permission-denied/offline/long-content behavior, keyboard/touch/focus/accessible name, responsive/text-scaling/reduced-motion/transparency behavior, platform mappings, tests/specimens/owner/deprecation.
- Primitive-first rule; no `PrimaryButton`/`BlueButton` copies; no god-components.
- Catalog rows (semantic job -> web / macOS / iOS): Product text (`Text` / `Text`+`Font` / same); Action button (`Button` / `TenXPrimaryButtonStyle`,`TenXSecondaryButtonStyle`,`TenXDangerButtonStyle` / same); Icon-only action (`IconButton` / `TenXIconButton`); Content card (`Card` / `TenXCardView`); List row (`ListRow` / `TenXListRow`); Section (`Section` / `TenXSection`); Badge/status pill (`Badge`/`Pill` / `TenXBadge`); Inline feedback (`ErrorBanner` / `TenXErrorBanner`); View header (`PageHeader`/`ViewHeader` / `TenXViewHeader`); Divider (`Rule` / `TenXRule`); Progress/loading (`Spinner`,`LoadingState`,`Skeleton*` / `TenXSpinner`,`TenXLoadingState`,`SkeletonBlock`); Empty state (`EmptyState` / `TenXEmptyState`); Text field (`Input`/`Field` / native field - iOS composite gap); Segmented choice (`SegmentedTabs` / `TenXSegmentedControl`); Modal task (`Dialog`/`Sheet` / native sheet); Anchored disclosure (`Popover`,`Menu`,`Tooltip`,`Collapsible` / native); Decision/approval (`DecisionCard`); Pipeline progress (`PipelineStepper`).

### 4.4 Content and voice (`content-and-voice.md`)

- Voice: "calm precision ... Avoid hype, blame, false certainty, and celebratory language before an external system confirms success."
- Terminology from `docs/product.md`/`docs/glossary.md` (`project`, `generated app`, `app service`, `backend`, `runtime`, `fleet`, `publishing`); add a glossary term before introducing new names.
- Labels: sentence case everywhere; buttons use the immediate verb (`Create project`, `Retry build`), avoid vague `Continue`/`Done`; destructive actions name the object (`Delete project`); no periods on short labels; no directional language.
- Status: say what is known now (`Uploading build`, `Waiting for Apple`); distinguish queued/working/blocked/retrying/complete/deployed/submitted/approved/published; never convert provider acceptance into end-to-end success.
- Errors answer: what failed (user terms), impact, next step, diagnostic detail available without secrets. Example: "We couldn't upload the build. Your project is unchanged. Check the connection and try again." Machine codes go to detail views/logs.
- Confirm only consequential/costly/irreversible actions; empty states explain why and next step, no shaming; success names the result, "Avoid confetti or praise for routine administrative actions."
- Plain language, expandable acronyms, meaningful link text, no meaning via punctuation/emoji/color/caps alone; allow text expansion.

### 4.5 Accessibility, parity, visual QA, change process

- `accessibility.md`: WCAG 2.2 AA on web, Apple conventions on native; native semantic controls first; every interactive element has an accessible name; focus moves into and is restored from modals; iOS preserves VoiceOver order/switch control; contrast AA; never color-only; support text scaling without clipping; 44pt targets; respect reduced motion/transparency; errors identify field and recovery.
- `platform-parity.md`: must remain equivalent - vocabulary, object identity, business rules, permissions, lifecycle states, recovery paths, hierarchy, component semantic job, analytics meaning, token names; should adapt natively - input, windowing, safe areas, typography rendering, icons, materials, animation. Capability classes: Shared / Adapted / Platform-exclusive / Planned gap / Not applicable; gaps marked `PARITY-GAP(owner, condition)`. Web is the UI reference for macOS 1:1 (ADR 0003); iOS adapts natively.
- `visual-qa.md`: evidence table by change type; appearance matrix (light/dark, contrast, reduced motion/transparency, long content, viewports/size classes, Dynamic Type, focus states); 7-step procedure; "Do not update snapshots solely to make tests pass"; baselines with owner/reason/removal condition.
- `change-process.md`: classify (foundation/token, primitive/composite, feature usage, platform adaptation, marketing/generated-app); proposal requirements; token workflow (edit `packages/design-tokens/`, validate, run pinned generators, review diffs, run drift + consumers + a11y + visual matrix; breaking changes add/migrate/deprecate/remove); component workflow (contract in model/catalog -> mapping per platform -> implement natively -> migrate consumers -> tests/specimens -> track debt); deprecation records replacement/window/owner.

### 4.6 Onboarding, paywalls, growth surfaces

- **Paywalls** (`docs/features/paywalls-monetization/`): in 10x this feature is a *builder* capability - users configure hosted paywall versions for their generated apps (`backend/api/routers/paywalls.py`, `paywall_templates.py`, `backend/paywall-templates/`, `apps.10x.app/p/[id]` hosted HTML, Superwall linking per `web/docs/paywalls-superwall-connect-2026-07-19.md` and `paywalls-management-simplification-2026-07-24.md`). Journey rules: deliberate empty state when no paywall exists; server validates ownership/asset/template before persisting; reload preserves version history and preview; "Publishing records an event and server state; do not label it successful merely because a modal closed"; 401/403 -> re-auth, 409 -> conflict recovery, 400 -> invalid content, 5xx -> keep draft for retry. Account billing is separate under `/api/v1/billing/*` and "External payment completion must return through the billing facade and show refreshed server state, not optimistic local entitlement."
- **Account paywall / pricing** components on web: `web/src/components/paywall.tsx`, `plan-paywall.tsx`, `pricing-dialog.tsx` (each with `*.test.tsx`); out-of-credits paywall opens without experiment-specific copy (`experiments-onboarding/user-journey.md`).
- **Onboarding + experiments** (`docs/features/experiments-onboarding/`): server-owned experiment assignment (`backend/api/routers/experiments.py`), deterministic bucketing, one bounded exposure per decision point, conversions never fail the primary action; post-signup onboarding (`web/src/components/post-signup-onboarding.tsx`) writes acquisition source early via `POST /api/v1/builder/onboarding` (`completed: false` progress writes cannot set `completed_at`; final choice writes `onboarding_plan_id`, migration `201_user_onboarding_plan.sql` / `108_user_onboarding.sql`, `205_user_onboarding_plan.sql`); "Native clients fail closed before external checkout unless that response echoes the chosen plan" (`docs/api-and-contracts.md`). Verification list: new user, returning user, ineligible, loading, assignment error, control, treatment, concluded winner, persistence failure, checkout return, staff override, unauthorized admin, reload recovery.
- **Growth** (`docs/features/growth-socials/`): project Socials surface generating launch-kit copy/images/posts (`web/src/views/workspace/growth-social-view.tsx`, `backend/api/routers/project_content_sections.py`), plus dated web design records (`web/docs/socials-*.md`).
- **"parity-paywalls" / "release-growth"** are branch names (`git branch -a`: `mac-parity/paywalls-20260826`, `mac-parity/paywalls-standalone-20260826`, `mac-parity/release-growth-mirror-20260826`, `mac-parity/release-growth-stack-mirror-20260826`) for macOS parity work mirroring the web Paywalls and Release/Growth surfaces under ADR 0003; no repository document with those exact names exists on `main`.
- Analytics for these surfaces use registered PostHog names (e.g. `experiment exposure`, `experiment conversion`, `stripe checkout created`, `subscription activated`, `notification_prompt_shown`) with server-side property allowlists (`backend/api/services/analytics.py`).

### 4.7 ADR index (`docs/adr/README.md`)

0001 monorepo; 0002 design-system boundaries (neutral tokens, native UI); 0003 web as UI reference for macOS; 0004-0005 preview leases/readiness; 0006 server-owned model routing; 0007 tester-only retention exceptions; 0008 GitHub-backed fleet release; 0009 capability-scoped Swift verification; 0010 browser presence warmth; 0011 atomic first-turn; 0012 gateway-first planner; 0013 product-owned project start; 0014 clone parity; 0015 Vercel Related Projects previews; 0016 canonical eval boundary; 0017 canonical apex web surface; 0018 channel-agnostic notifications; 0019 server-owned backend bundle setup; 0020 versioned context snapshots; 0021 fleet admission; 0022 granular admin metrics; 0023 founding-prompt corpus; 0024 checked OpenAPI artifacts; 0025 AsyncAPI realtime contracts; 0000 template.

---

## 5. Web (`web/`, `packages/portal-ui`)

### 5.1 Stack (`web/package.json`)

`next 16.3.0`, `react 19.2.4`, `@tanstack/react-query ^5.101.2`, `zustand ^5.0.14`, `openapi-fetch ^0.17.0`, `openapi-typescript 7.13.0` (exact pin, dev), `msw ^2.14.6` (dev, `"msw": {"workerDirectory": ["public"]}`), `@supabase/supabase-js ^2.110.1`, `@sentry/nextjs ^10.67.0`, `posthog-js ^1.404.1`, `@vercel/analytics`, `tailwindcss ^4` + `@tailwindcss/postcss`, Radix primitives (`react-dialog`, `react-popover`, `react-dropdown-menu`, `react-tooltip`, `react-context-menu`), `lucide-react`, `clsx`, `tailwind-merge`, `vitest ^4.1.10`, `@testing-library/react`, `jsdom`, `eslint ^9` + `eslint-config-next`, `@stripe/react-stripe-js`. Scripts: `dev`, `dev:demo` (`NEXT_PUBLIC_API_MOCKING=enabled`), `dev:new-user`, `build` (`next build --webpack`), `typecheck`, `lint`, `lint:design` (baseline-aware, `scripts/lint-design.mjs`), `test` (`vitest run`), `gen:api`.

### 5.2 Binding rules (`web/README.md` "Architecture rules (binding)", `web/AGENTS.md`)

1. **SPA discipline** - root layout handles tokens/providers; everything below is `"use client"`; no RSC data fetching, server actions, or Next caching.
2. **Screens never fetch** - components consume hooks from `src/lib/api/hooks`; hooks call the generated typed client.
3. **Mock at the boundary** - screens must not know whether MSW or the real API answered; wiring live = deleting the handler in `src/mocks/handlers.ts`; fixtures derive from real shapes.
4. **Server state vs client state** - TanStack Query owns server data, Zustand only UI state; nothing stored twice.
5. **Tokens only** - `globals.css` token utilities; spacing snaps to the token scale; arbitrary values need `{/* theme-exempt: why */}`; chrome lives in `src/components/primitives` ("the web port of TenXPrimitives").

File organization (`web/AGENTS.md`): `src/app/` thin routes/layouts/loading/error; reusable screens in `src/views/<area>/`; primitives in `src/components/primitives/`; cross-feature components `src/components/<domain>/`; `src/lib/api/` transport, query keys, hooks; `src/store/` browser-only global state; `src/mocks/` MSW handlers + fixtures; kebab-case files, PascalCase components, `use*` hooks, `*.test.ts(x)` beside behavior. Next.js 16 rule: read `node_modules/next/dist/docs/` before writing framework code.

### 5.3 Key code patterns

- API client (`src/lib/api/client.ts`): `createClient<paths>({ baseUrl, fetch: fetchWithTimeout })` from `openapi-fetch` typed by generated `paths`; a `Middleware.onRequest` sets protocol headers (`X-10x-Api-Version: v1`, `X-10x-Credit-Units: normalized`, `X-10x-Platform: web`, `Accept: application/json, application/x-ndjson`) and `Authorization: Bearer <supabase access token>` from `getAccessToken()`; `REQUEST_TIMEOUT_MS = 12_000` with longer per-path overrides for Stripe operations.
- Hooks (`src/lib/api/hooks.ts`): `useQuery`/`useMutation`/`queryOptions` with centralized keys in `src/lib/api/query-keys.ts` (`projectQueryKeys`, `workspaceQueryKeys`, `workspaceQueryPolicy`); analytics emitted from hooks using `ANALYTICS_EVENTS` constants.
- Zustand store (`src/store/auth-modal.ts`): `create<State>((set) => ({ isOpen, prompt, intent, open(), close() }))`, documented as "UI state only (never server data)".
- MSW (`src/mocks/handlers.ts`, `browser.ts`, `fixtures/{billing,workspace}.ts`): `http.get(\`${API}/api/v1/...\`, () => HttpResponse.json(fixture))`, mutable in-memory overrides for mutations, `delay()`; `NEXT_PUBLIC_API_MOCKING=enabled|hybrid|disabled`, `NEXT_PUBLIC_MOCK_NEW_USER`. Web fixtures are the canonical source that iOS exports.
- Auth (`src/lib/auth.tsx`, `src/lib/supabase.ts`): Supabase OAuth (Google/Apple) session context, PostHog identify/reset at the auth boundary, query-client rotation on account switch.
- Analytics (`src/lib/analytics.ts`): privacy-bounded PostHog; enabled only when `NEXT_PUBLIC_POSTHOG_KEY` and `NEXT_PUBLIC_POSTHOG_ENABLED` truthy; base props `{surface: "web_app", platform: "web", env}`; identify with Supabase UUID only; honors GPC/DNT; proxied via `/x1` rewrites in `next.config.ts`.
- Sentry: `sentry.server.config.ts`, `sentry.edge.config.ts`, `src/instrumentation-client.ts` all `Sentry.init({ dsn, enabled: Boolean(dsn), tracesSampleRate: 1, beforeSend: sanitizeSentryEvent })`; `next.config.ts` wraps with `withSentryConfig`; env `NEXT_PUBLIC_SENTRY_DSN`, build-only `SENTRY_AUTH_TOKEN`.
- `next.config.ts`: security headers (nosniff, referrer policy, `X-Frame-Options: SAMEORIGIN`, CSP `frame-ancestors 'self'`), `turbopack.root: __dirname`, PostHog and notification proxy rewrites, API origin from `@10x/vercel-api-origin`.
- Tests: `vitest.config.ts` (`include: src/**/*.test.ts(x)`, `environment: node`, alias `@` -> `src`), `vitest.setup.ts` installs in-memory `localStorage`. `./scripts/check web` = typecheck, lint, lint:design, vitest, `next build`.
- Design conventions (`web/docs/design-conventions.md`): Tailwind default palettes wiped; surface tiers `bg-base`, `bg-sidebar`, `bg-sunken`, `bg-surface`, `bg-raised`, `bg-surface-subtle`, `bg-control-selected`, `bg-accent`; text `text-primary/secondary/tertiary`; status `success/error/warning/info`; lines `border-separator/hairline/stroke-strong`; type `type-title` (20/600), `type-app-emphasis` (14/500), `type-app` (14/400), `type-mono`; raw `text-<size>` and hex classes lint-gated; reference gallery at `/admin/design`.

### 5.4 `packages/portal-ui` and `packages/`

- `@10x/portal-ui` (`packages/portal-ui/package.json`): private, ESM, `main: ./src/index.ts`, peer `react ^18.3.1`, deps only `clsx` + `tailwind-merge`, `build` via `tsc -p tsconfig.build.json`, `test` = build + `node --test tests/*.test.mjs`. Exports `cn`, `Button`, `Card`, `EmptyState`, `Field`, `Input`, `Textarea`, `ThemeProvider`, `createThemeController`, `useTheme`. Ships no CSS; consumes the portal HSL token vocabulary generated from `tokens.json`. Consumers: `admin/` and `creator/` (Vite/React 18) only; **not** consumed by `web/` (Next/React 19) - "This exception does not make the Next.js web product a consumer automatically" (`docs/design-system.md`).
- `packages/AGENTS.md`: add a package only with two current consumers; define ownership/consumers/API/compat/tests/versioning first; no `utils`/`common` grab-bags; `design-tokens/` holds only token source/schema/generators.
- Root `package.json`: `packageManager npm@11.16.0`, workspaces `admin`, `creator`, `packages/vercel-api-origin`, `packages/portal-ui`; `web/` keeps its own lockfile (`docs/development.md` "Dependency policy"). `.nvmrc` = `22`.

---

## 6. Ops

### 6.1 Scripts (`scripts/AGENTS.md`, individual scripts)

Rules: resolve repo root from script location; `set -euo pipefail`; quote paths; never log env values; default commands non-destructive and offline from production; mutating commands need explicit verb, dry-run, approval; keep `scripts/docs/README.md`, root `README.md`, `AGENTS.md`, `docs/development.md` in sync; test with `bash -n scripts/*`.

- `scripts/bootstrap [--check]`: requires `git node npm python3` (+ `swift xcodebuild` on Darwin); `--check` exits after presence check; install mode runs `npm ci` at root (portal workspace), then `npm ci` in `web`, `website`, `backend/managed-better-auth`; creates `backend/.venv` with `uv venv --seed --python 3.12.7` or `python3 -m venv` (refuses non-3.12), `pip install -r backend/requirements-dev.txt`; `swift package resolve` for `macos` and `ios`; prints "Copy project .env.example files to ignored local .env files as needed." Never creates env files or contacts production.
- `scripts/dev <backend|web|admin|creator|website|macos|ios|all>`: backend -> `backend/scripts/dev.sh`; web -> `npm --prefix web run dev`; ios -> `open ios/App/TenXApp.xcodeproj`; `all` runs backend + web with a kill trap.
- `scripts/test <project>`: backend pytest with `PYTHONPATH`; web `npm test`; ios `xcodebuild -scheme TenXKit -destination "${IOS_DESTINATION:-platform=iOS Simulator,name=iPhone 17 Pro}" test`; macos `swift test`.
- `scripts/check <project|design|contracts|docs|packages|all>`: backend = compileall + catalog checks + tests; web = typecheck, lint, lint:design, test, build; admin/creator = token-boundary + color-baseline (`scripts/baselines/portal-color-usage.env`) + typecheck/lint/test/build; ios = `swift package dump-package` + tests; docs = `docs-check` + `governance-check`; design = token package tests + `generate design-tokens --check`; contracts = docs-check + every `generate <x> --check` + `openapi-compat origin/main` + contract script tests.
- `scripts/generate <ios-fixtures|macos-config|runtime-contract|design-tokens|analytics-events|admin-metrics|api-portal|openapi|asyncapi|openapi-handwritten|realtime-protocol|web-api> [--check]`: thin dispatcher to each generator.
- `scripts/affected [base-ref]`: `git diff --name-only base...HEAD | scripts/classify-paths`, then runs the relevant `check` targets. `scripts/classify-paths` is the single path-to-check map shared with CI (generated outputs are classified together with their sources).
- `scripts/doctor`: prints tool versions, warns if Node != 22 or Python != 3.12, lists optional tools (`uv docker flyctl vercel corepack`), runs `docs-check`.
- `scripts/docs-check`, `docs-impact-check`, `docs-validator.mjs`, `governance-check`, `openapi-compat`, `merge-pr`, `evals`, `tenx-stats`, `dependency-audit`, `tests/` (shell tests with fake `gh`).
- `.claude/launch.json` defines local launch configs (`web-3100`, `web-demo-3101`, `web-new-user-3200`, `admin`); `.claude/skills/tenx-admin-stats/SKILL.md` is a project skill.
- `.editorconfig`: utf-8, LF, final newline, trim whitespace, 2-space indent default, 4 for `*.py` and `*.swift`, tabs for Makefile, no trim for `*.md`.
- `.gitignore`: `.env`, `.env.*` except `!.env.example` / `!.env.*.example`, `*.key *.pem *.p8 *.p12 *.mobileprovision *.provisionprofile`, `.fleet-secrets/`, `node_modules` (no trailing slash so symlinks are caught), `.next/`, `dist/`, `*.tsbuildinfo`, `.venv/`, `__pycache__/`, `.build/`, `.swiftpm/`, `DerivedData/`, `xcuserdata/`, `.vercel/`, `build/`, `output/`.

### 6.2 PostHog conventions

- Event names are registered in `contracts/analytics-events/events.json` (`{name, owner_surface: macos|web|website|server, status: active|dead-name, notes}`) and generated into `web/src/lib/generated/analytics-events.ts` (`ANALYTICS_EVENTS` const map + union type) and `backend/api/generated/analytics_events.py` (`ACTIVE_EVENT_NAMES`/`DEAD_EVENT_NAMES`); "Adding an emitter with a new event name without registering it here ... is a contract violation" (`contracts/analytics-events/README.md`). Names are lowercase; both space-separated (`app opened`, `screen viewed`, `message sent`) and snake_case (`session_started`, `tab_viewed`, `feedback_submitted`) forms exist (macOS-originated names use spaces).
- Server: per-event property allowlists in `backend/api/services/analytics.py`; disabled unless `POSTHOG_ENABLED`; env `POSTHOG_PROJECT_KEY`, `POSTHOG_HOST=https://us.i.posthog.com`, `POSTHOG_PERSONAL_API_KEY`, `POSTHOG_PROJECT_ID`.
- Web: `NEXT_PUBLIC_POSTHOG_KEY/HOST/PROXY_PATH/ENABLED`; distinct id = Supabase user UUID; never email/prompt/content; GPC/DNT suppress init; `surface` property distinguishes `web_app` vs `marketing_site` (`docs/security-and-privacy.md` "Credential rules", `web/src/lib/analytics.ts`).
- Error tracking is PostHog on backend and web (`docs/observability.md`); Sentry is web-only and privacy-sanitized.
- iOS is currently uninstrumented ("Known gaps: the iOS client is uninstrumented", `docs/data-and-analytics.md`).

### 6.3 Secrets rules

`SECURITY.md`, `docs/security-and-privacy.md` "Credential rules", `AGENTS.md` "Safety", `docs/development.md` "Environment files":
- Never commit secrets, keys, prod/customer data, `.env` files, provider exports; `.env.example` holds names + safe descriptions only; `scripts/docs-check` fails if `.env`, `.env.local`, `.env.production`, `tsconfig.tsbuildinfo` are tracked.
- Local files: `backend/.env`, `<frontend>/.env.local`, mode `0600`; never copy prod values casually; do not persist `VERCEL_OIDC_TOKEN`.
- Server secrets live in Render (`sync: false` env vars), Vercel project envs, Fly secrets, GitHub Actions environments (all empty at last audit); browser/native clients get only public keys (`NEXT_PUBLIC_*`, anon key) or short-lived grants; "Separate public runtime keys from management/admin credentials"; rotate exposed credentials immediately.
- Never log env values (`scripts/AGENTS.md`); redact prompts/credentials from logs (`backend/docs/security.md`); documentation names configuration keys but never values.

---

## 7. How a new app (Readsync) should be laid out to match 10x

### 7.1 Recommended repository layout

```
readsync/
  AGENTS.md                 # root instructions (mission, domains, sources of truth, standard commands,
                            #   required workflow, architecture rules, safety, testing, docs, checklist)
  CLAUDE.md                 # exactly "@AGENTS.md"
  CONTRIBUTING.md, SECURITY.md, README.md
  .editorconfig, .gitignore, .nvmrc (22), .python-version (3.12.7)
  package.json              # private workspace root: workspaces ["packages/*"]; scripts map to ./scripts/*
  .github/
    workflows/ci.yml        # changes -> classify-paths -> docs, docs_impact, design_tokens, openapi, backend, web, ios
    pull_request_template.md
    CODEOWNERS
  docs/
    README.md, agent-workflow.md, architecture.md, product.md, business.md, glossary.md,
    design-system.md, api-and-contracts.md, data-and-analytics.md, security-and-privacy.md,
    development.md, testing-strategy.md, deployment-and-releases.md, domains-and-environments.md,
    observability.md, ownership.md
    design/ (README, foundations, component-model, component-catalog, accessibility,
             platform-parity, content-and-voice, visual-qa, change-process)
    features/ (README.md, registry.yml, _template/, <feature>/{README,user-journey,
              system-and-code-map,testing-and-e2e,operations-and-release}.md)
    adr/ (README.md, 0000-template.md, 0001-monorepo.md, 0002-design-system-boundaries.md, ...)
    runbooks/, proposals/, audits/
  backend/
    AGENTS.md, CLAUDE.md, README.md, .env.example, requirements.txt, requirements-dev.txt,
    runtime.txt, vercel.json (or render.yaml), app.py (from api.main import app)
    api/ {main.py, config.py, dependencies.py, versioning.py, http.py,
          versions/v1/__init__.py, routers/<domain>.py, schemas/<domain>.py,
          services/<domain>.py, services/<provider>.py, generated/}
    shared/ {openapi_summaries.py, logging_privacy.py}
    supabase/ {config.toml, migrations/NNN_snake.sql}
    scripts/ {dev.sh, export_openapi.py, openapi_compat.py, run_<job>_worker.py}
    tests/ {conftest.py, test_<x>_router.py, test_<x>_service.py, test_openapi_export.py}
    docs/ {README, architecture, local-development, testing, deployment, security}
  contracts/
    AGENTS.md, CLAUDE.md, README.md, docs/README.md
    openapi/ {README.md, product-api.json, scripts/}
    analytics-events/ {README.md, events.json, scripts/generate.mjs, tests}
    fixtures/                 # only if a second platform decodes them
  packages/
    AGENTS.md, CLAUDE.md, README.md, docs/README.md
    design-tokens/ {package.json, tokens.json, schema.json, scripts/generate.mjs, tests/, docs/token-model.md}
    vercel-api-origin/        # only if web + API both deploy to Vercel with Related Projects
  ios/
    AGENTS.md, CLAUDE.md, README.md, Package.swift, Package.resolved
    App/ReadsyncApp.xcodeproj, App/ReadsyncApp/ReadsyncAppApp.swift
    Sources/ReadsyncKit/ {API/{APIClient,Models,Stores}.swift, Theme/{Theme.swift,Generated/DesignTokens.swift},
                          Primitives/, Glass/GlassChrome.swift, Mocks/{MockTransport,MockHandlers,Fixtures}.swift,
                          Resources/Fixtures/*.json, Gallery/, Views/}
    Tests/ReadsyncKitTests/ {FixtureParityTests, MockTransportTests, ScreenSnapshotTests, __Snapshots__/}
    scripts/export-fixtures.mjs
    docs/ {README, architecture, local-development, testing, design-system, navigation, deployment}
  web/
    AGENTS.md, CLAUDE.md, README.md, .env.example, package.json (own lockfile), next.config.ts, vercel.json,
    vitest.config.ts, vitest.setup.ts, eslint.config.mjs, postcss.config.mjs,
    sentry.{server,edge}.config.ts, src/instrumentation*.ts
    src/ {app/, views/<area>/, components/primitives/, components/<domain>/, lib/api/{client.ts,hooks.ts,
          query-keys.ts,schema.d.ts,types.ts}, lib/analytics.ts, lib/supabase.ts, lib/auth.tsx,
          store/, mocks/{handlers.ts,browser.ts,fixtures/}, generated/design-tokens.{css,ts}}
    docs/ {README, architecture, local-development, testing, deployment, design-system, design-conventions}
  scripts/
    AGENTS.md, CLAUDE.md, docs/README.md
    bootstrap, doctor, dev, test, check, affected, classify-paths, generate,
    docs-check, docs-validator.mjs, docs-impact-check, openapi-compat, governance-check
```

### 7.2 Toolchain mirror

| Layer | 10x choice to copy | Source |
|---|---|---|
| Node / Python | Node 22, Python 3.12.7, `uv` for venv | `.nvmrc`, `.python-version`, `scripts/bootstrap` |
| Backend | FastAPI `==` pinned + pydantic `==` pinned, uvicorn, httpx, orjson, PyJWT[crypto], posthog, python-dotenv; pytest + pytest-asyncio + pytest-xdist | `backend/requirements*.txt` |
| DB / auth | Supabase Postgres via PostgREST with service-role from the API, Supabase Auth JWT verified in `api/dependencies.py`, RLS as defense in depth, SQL migrations `NNN_name.sql` applied by Supabase CLI | 2.4, 2.5 |
| Jobs | Durable rows + leased poller worker process (`scripts/run_<x>_worker.py`) on Render/Fly; cron via Render `cron` service | 2.7 |
| Contracts | In-process OpenAPI export + `--check` drift gate + `openapi-compat` breaking-change gate; `openapi-typescript` for web; handwritten Codable models for iOS | 2.9 |
| Web | Next.js 16 (SPA discipline), React 19, TanStack Query 5, Zustand 5, openapi-fetch, MSW 2, Tailwind 4 with wiped palettes, Radix, Vitest 4, `@sentry/nextjs`, `posthog-js` | 5.1 |
| iOS | Swift tools 6.2, iOS 26, one SPM library `<App>Kit` + thin Xcode app target, `swift-snapshot-testing` 1.17+, Swift Testing for parity tests, XCTest for snapshots | 3.1, 3.10 |
| Tokens | `packages/design-tokens/tokens.json` + `schema.json` + dependency-free Node generator emitting CSS/TS/Swift | 3.4, `packages/design-tokens/README.md` |
| Analytics | PostHog with registered event names generated into web + backend constants; server property allowlists | 6.2 |
| Errors | PostHog exception capture (backend, web) + Sentry on web (privacy-sanitized); add PostHog/Sentry to iOS deliberately (10x has none) | 6.2, `docs/observability.md` |
| Hosting | Vercel for web and the FastAPI API (`framework: fastapi`), Render for long-lived workers/WebSocket services, Supabase for data | 2.10 |

### 7.3 Copy verbatim vs adapt

**Copy verbatim (rename `10x`/`TenX` -> `Readsync`, drop 10x-only domains):**
- `CLAUDE.md` contents (`@AGENTS.md`) in every scope.
- `.editorconfig`, `.gitignore`, `.nvmrc`, `.python-version`.
- `scripts/AGENTS.md` rules; `scripts/bootstrap`, `scripts/doctor`, `scripts/dev`, `scripts/test`, `scripts/check`, `scripts/affected`, `scripts/generate`, `scripts/docs-check` (trim the scope list), `scripts/docs-validator.mjs`, `scripts/classify-paths` (trim cases).
- `docs/agent-workflow.md`, `docs/design/*.md` (all eight; they are product-agnostic policy), `docs/features/_template/`, `docs/adr/0000-template.md`, `docs/adr/0001-monorepo.md`, `docs/adr/0002-design-system-boundaries.md`, `docs/adr/0024-checked-openapi-artifacts.md`.
- `.github/pull_request_template.md` (drop the admin-data-access block).
- `packages/design-tokens/` in full (`package.json`, `schema.json`, `scripts/generate.mjs`, `tests/`, `docs/token-model.md`); then edit `tokens.json` values for Readsync's palette, keep the semantic names.
- `packages/AGENTS.md`, `contracts/AGENTS.md`, `contracts/analytics-events/` (README, generator, empty registry).
- Backend: `api/config.py` loading pattern, `api/dependencies.py` (Supabase JWT + JWKS cache + `AuthenticatedUser`), `api/versioning.py`, `api/http.py`, `shared/openapi_summaries.py`, `shared/logging_privacy.py`, `scripts/export_openapi.py`, `scripts/openapi_compat.py`, `scripts/dev.sh`, `tests/conftest.py` shape, `api/services/email_sender.py` (Resend), `api/services/analytics.py` (allowlist pattern), migration file style (`BEGIN; CREATE TABLE IF NOT EXISTS ...; ENABLE ROW LEVEL SECURITY; COMMIT;`).
- iOS: `Package.swift`, `Theme/Theme.swift` adapter, `Glass/GlassChrome.swift`, `Mocks/MockTransport.swift`, `Mocks/Fixtures.swift`, `API/APIClient.swift`, `LoadState` + store template from `API/Stores.swift`, `Primitives/*` (all), `Tests/ScreenSnapshotTests.swift` harness, `Tests/FixtureParityTests.swift` shape, `scripts/export-fixtures.mjs`, `ios/README.md` "Architecture rules (binding)" and `ios/AGENTS.md` "Binding rules", `ios/docs/*` (navigation, design-system, testing).
- Web: `web/AGENTS.md` architecture + file-organization + binding rules, `web/README.md` rules, `src/lib/api/client.ts` middleware pattern, `src/store/*` pattern, `src/mocks/` pattern, `src/lib/analytics.ts`, sentry configs, `next.config.ts` headers/rewrites, `vitest.config.ts`, `vitest.setup.ts`, `scripts/lint-design.mjs`, `docs/design-conventions.md` token vocabulary.

**Adapt:**
- Root `AGENTS.md`: keep structure and every rule list; replace mission/domains, drop fleet/preview/admin-stats/prompt-corpus sections, replace the developer allowlist with Readsync's handles (identity check via `gh api user --jq .login` stays), shorten the repository map to the projects Readsync has.
- `docs/product.md`, `business.md`, `glossary.md`: rewrite for a book reader (vocabulary: book, library, chapter, position/progress, highlight, narration, sync).
- `docs/architecture.md`, `deployment-*.md`, `domains-and-environments.md`, `observability.md`, `security-and-privacy.md`: keep headings and invariants list; fill Readsync services.
- Feature packets: create per Readsync journey (library, reader, sync, audio/narration, onboarding, paywall, account) from `_template/`; add `registry.yml`.
- Backend routers/services/schemas/migrations: new domains; keep the router->service->PostgREST helper layering and the `HTTPException` validation style.
- Provider wrappers for OpenAI, ElevenLabs, fal, Stripe/RevenueCat: write in the `email_sender.py` shape (module constants for endpoint, `settings.<key>`, one error class, `async def` functions over `httpx`, mocked at the module boundary in tests). 10x has no ElevenLabs/fal code to copy.
- iOS `MockHandlers.swift`, `Models.swift`, `Stores.swift`, `Views/*`: new routes/models/screens; keep `liveRoutes`/fixture-group split and interactive mutation state.
- iOS navigation: keep the "app tier = native `TabView`, deep task tier = full-screen cover with glass pill" model but define Readsync's tabs; keep `OPEN_*` debug deep links.
- Tokens: keep `tokens.json` schema and category names; change values; bump `version`.
- Web `src/app`, `views`, hooks, fixtures: new screens; keep query-key module and hook-per-surface pattern.
- CI `ci.yml`: keep `changes` + classify fan-out and the gate jobs that apply (docs, docs_impact, design_tokens, analytics_events, openapi, backend, web, ios); drop asyncapi/realtime/admin/creator/macos/website unless needed.
- Analytics registry: start `events.json` empty and register every Readsync event before emitting; add an iOS generated consumer (10x planned but never built one).
- Add what 10x lacks and Readsync needs: iOS PostHog/Sentry setup, iOS Keychain-backed Supabase session, an iOS release pipeline doc (`ios/docs/deployment.md` in 10x is still a draft), a generated Swift client only if the team decides to close the gap 10x left open.
