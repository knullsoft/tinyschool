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

## Deploy with Dokploy

TinySchool uses the root `docker-compose.yml`. The single container embeds the
UI and API, while the named volume persists SQLite data and backups.

1. In Dokploy, create a **Docker Compose** service from this repository.
2. Set the Compose path to `./docker-compose.yml`.
3. Add `TINYSCHOOL_APP_BASE_URL=https://your-domain.example` in Environment.
4. In Domains, route your domain to service `app`, port `8080`, then deploy.

Optional: set `APP_VERSION` to the version shown in the UI footer.

Dokploy manages HTTPS and routing. Do not publish port `8080` on the host.
The `tinyschool-data` named volume can be backed up through Dokploy's volume
backup feature.
