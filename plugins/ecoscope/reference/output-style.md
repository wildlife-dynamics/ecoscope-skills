# Output styling conventions

Defaults for maps, charts, tables, and color mapping. Pipeline wiring is in
[patterns.md](patterns.md).

## Contents
- Color mapping
- Maps (EcoMap)
- Charts (EcoPlot)
- Tables

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
