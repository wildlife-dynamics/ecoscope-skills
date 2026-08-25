# Task pitfalls

Gotchas when wiring specific tasks in specs. Cross-referenced from the compile→test loop.

## Contents
- `apply_sql_query`
- `normalize_json_column`
- `create_docx`
- `persist_grouped_dfs_for_results_download`
- Misc

## `apply_sql_query`

- **SQLite dialect, not DuckDB**: `TRY_CAST(x AS DOUBLE)` → `CAST(x AS REAL)`; `DOUBLE` → `REAL`
  or `INTEGER`. `json_extract()` IS available and useful.
- **Complex column types break SQLite**: columns holding Python dicts or lists can't be stored;
  `SELECT *` fails silently or errors. Common offenders after `load_df(deserialize_json=true)`:
  `attributes` (list), `extracted_attributes` (dict), `reported_by` (dict). Fix with
  `sanitize: true` (default since ecoscope v2.17.0): list/dict/set/bytes columns are converted to
  JSON strings before the query runs; geometry is preserved. The JSON strings then work with
  `json_extract()` (below). Only set `sanitize: false` when a downstream task needs the real
  list/dict values — then use the `columns:` whitelist to exclude them, or restructure so they're
  removed/expanded first (e.g. `normalize_json_column`). Only whitelist columns **guaranteed to
  exist** — optional fields KeyError.
- **`json_extract()` beats normalize+SQL** for simple extractions from JSON-string columns:

  ```sql
  SELECT uuid, X, Y, time, geometry,
    json_extract(extracted_attributes, '$.Species') AS "Species",
    COALESCE(CAST(json_extract(extracted_attributes, '$."Count"') AS REAL), 0) AS "Count"
  FROM df
  WHERE json_extract(extracted_attributes, '$.Species') IS NOT NULL
  ```

## `normalize_json_column`

- **Requires Python dicts, not JSON strings.** On strings, `pd.json_normalize` silently produces
  empty columns — data lost without error. Diagnosis: expected `column__field` columns missing
  after normalize ⇒ input was strings.
- Must run **before** any SQL that references the expanded columns; the original column is
  replaced by `column__field1`, `column__field2`, ….

## `create_docx`

Context item types (`context.items`, each `{item_type, key, value, ...}`). A grouped `value` is a
list of `(CompositeFilter, value)` tuples, i.e. `split_groups`/`groupbykey` output:

| `item_type` | `value` | Template usage |
|---|---|---|
| `timerange` | TimeRange | `{{ key }}` (with `format:`; collapses to one value when since/until format identically, e.g. `%b %Y` → `Feb 2026`) |
| `text` | string | `{{ key }}` |
| `text` (grouped) | list of (filter, string) | `{% for item in key %}{{ item.title }}{{ item.value }}{% endfor %}` |
| `image` | path (`.png`/`.jpg`/`.html`) | `{{ key }}` → InlineImage; `width_inches` (default 6, shared), `height_inches`, `screenshot_config` |
| `image` (grouped) | list of (filter, path) | `{% for item in key %}{{ item.title }}{{ item.image }}{% endfor %}` |
| `table` | DataFrame | `{{ key.col_labels }}`, `{{ key.tbl_contents }}` (`row.label`, `row.cols`) |
| `table` (grouped) | list of (filter, DataFrame) | `{% for item in key %}` with `item.title`, `item.col_labels`, `item.tbl_contents`; or `merge_groups: true` → one direct-style table with a `Group` column (omitted for a lone "All" group) |

- **Grouped items require `groupers`** (pass the same groupers used to split the data). Without
  them `create_docx` raises `ValueError: Grouped items require groupers` — the param description's
  "sorted alphabetically" fallback does not exist. A filter index not covered by the groupers
  raises `No grouper found for index_name`. Groupers also drive `item.title` (grouper
  `display_name`; column name omitted when there's a single grouper) and sort order (e.g. months
  in calendar order).
- Grouped items also expose `item.groups` (`{index_name: value}`, "all" dropped) for nested
  sections: `{%p for area, maps in patrol_maps|groupby("groups.patrol_area") %}`.
- Give it `skipif: {conditions: [never]}` like widgets; skip handling is built in (task-library
  #225, 2026-08-19): SkipSentinel entries inside grouped values are dropped, a skipped direct
  text/image renders blank (or `missing_text`, e.g. `"(No data)"`), a skipped direct table renders
  empty so template loops still work. `skip: true` returns `None` without rendering.
- Output is `[<filename_prefix>_]<7-char context hash>.docx` under `output_dir`.
- The `.docx` template is user-authored (Jinja2 placeholders matching context keys; `.html` images
  auto-convert to PNG via Playwright), lives under `resources/templates/` in the repo. Local runs
  use an absolute path in test cases; **publishing converts it to a GitHub raw URL** — SHA-pinned
  during PR CI ([testing.md](testing.md)).

## `persist_grouped_dfs_for_results_download`

- Use this for results downloads, **not `persist_df_wrapper`**: it wraps `persist_df_wrapper` per
  group and prefixes each filename with a 7-char hash of the group key, which the FE needs to
  match files to dashboard views. Input is `split_groups` output (`(filter, df)` tuples).
- `sanitize: true` serializes complex objects (dicts/lists/sets) to JSON strings for
  Arrow/Parquet — set it whenever event/observation details are included. Default is `false`.
- Groups with a `None` key or an empty df are silently skipped — an empty return list is not an
  error.

## Misc

- **`filter_row_values` / `exclude_row_values`** take `values: list[str] | None` (None = no
  filtering); pair with `set_list_of_string_vars` for user-configurable lists. Values must match
  the data's **display titles** exactly when upstream mapped raw values to titles
  (`process_events_details(map_to_titles=True)`) — a raw-slug default silently matches nothing.
  Verify titles from a live run's output before setting defaults.
- **`convert_values_to_timezone`** — `columns: [...]` or `auto_detect: true`, mutually exclusive.
- **`with_unit` / quantity fields** — unit suffixes auto-append on CustomMetric-style outputs on
  current platform releases; don't hand-append in labels.
- A task importable in Python but unknown to the compiler is a discovery problem —
  [task-discovery.md](task-discovery.md) has the checklist.
