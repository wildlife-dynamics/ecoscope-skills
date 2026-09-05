# Catalog metadata — the three surfaces

What "the catalog" shows for a workflow — name, description, image, latest version — is read
from three places that do not sync with each other. Verified against the code named in
§ Where to verify; re-check there before relying on a detail.

## Contents
- The three surfaces
- Spec `metadata:` (the workflow repo)
- Desktop catalog (a JSON on GCS)
- Web catalog (an ecoscope-server template row)
- The rename trap
- Where to verify

## The three surfaces

| Surface | Read by | Holds | Set where |
|---|---|---|---|
| `spec.yaml` `metadata:` | nothing downstream yet — attribution and a convention for future tooling | name, description, maintainers, license, links, keywords, plus any extra key | the workflow repo |
| Desktop catalog JSON | Ecoscope Desktop's template catalog | name, description, repo `url`, `version_file_path` | ecoscope-desktop repo backup file + a manual `gsutil cp` to GCS |
| Server `workflow_template` row | ecoscope-web (web app, and Desktop for imported templates) | name, category, description, `image_url` | the server's template create/update endpoints, per environment |

## Spec `metadata:` (the workflow repo)

Compiler ≥ 0.9.0 (`Metadata` and `Maintainer` in `wt_compiler.spec`). When the block is present,
`name`, `description`, `maintainers` (non-empty) and `license` are required; `repository`,
`documentation`, `readme`, `keywords` are optional; both models allow and retain extra keys.
Excluded from `Spec.sha256`, so a metadata-only change compiles to a byte-identical generated
tree — and `--update` still bumps MIN (`compile.md` § `--update` semantics). The compiler
templates never read it: it is not in the generated package, `README.md` or `rjsf.json`.

The fleet convention for extras, so specs converge on the same keys:

```yaml
metadata:
  name: NDVI Workflow                     # match the Desktop catalog entry
  description: >-
    One paragraph, same text as the Desktop catalog entry.
  maintainers:
    - {name: Yun Wu, email: yun@wildlifedynamics.com, role: owner}
    - {name: Alex Morling, email: alexm@earthranger.com, role: reviewer}
  license: BSD-3-Clause                   # SPDX id, not the LICENSE title
  repository: https://github.com/<org>/<repo>
  documentation: https://github.com/<org>/<repo>#readme
  readme: README.md
  keywords: [ndvi, vegetation, gee]
  thumbnail: resources/thumbnail.png      # repo-relative, committed alongside
```

## Desktop catalog (a JSON on GCS)

Desktop lists the templates named in one hardcoded file on public GCS (URL in ecoscope-web's
`constants.ts`; backup copy and the upload command in the ecoscope-desktop `README.md` §
Template Catalog). Each entry is `{name, description, url, version_file_path}` — the zod schema
`catalogItemSchema` in ecoscope-web reads exactly those four, so there is no image slot. The
latest version is not in the file: Desktop fetches `version_file_path` from the GitHub repo at
`url` on every listing (`enrichCatalogItemAndFetchLatestVersion`).

Once a user imports the template, the on-disk record hardcodes `image_url: null` and the
description `Source code: <url>` (`workflowtemplates.desktop.server.utils.ts`), so the JSON
description shows only in the catalog listing, never on the imported template.

To change an entry: edit the backup file in ecoscope-desktop, PR it against a ticket, then
upload the same file by hand with `Cache-Control: no-cache` (command in that README). Nothing
in any workflow repo's CI touches this file.

## Web catalog (an ecoscope-server template row)

**v1 (service-URL) templates** — the production catalog. `CreateWorkflowTemplate` /
`UpdateWorkflowTemplate` (`ecoscope_server/schemas/workflow_template.py`) carry `name`,
`category`, `description`, `image_url`; `image_url` is a plain URL string (128 chars max on the
column, `models/base.py`). The compose deploy script
(`template-service-url-version-bump.py`) only *adds versions* to a template it finds by exact
`name` (`get_template_name`); the row itself is created once by hand per environment, and that
is where the image is set.

The web card (`WorkflowTemplateCard.tsx`) renders `image_url` when present and not the
placeholder `https://example.com/image.png`; otherwise it falls back to
`workflowTemplateGraphics` (`utils/workflows.utils.ts`) — a switch keyed by the exact template
name constants in `utils/constants.ts`, each pairing an SVG under `src/ui/images/` with a
background colour. A name not in that switch gets the generic dashboard icon on teal. A bespoke
logo for a new catalog workflow is therefore a web-app change: SVG, name constant, switch case.

**v2 (sandboxed / custom) templates** registered from a GitHub release
(`services/workflow_templates.py`, `register_custom_workflow_template`): `name` is the repo
slug, `description` is the GitHub repo "About" text, `category` is `custom`, `image_url` is
forced to `None`. Display metadata is deliberately kept outside the digest-hashed
`metadata.json`. To change what users see, edit the repo's About field on GitHub; re-registering
at a new tag re-syncs it.

## The rename trap

Two exact-string couplings, neither guarded by CI:

- The Desktop entry's `version_file_path` hardcodes the generated package directory
  (`ecoscope-workflows-<id>-workflow/VERSION.yaml`). Changing the spec `id` or the compile's
  `--pkg-name-prefix` moves that file; Desktop's version fetch then fails, the entry reports
  no version, and the listing flags "some versions unavailable" — with the old version still
  installed for everyone who already imported it. Update the JSON in the same release.
- The server template `name` is the key for both the compose deploy script and the web logo
  map. Renaming a v1 template breaks the deploy's lookup and drops the bespoke logo.

## Where to verify

| Fact | Look at |
|---|---|
| Spec model, required vs optional | `wt_compiler.spec` — `Metadata`, `Maintainer`, `Spec.sha256` |
| Desktop catalog URL, schema, enrichment | ecoscope-web `utils/constants.ts`; `domain/entities/…/workflow-templates/import/models.ts` (`catalogItemSchema`); `utils/actions/workflow-templates/workflowtemplates.desktop.server.utils.ts` |
| Catalog backup file and upload command | ecoscope-desktop `README.md` § Template Catalog; `gcs/hardcoded-template-catalog/workflow_templates.json` |
| Server template schema and v2 registration | ecoscope-server `schemas/workflow_template.py`; `services/workflow_templates.py`; `README.md` § v2 (sandboxed) workflow templates |
| Web card fallback | ecoscope-web `WorkflowTemplateCard.tsx`; `utils/workflows.utils.ts` (`workflowTemplateGraphics`, `workflowType`) |
| Compose deploy name match | compose `template-service-url-version-bump.py` (`get_template_name`) |
