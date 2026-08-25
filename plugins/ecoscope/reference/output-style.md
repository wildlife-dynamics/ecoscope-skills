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

Applied via `apply_color_map` using **matplotlib colormap names**:

- `"Dark2"` — categorical, up to 8 distinct colors (stations, species, patrol types)
- `"tab20b"` — categorical with more groups (up to 20)
- `"viridis"` — continuous/sequential

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
  ([preview-desktop.md](preview-desktop.md)).
