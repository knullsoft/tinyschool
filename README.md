# Tiny School

A simply school management software to manage students, classes

## Run locally

```bash
./scripts/run-local.sh
```

This stops any previous local run, builds the static UI into the API binary, and
starts a single Go server. Open `http://127.0.0.1:8080`. Logs and PID files are
written to `.runs/local`.

Override the port when needed:

```bash
TINYSCHOOL_API_PORT=8180 ./scripts/run-local.sh
```

Stop the server with:

```bash
./scripts/stop-local.sh
```

Local data is stored in `.runs/local/tinyschool.db`. A new database starts
empty; create an account from the registration page.

Screenshots still use a UI-only Nuxt dev server (no API):

```bash
./scripts/take-screenshot.sh
```

## API architecture

```text
Cobra/Viper -> server -> delivery/http -> service -> storage interface
                                                     |
                                                     v
                                            storage/gormsqlite
```

- `internal/model`: database-independent domain models.
- `internal/dto`: request and response contracts.
- `internal/service`: validation and business rules.
- `internal/storage`: replaceable persistence interface.
- `internal/storage/gormsqlite`: all GORM, SQLite, migration, seed, and query
  code.
- `internal/delivery/http`: handlers and HTTP middleware.
- `internal/staticui`: embedded Nuxt SPA served at `/`.
- `internal/server`: routes and graceful shutdown.

The detailed endpoint contract and implementation plan is in
`requirements/api-plan.md`.

Run the API directly (build the UI first if you changed it):

```bash
./scripts/build-ui.sh
cd tinyschool-api
go run . --database ./tinyschool.db --address :8080
```

UI is served at `/`; JSON API lives under `/api/v1`. Probes: `/health`, `/ready`.

## Data export and import

`Settings → Data` downloads and restores the whole workspace of the signed-in
account.

- `GET /api/v1/me/data/export` returns an `.xlsx` workbook with one sheet per
  record type. `?format=csv` returns the same sheets as a `.zip` of CSV files.
- `POST /api/v1/me/data/import` takes the file back as multipart field `file`
  (`.xlsx`, `.zip`, or a single sheet as `.csv`) and **replaces** everything the
  account owns, in one transaction. Nothing is written unless the whole file
  validates.

The sheets are `schools`, `academic_years`, `academic_segments`, `students`,
`student_classrooms`, `student_logs`, `classes`, `class_students`,
`assignments`, `assignment_scores`, `exams` and `exam_scores`. Rows point at
each other with the ids in the file; those ids are local to the file, and the
importer stores every record under a freshly generated id, so a file exported
from one account can be imported into another. Multi-valued cells (a school's
classrooms) are separated with `|`, and columns are matched by header name, so
a hand-edited sheet may reorder or drop columns.

An export of an empty account is a usable import template: every sheet is
present with its header row.

## Deploy (SSH)

Requires the shared edge from [`../deployer`](../deployer) (Swarm + Traefik on
overlay network `proxy`). The same script deploys from a laptop or GitHub Actions:

```text
laptop: upload source → build image → docker stack deploy → Traefik HTTPS → /ready
CI:     upload source → pull CI image → docker stack deploy → Traefik HTTPS → /ready
```

```text
deployer (once)          tinyschool (per release)
─────────────────        ─────────────────────────
Swarm + Traefik    ──►   stack tinyschool_api
overlay: proxy           deploy.labels → Host(DOMAIN)
certresolver: le         joins network proxy
```

TinySchool deploys as Swarm stack `tinyschool` (`deploy/stack.yaml`). Labels live
under `deploy.labels` so Traefik's swarm provider picks them up. The API image
embeds the static UI; Traefik proxies everything to port 8080.

```bash
# one-time on the VPS (from the deployer repo)
DEPLOY_HOST=147.93.97.228 ACME_EMAIL=you@example.com ./scripts/bootstrap-vps.sh

# then from this repo
ssh-copy-id root@147.93.97.228
./scripts/deploy.sh
```

Default URL: `https://tinyschool.147.93.97.228.nip.io`

No image variable is needed when building on the server. `IMAGE_API` is an
optional CI override for pulling a pre-built image from the registry.

Override with `DEPLOY_HOST`, `DEPLOY_USER`, `DEPLOY_PATH`, `DEPLOY_DOMAIN`,
`STACK_NAME`, or `PROXY_NETWORK`. SQLite lives in the stack volume
`tinyschool_data` (single replica on the manager); TLS stays with Traefik.

### GitHub Actions

Add the private key as the `DEPLOY_SSH_PRIVATE_KEY` repository secret.
Optional repository variables use the same `DEPLOY_*` names above.

#### Releases

Versions are git tags (`vX.Y.Z`). The tag is baked into the UI at image build
time and shown as a subtle footer on every page.

```text
tag v0.1.0 ──► Deploy workflow ──► api image + production ──► footer shows v0.1.0
```

Create a release either way:

1. **From GitHub** — Actions → **Release** → Run workflow → enter `v0.1.0`
2. **From git** — tag and push yourself:

```bash
git tag -a v0.1.0 -m "Release v0.1.0"
git push origin v0.1.0
```

Pushing a `v*.*.*` tag runs **Deploy**. Manual **Deploy** (workflow_dispatch)
redeploys the current commit using `git describe` for the footer version.
