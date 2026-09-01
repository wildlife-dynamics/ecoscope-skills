# Workflow patterns

The recurring spec shapes, drawn from real fleet specs. Syntax lives in [spec.md](spec.md); task
semantics in [tasks.md](tasks.md).

## Contents
- The pipeline skeleton
- Setup and fetch
- Grouping, splitting, and the spatial-grouper resolver chain
- Widget pipelines (map, chart)
- Data export and DOCX reports
- Dashboard assembly and the "Edit Layout" predicate
- `groupbykey` — zipping keyed iterables
- Positive "keep" toggles

## The pipeline skeleton

Every recent wt-framework spec follows this order:

```
set_workflow_details → set_er_connection → set_time_range → get_timezone_from_time_range
→ <fetch> → convert_values_to_timezone → filters card
→ set_groupers [+ spatial resolver chain] → add_temporal_index → add_spatial_index
→ convert_column_values_to_string → split_groups
→ per-widget mapvalues chains → persist_text → create_*_widget_single_view (skipif never)
→ merge_widget_views → gather_dashboard
```

## Setup and fetch

```yaml
workflow:
  - {name: Workflow Details, id: workflow_details, task: set_workflow_details}
  - {name: Time Range, id: time_range, task: set_time_range,
     partial: {time_format: "%d %b %Y %H:%M:%S %Z"}}
  - {name: Extract Timezone, id: get_timezone, task: get_timezone_from_time_range,
     partial: {time_range: "${{ workflow.time_range.return }}"}}
  - {name: Data Source, id: er_client_name, task: set_er_connection}

  - {name: Get Events, id: get_event_data, task: get_events,
     partial: {client: "${{ workflow.er_client_name.return }}",
               time_range: "${{ workflow.time_range.return }}", raise_on_empty: false}}
```

`workflow_details` must use exactly that id ([tasks.md](tasks.md)). For file-based sources use
`load_df`.

## Grouping and splitting

```yaml
  - {name: Set Groupers, id: groupers, task: set_groupers}
  - {name: Add Temporal Index, id: temporal_index, task: add_temporal_index,
     partial: {df: "${{ workflow.sql_query.return }}", groupers: "${{ workflow.groupers.return }}"}}
  - {name: Split by Group, id: grouped, task: split_groups,   # id ≠ task name (spec.md rule 2)
     partial: {df: "${{ workflow.temporal_index.return }}", groupers: "${{ workflow.groupers.return }}"}}
```

**Spatial groupers need a three-task resolver chain** (the upstream groupers tutorial omits it):

```yaml
  - {id: spatial_group_names, task: extract_spatial_grouper_feature_group_names,
     partial: {groupers: "${{ workflow.groupers.return }}"}}
  - {id: spatial_feature_groups, task: get_spatial_features_group,
     partial: {client: "${{ workflow.er_client_name.return }}"},
     map: {argnames: spatial_features_group_name, argvalues: "${{ workflow.spatial_group_names.return }}"}}
  - {id: resolved_groupers, task: resolve_spatial_feature_groups_for_spatial_groupers,
     skipif: {conditions: [never]},
     partial: {groupers: "${{ workflow.groupers.return }}",
               spatial_feature_groups: "${{ workflow.spatial_feature_groups.return }}"}}
```

then `add_spatial_index` consumes `resolved_groupers`. The resolver keys its lookup on the feature
group's **`metadata.display_name`**, not the requested name — a mismatch silently leaves the
grouper unresolved, `add_spatial_index` adds nothing, and `split_groups` dies with
`KeyError('SpatialGrouper_<name>')`. Mocked test cases must therefore use the display name the
mock fixture carries (`"SpatialGrouperTest"` for the stock fixture — [testing.md](testing.md)).
`add_spatial_index` appends the region as a pandas **index level**, not a column.

## Widget pipelines

**Map:** `apply_color_map → create_{point|polyline|polygon}_layer → draw_ecomap → persist_text →
create_map_widget_single_view → merge_widget_views` (styling defaults in
[output-style.md](output-style.md)):

```yaml
      - {name: Apply Colormap, id: colormap, task: apply_color_map,
         partial: {input_column_name: category, colormap: tab20b},
         mapvalues: {argnames: df, argvalues: "${{ workflow.grouped.return }}"}}
      - {name: Create Polyline Layer, id: polyline_layer, task: create_polyline_layer,
         skipif: {conditions: [any_is_empty_df, any_dependency_skipped, all_geometry_are_none]},
         partial: {layer_style: {get_color_column: category_colormap, get_width: 2},
                   legend: {label_column: Category, color_column: category_colormap}},
         mapvalues: {argnames: geodataframe, argvalues: "${{ workflow.colormap.return }}"}}
      - {name: Set Base Maps, id: base_map_defs, task: set_base_maps}
      - {name: Draw Ecomap, id: ecomap, task: draw_ecomap,
         partial: {tile_layers: "${{ workflow.base_map_defs.return }}", static: false, max_zoom: 20},
         mapvalues: {argnames: geo_layers, argvalues: "${{ workflow.polyline_layer.return }}"}}
      - {name: Persist Ecomap, id: ecomap_html_url, task: persist_text,
         partial: {root_path: "${{ env.ECOSCOPE_WORKFLOWS_RESULTS }}"},
         mapvalues: {argnames: text, argvalues: "${{ workflow.ecomap.return }}"}}
      - {name: Create Map Widget, id: map_widget, task: create_map_widget_single_view,
         skipif: {conditions: [never]},
         partial: {title: "My Map"},
         map: {argnames: [view, data], argvalues: "${{ workflow.ecomap_html_url.return }}"}}
      - {name: Merge Map Widget Views, id: merged_map_widget, task: merge_widget_views,
         partial: {widgets: "${{ workflow.map_widget.return }}"}}
```

Note the `mapvalues`→`map` transition at the widget step (the persisted keyed iterable yields
`[view, data]` tuples that `map` destructures), and `skipif: never` on the widget.
`persist_text(text, root_path, filename=None, filename_suffix=None) -> str` hashes the text into
a filename when none is given. Polyline layers use `get_color_column`/`get_width` (NOT
`fill_color_column`/`get_radius`, which are point-layer params).

**Chart:** `draw_{line|bar|time_series_bar|pie}_chart → persist_text →
create_plot_widget_single_view → merge_widget_views` — same persist/widget/merge tail as maps.

## Data export and DOCX reports

**Export:** `persist_grouped_dfs_for_results_download` (not `persist_df_wrapper` — the FE needs
the group-key hash it embeds in each filename to match downloads to dashboard views). Feed it
`split_groups` output as `grouped_dfs` (works ungrouped too), with
`root_path: ${{ env.ECOSCOPE_WORKFLOWS_RESULTS }}`, `filetypes: [csv|geoparquet|gpkg]`, optional
`filename_prefix`, and `sanitize: true` if data has nested JSON/lists (serializes complex columns
to JSON strings). Groups with an empty df are skipped.

**DOCX:** context items typed `timerange` / `table` / `image` (direct path or grouped
`(filter, path)` list) / `text`; template is a user-authored `.docx` with Jinja2 placeholders
matching context keys; HTML images auto-convert to PNG via Playwright. Gotchas (`groupers`
required for grouped items, skip handling, template-path resolution and raw URLs) in
[task-pitfalls.md](task-pitfalls.md) and [testing.md](testing.md).

## Dashboard assembly and the "Edit Layout" predicate

```yaml
  - {name: Create Dashboard, id: dashboard, task: gather_dashboard,
     partial: {details: "${{ workflow.workflow_details.return }}",
               widgets: ["${{ workflow.merged_map_widget.return }}",
                         "${{ workflow.merged_chart_widget.return }}"],
               groupers: "${{ workflow.groupers.return }}",
               time_range: "${{ workflow.time_range.return }}"}}
```

An ungrouped workflow (no groupers/split/merge; widgets flow straight in) produces `views` of
exactly `{"{}": [...]}`, and Ecoscope Desktop **hides the "Edit Layout" button** on it. With
`set_groupers` in the spec and nothing selected the key is `{"All": "True"}` (the AllGrouper) —
a real view, Edit Layout stays; an empty fixture still yields `{}`. The render predicate in ecoscope-web's `WorkflowResults.tsx`:

```js
isNoView = data.views && Object.keys(data.views).length == 1 && Object.keys(data.views)[0] === '{}'
// Edit Layout wrapped in {!isNoView && ...}
```

The gate is purely on this result data shape — **not** on template source, repoUrl, version, or
published status; that metadata isn't even passed in. layout.json is still loaded and applied
either way; only the *edit* affordance is gated. Getting the button on an ungrouped workflow means
adding a real grouper — a data-model change, not a tweak.

## `groupbykey` — zipping keyed iterables

Use when two or more keyed iterables (each from `split_groups` or a `mapvalues` chain over it)
must be paired back together by matching composite-filter keys:

```
in : [[(K_a, v0_a), (K_b, v0_b)],      # iterable 0
      [(K_a, v1_a), (K_b, v1_b)]]     # iterable 1
out: [(K_a, [v0_a, v1_a]), (K_b, [v0_b, v1_b])]
```

Order is positional; keys are CompositeFilter tuples and must match exactly across inputs.

**Consumer pattern A — multi-argname `mapvalues`** (downstream task takes separate params):

```yaml
- {id: zipped_layers, task: groupbykey,
   partial: {iterables: ["${{ workflow.boundary_layer.return }}",     # → geo_layers (pos 0)
                         "${{ workflow.tile_layers.return }}"]}}      # → tile_layers (pos 1)
- {id: combined_map, task: draw_map,
   mapvalues: {argnames: [geo_layers, tile_layers],                   # order matches iterables
               argvalues: "${{ workflow.zipped_layers.return }}"}}
```

**Consumer pattern B — single argname** (downstream takes one list param): pass one argname; the
whole value-list arrives as that argument. The downstream signature dictates A vs B.

**`skipif` for `groupbykey`** — nested values may be SkipSentinels, so:

```yaml
  skipif:
    conditions: [any_dependency_skipped, all_keyed_iterables_are_skips]
    unpack_depth: 1
```

Without `unpack_depth: 1` the skip check inspects the outer list and misses nested sentinels.
`groupbykey` itself drops sentinel values from inputs, so a partially-skipped iterable still
produces a usable result.

**Failure modes:** `iterables: [a, b]` with `argnames: [arg_b, arg_a]` assigns values to the wrong
parameters **with no compile-time error**; zipping iterables split with *different* `groupers`
silently disappears groups (key drift). `merge_df` does not zip — it flattens ONE keyed iterable
into an indexed DataFrame; use `groupbykey` to zip, `merge_df` to flatten.

## Positive "keep" toggles

To show a checked-means-do-it toggle over skip-semantics tasks: chain `invert_bool(value=True)`
ahead and wire its return into the consumer's `skip` partial. **Unless** the consumer has its own
skip param with a terminal return (e.g. `download_event_attachments.skip_download`) — then feed
the toggle straight in and drop `maybe_skip_df` entirely. Keep `maybe_skip_df` only where the
return (or sentinel) feeds downstream tasks.
