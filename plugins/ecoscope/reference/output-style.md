# Output styling conventions

Defaults for maps, charts, tables, and color mapping. Pipeline wiring is in
[patterns.md](patterns.md).

## Contents
- Color mapping
- Maps (EcoMap)
- Charts (EcoPlot)
- Tables
- Dashboard layout (`layout.json`)

## Color mapping

Applied via `apply_color_map`, which takes either a **list of hex colors** or a **matplotlib
colormap name**. Default to the EarthRanger design-system scales below — the Ai2 design system
names Ecoscope as part of the EarthRanger platform, so these are the brand-correct defaults, and
they are specified as identical in light and dark mode.

**Categorical** — stations, species, patrol types, event types:

```yaml
colormap: ["#3e35a3", "#488a00", "#00958f", "#b62879", "#c6880c",
           "#00d0c8", "#78d811", "#5c4fe7", "#f4db20", "#ed3ea2"]
```

**Tracks** — trajectory/polyline layers, where each subject gets its own line:

```yaml
colormap: ["#3e35a3", "#b62879", "#ff803e", "#ed3ea2", "#3089ff",
           "#8c1700", "#a100cb", "#004e26", "#002960", "#f23b0e"]
```

**Sequential** — ordered or binned values (a classified column, a density bucket):

```yaml
colormap: ["#f4db20", "#ffb700", "#ed3ea2", "#a100cb",
           "#5c4fe7", "#0056c7", "#00882e", "#78d811"]
```

Use each scale **in order** — the design system requires it, and the list form honors it
(`apply_color_map` assigns `colors[i % len(colors)]` to the i-th distinct value). Don't skip
entries or splice in brand colors; the scales are built to stay distinguishable and accessible
as ordered sets. Note the i-th distinct value is ordered by **first appearance**, not sorted —
sort the df before the colormap task if you need colors stable across runs.

Pin scales with `partial`, never as a form field: the list form is `SkipJsonSchema` on the task,
so it renders no config-form control.

**Matplotlib names remain the fallback for two cases:**

- **More than 10 categories** (8 for sequential) — `"tab20b"` gives 20 distinct colors where a
  hex list would start repeating.
- **Continuous numeric columns** — a string colormap over a numeric column interpolates across
  the ramp, whereas a list is always discrete. `"viridis"` stays the default for a true gradient.

Values copied from [allenai/design](https://github.com/allenai/design/blob/main/earthranger/DESIGN.md)
@ `713d6cd`, 2026-08-21 (§ Data Visualization — Categorical / Tracks / Sequential).

The output column contains RGBA tuples; downstream layers reference it via `color_column` /
`fill_color_column`, and legends pair `label_column` (the category) with the same `color_column`.

Standard flow: classify (`apply_color_map`) → layer (`create_*_layer` referencing the color
column) → legend (same df) → `draw_ecomap` assembling layers + basemaps + chrome.

## Maps (EcoMap)

**Tile layer presets**: OpenStreetMap, ROADMAP (ArcGIS streets), SATELLITE (ArcGIS imagery),
TERRAIN (ArcGIS topo), LANDDX, USGS HILLSHADE. Default base maps from `set_base_maps`:
TERRAIN + SATELLITE at `opacity: 0.5`.

**Point layer defaults:**

```yaml
layer_style: {get_radius: 5.0, radius_units: pixels, fill_color_column: my_colormap,
              opacity: 1, pickable: true}
legend: {label_column: category_column, color_column: my_colormap}
tooltip_columns: ["Name", "time"]
```

**Polyline layer defaults** (note the different param names — `color_column`/`get_width`, not
`fill_color_column`/`get_radius`):

```yaml
layer_style: {get_width: 3, width_units: pixels, color_column: my_colormap,
              cap_rounded: true, opacity: 1, pickable: true}
tooltip_columns: ["Start Time", "Duration (s)", "Speed (kph)"]
```

**Polygon layer defaults:**

```yaml
layer_style: {get_fill_color: null, get_line_width: 1, filled: true, stroked: false,
              opacity: 1, pickable: true}
```

**Map chrome:**

```yaml
north_arrow_style: {placement: top-left}
legend_style: {title: "Legend Title", placement: bottom-right}
static: false
max_zoom: 20
```

## Charts (EcoPlot)

```yaml
plot_style:   {mode: lines+markers, xperiodalignment: start, xperiod: M1}
layout_style: {showlegend: true, hovermode: closest, title: "Chart Title", title_x: 0.5,
               xaxis: {title: "X Label"}, yaxis: {title: "Y Label"}}
```

Bar charts: `bargap: 0.1`, `bargroupgap: 0.05`. Time-series tick format default `"%b-%Y"`.

## Tables

```yaml
table_config: {enable_sorting: true, enable_filtering: false, enable_download: false,
               hide_header: false}
```

- **No index columns** — only meaningful data columns.
- `hide_header: true` when the widget title provides the context.
- `enable_download: true` for export workflows; `enable_filtering: true` for drill-down tables.
- Rendered with ag-grid (Alpine theme), auto-sized to cell contents.

## Dashboard layout (`layout.json`)

Hand-authored at the repo root; a JSON array with one react-grid-layout entry per widget in
`gather_dashboard.widgets`. Schema and the Desktop "Edit Layout" gate are in
[patterns.md](patterns.md); these are the sizing/placement conventions.

```json
[
  {"i": "0", "x": 0, "y": 0,  "w": 2,  "h": 3,  "minW": 2, "minH": 3,  "widget_id": 0, "static": false},
  {"i": "1", "x": 0, "y": 3,  "w": 5,  "h": 10, "minW": 5, "minH": 10, "widget_id": 1, "static": false},
  {"i": "2", "x": 5, "y": 3,  "w": 5,  "h": 10, "minW": 4, "minH": 8,  "widget_id": 2, "static": false}
]
```

- **10-column grid** (`cols={10}` in ecoscope-web's `WorkflowResultsGridLayout.tsx`): keep
  `x + w ≤ 10` — wider entries are clamped, not errors. Rows are 28px; `y` is in row units,
  stack by adding the previous row's `h`. Layout is **vertically compacted** (gaps in `y` close
  up; `event_details` compacts horizontally instead), so `y` sets order, not absolute position.
- **`i`** is the entry key (`"0"`, `"1"`, … as strings, unique); **`widget_id`** is the widget's
  0-indexed position in `gather_dashboard.widgets`. They usually coincide, but `i` may follow
  placement order while `widget_id` points at the widget — don't assume they match.
- **`static: false`** always; every entry carries all nine keys.
- **Sizes by widget type:**

  | Widget | `w` × `h` | `minW` × `minH` | Placement |
  |---|---|---|---|
  | Stat / single value | 2–3 × 3 | 2 × 3 | a row across the top (`y: 0`, `x` stepping by `w`) |
  | Map, paired | 5 × 10 | 5 × 10 | two per row at `x: 0` and `x: 5` |
  | Map, full-width | 10 × 12–16 | 5–6 × 8–10 | alone on its row |
  | Chart | 5 × 10 | 4 × 8 | paired with a map or another chart |
  | Table | 10–12 × 12 | 6 × 10 | alone on its row |

- Order top-to-bottom: stat tiles → maps → charts/tables. Single-widget workflows use one
  full-width entry.
- **Every widget needs an entry.** The renderer iterates the layout, not the widgets — a widget
  with no entry is not drawn, and `[]` renders a dashboard with zero tiles (mt-patrols and
  mt-wildlife ship `[]` and are affected).
- Desktop preview needs the workflow repo's own `layout.json`, not the one from `result.json`
  ([preview-dashboard.md](preview-dashboard.md)).
