# Data connections (EarthRanger, SMART, GEE)

How workflows reach external data sources, and how credentials flow in each environment.

## Contents
- Architecture
- Connection types and fields
- Environment-variable format
- spec.yaml setup
- CI secrets (including the GEE base64 recipe)
- Desktop
- Troubleshooting

## Architecture

Three layers:

1. **Connection classes** — pydantic-settings models loaded from env vars (or a pyproject
   fallback table).
2. **Setup tasks** — `set_er_connection` / `set_smart_connection` / `set_gee_connection` return
   the connection **name as a plain `str`**.
3. **Client types** — `EarthRangerClient`, `SmartClient`, `EarthEngineClient`: annotated types
   whose BeforeValidator resolves the name string into a live client at task-call time.

**The UI's data-source picker comes from the setup task's *parameter* type**
(`data_source: Annotated[EarthRangerConnection, DataSourceField]`), not from its return type —
upstream docs saying "return type" are wrong ([upstream-docs.md](upstream-docs.md)). The
connection dataclass carries `name` (titled "Data Source") plus an excluded `connection_type`
discriminator.

## Connection types and fields

| Type | env segment | Fields |
|---|---|---|
| EarthRanger | `earthranger` | `server` (req), `username`, `password`, `token`, `tcp_limit` (5), `sub_page_size` (4000) |
| SMART | `smart` | `server` (req), `username`, `password`, `token` |
| Earth Engine | `earthengine` | `service_account`, `private_key`, `private_key_file`, `ee_project` |

ER and SMART enforce **token XOR (username+password)** — both or neither raises.

## Environment-variable format

```
ECOSCOPE_WORKFLOWS__CONNECTIONS__<TYPE>__<NAME>__<FIELD>
```

Case-insensitive; **the connection name is the third path segment** — the piece most likely to
trip someone up:

```bash
ECOSCOPE_WORKFLOWS__CONNECTIONS__EARTHRANGER__MEP_DEV__SERVER=https://…
ECOSCOPE_WORKFLOWS__CONNECTIONS__EARTHRANGER__MEP_DEV__USERNAME=…
ECOSCOPE_WORKFLOWS__CONNECTIONS__EARTHRANGER__MEP_DEV__PASSWORD=…
```

The name in `test-cases.yaml` (`data_source.name: "mep_dev"`) must match that segment. Supplied
via shell/.env locally, GitHub secrets in CI, and the Desktop UI per session.

Other runtime env vars: `ECOSCOPE_WORKFLOWS_RESULTS` (the only one intended for direct
`${{ env.* }}` use in specs), plus warehouse switches
(`USE_EARTHRANGER_WAREHOUSE_API`, `EARTHRANGER_WAREHOUSE_API_BASE_URL`, `DWH_EVENTS_ENABLED` —
the last read on every call so it can be flipped without re-import).

## spec.yaml setup

Setup task first; fetch tasks receive the name via the return reference:

```yaml
  - {name: Data Source, id: er_client_name, task: set_er_connection}
  - {name: Get Events, id: get_event_data, task: get_events,
     partial: {client: "${{ workflow.er_client_name.return }}",
               time_range: "${{ workflow.time_range.return }}", raise_on_empty: false}}
```

Dynamic dropdowns keyed to the selected connection use `ecoscope:transform` +
`EarthRangerEnumResolver` — syntax and the Desktop rendering caveat in [rjsf.md](rjsf.md).

## CI secrets

Per-source secrets, wired as env vars in the repo's `test.yml` test step (the scaffold's generic
`test.yml` has NO connection env block — live CI cases fail auth until it's added):

| Source | Secrets | Wired as |
|---|---|---|
| EarthRanger | `ER_SERVER`, `ER_USERNAME`, `ER_PASSWORD` | `…__EARTHRANGER__<NAME>__{SERVER,USERNAME,PASSWORD}` |
| SMART | `SMART_SERVER`, `SMART_USERNAME`, `SMART_PASSWORD` | `…__SMART__<NAME>__…` |
| Earth Engine | `EE_SERVICE_ACCOUNT`, `EE_PRIVATE_KEY` (base64 JSON) | service_account + decoded key file |

Changing the connection name means updating all three places: `test-cases.yaml`, the `test.yml`
env segment, and (checking) the repo secrets. **Setting secrets is a user action** — `gh secret
set` is permission-blocked for the agent; surface the need instead
([process-rules.md](process-rules.md)).

**GEE key recipe** — always base64-encode the ORIGINAL `.json` key file (env-var copies mangle
newlines / URL-encode quotes):

```bash
base64 < /path/to/gee-service-account-key.json | gh secret set EE_PRIVATE_KEY -R <owner/repo>
```

Decode in CI with `printf '%s' "$EE_KEY_JSON" | base64 -d > gee-key.json` (env-var reference,
never `echo "${{ secrets.* }}"`), then point
`…__earthengine__<name>__private_key_file` at the decoded file. Locally, prefer
`private_key_file` pointing at the JSON over embedding the key in an env var.

## Desktop

Data sources are pre-configured in the app; the workflow form's connection dropdown is the only
true select-widget on a typical form. Users re-enter passwords each session. To exercise
locally-edited task code in Desktop, switch the relevant requirement to `path:` + `editable: true`
and recompile with `--install` ([spec.md](spec.md)); revert before publish.

## Troubleshooting

- **402/502 from ER or SMART**: these services sit behind a VPN — switch VPN server before
  debugging anything else.
- **`ValueError: Failed to find IDs for values: {...}`** on a live run: the server pruned a
  patrol/event type your spec or test case still names. Re-list (e.g.
  `client.get_patrol_types()` from the inner env) and update defaults — server-side config drift
  breaks live runs only; mock runs keep passing.
- Empty live results with `Success` status: the connection is valid but the window/type filter
  matches nothing — the silently-empty-run trap ([testing.md](testing.md)).
