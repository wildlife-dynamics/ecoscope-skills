# Tasks — anatomy, annotations, and the tasks every workflow uses

How registered functions are written and how their annotations drive the config form. Discovery
mechanics (entry points, re-exports, collisions) live in [task-discovery.md](task-discovery.md);
authoring gotchas for specific tasks in [task-pitfalls.md](task-pitfalls.md).

## Contents
- Task anatomy
- Annotations that drive the form
- The io tag and mockability
- Skip handling inside tasks
- Task-level form-schema customization
- The tasks nearly every workflow uses (workflow_details, time range, groupers, widgets, dashboard)
- Custom task package recipe

## Task anatomy

```python
from typing import Annotated, cast
import pandas as pd
from pydantic import Field
from wt_registry import register
from ecoscope.platform.annotations import AnyDataFrame

@register()
def filter_rows(
    df: Annotated[AnyDataFrame, Field(description="Input data.")],
    column: Annotated[str, Field(description="Column to filter.")],
    value: Annotated[str, Field(description="Value to keep.")] = "",
) -> AnyDataFrame:
    """Filter DataFrame rows where column equals value."""
    return cast(AnyDataFrame, df[df[column] == value])
```

- `register(*, title=None, description=None, tags=None, deprecated=False, deprecation_message=None)`.
  Omitted `title` auto-derives from the function name (`get_patrol_observations` →
  `"Get Patrol Observations"`).
- **Every parameter and the return must be annotated** — the validator rejects untyped params,
  missing return annotations, async functions, and classes.
- Export the function from its category `__init__.py` (and `__all__`), or it becomes reachable
  only at its private module path ([task-discovery.md](task-discovery.md)).
- Cast returns for the type checker (`cast(AnyDataFrame, result)`).

## Annotations that drive the form

- `Annotated[T, Field(...)]` drives the form. Pydantic drops `Field` metadata inside `Annotated`;
  the registry's schema generator works around that by copying `default`/`description`/`title`/
  `json_schema_extra` onto the property — and **deleting the property entirely when
  `Field(exclude=True)` is set**. Generation runs in serialization mode (required for
  AdvancedFields to be excludable inside nested models).
- `Field(exclude=True)` = not user-configurable, wire-only via `partial`. Used e.g. on widget
  `view` params and on Literal discriminators you want out of the form while keeping runtime union
  discrimination.
- `AdvancedField(...)` (from `ecoscope.platform.annotations`) sets
  `json_schema_extra={"ecoscope:advanced": True}` and **requires a default**. Renders inside the
  card's "Advanced Configurations" accordion — but only on a card's direct task args; it is
  ignored inside nested objects and array rows ([rjsf.md](rjsf.md)).
- `SkipJsonSchema[None]` on `X | None` = "optional, but don't offer null in the form". A field
  typed `SkipJsonSchema[...]` is **excluded from the Params schema entirely**, so it cannot be set
  from `test-cases.yaml` (pydantic silently drops it as extra).
- DataFrame aliases (`AnyDataFrame`, `AnyGeoDataFrame`, `EmptyDataFrame`, `…OrEmpty`) are pandera
  DataFrameModels serialized to a placeholder in JSON schema — they affect schema generation only,
  not validation. Named schemas live in `ecoscope.platform.schemas`.
- Escalation ladder for form control: `Field` → `AdvancedField` → `json_schema_extra` callable
  (sparingly). Per-workflow tweaks belong in spec `rjsf-overrides` instead ([rjsf.md](rjsf.md)).

## The io tag and mockability

`@register(tags=["io"])` has exactly one effect: under mock-io the task is replaced by a canned
magicmock returning a packaged fixture ([testing.md](testing.md)). The io tag is what makes a task
mockable — data-fetching tasks carry it; `persist_*` deliberately does not (its writes are part of
the observable output).

## Skip handling inside tasks

- `SkipSentinel` is the skip marker; generated code chains
  `.set_task_instance_id(id).partial(...).validate().handle_errors().skipif(conditions, unpack_depth).call()`
  (all methods return new instances; `.handle_errors()` wraps exceptions as `TaskInstanceError`
  carrying the instance id — which is why runtime errors name the task instance).
- `SkippedDependencyFallback(fn)` converts an upstream sentinel into something usable — every
  widget's `data` param falls back to None; `groupbykey` drops sentinels from its inputs.

## Task-level form-schema customization

These change the task for ALL workflows (vs per-workflow `rjsf-overrides`):

- **Hide discriminators**: `Annotated[Literal["x"], Field(exclude=True)] = "x"` on BaseModel
  branches — union discrimination still works at runtime, field leaves the schema.
- **Variant titles in anyOf dropdowns**: `model_config = ConfigDict(json_schema_extra={"title": "Display Name"})`.
- **Rename labels**: `Field(title="...")`; hide a label visually with `title=" "` (single space).
- **Enum display labels must be fixed task-side, not spec-side.** A `Literal[...]` param emits
  `enum`, and rjsf prefers `enum` over `oneOf` — a spec-side `oneOf: [{const, title}]` override is
  silently ignored and raw values render. Fix with a `json_schema_extra` callable that pops `enum`
  and sets the labeled `oneOf`. (Plain `str` params have no enum, so spec-side `oneOf` works
  there.)
- **Arbitrary schema edits**: `Field(json_schema_extra=callable)` mutating the schema dict.

## The tasks nearly every workflow uses

- **`set_workflow_details`** — its instance **`id` must be exactly `workflow_details`**; Desktop
  and Web look for this specific id, and omitting it yields the front-end error
  `Could not read properties of undefined (reading 'name')`.
- **`set_time_range(since, until, timezone, time_format)`** → TimeRange;
  `get_timezone_from_time_range` extracts the tz for downstream conversion.
- **Connections** — `set_er_connection` / `set_smart_connection` / `set_gee_connection` return the
  connection *name* as a plain `str`; see [connections.md](connections.md) (including why the UI
  picker comes from the **parameter** type, not the return).
- **Groupers** — `set_groupers` (hides its field with `title: " "`), `split_groups`,
  `groupbykey`, `merge_df`. Grouper types: `ValueGrouper` (UI "Category"), `TemporalGrouper`
  (UI "Time"; temporal_index ∈ Year/Month/YearMonth/DayOfTheYear/DayOfTheMonth/Date/DayOfTheWeek/
  Hour), `SpatialGrouper` (UI "Spatial", EarthRanger feature groups only — needs the resolver
  chain in [patterns.md](patterns.md)). Each hand-writes its RJSF schema via
  `__get_pydantic_json_schema__`.
- **Widgets** — all share `(title: str, data: <T>, view: CompositeFilter | None) -> WidgetSingleView`:

  | Task | data type | widget_type |
  |---|---|---|
  | `create_map_widget_single_view` | precomputed HTML | `map` |
  | `create_map_v2_widget_single_view` | deck.gl JSON | `map_v2` |
  | `create_plot_widget_single_view` | precomputed HTML | `graph` |
  | `create_text_widget_single_view` | text | `text` |
  | `create_single_value_widget_single_view` | Quantity/number | `stat` |
  | `create_table_widget_single_view` | precomputed HTML | `table` |

  Plus `merge_widget_views` (merges on title + widget_type) and
  `create_files_single_view` / `merge_file_views` for OutputFiles workflows.
  **Widget tasks take `skipif: {conditions: [never]}`** so placeholders always exist.
- **`gather_dashboard`** — the mandatory terminal node (every workflow must end with it, even
  without a user-facing dashboard; `gather_output_files` is the terminal node for download-style
  workflows instead). Takes `details`, `widgets`, `groupers`, `time_range`, optional `warning`,
  `files`. Runtime invariant: **all grouped widgets must have the same view keys** (it back-fills
  null views then asserts alignment). Its default `skipif` includes `any_dependency_skipped`, so
  one failed upstream task can skip the whole dashboard — surfacing as an app 500
  "`result.json` not found".

## Custom task package recipe

Minimal greenfield package: `uv init --lib my-tasks`, add `wt-registry` to dependencies, declare
the entry point

```toml
[project.entry-points."wt_registry"]
my_tasks = "my_tasks"
```

then reference it from `spec.yaml` with an absolute `path:` + `editable: true` (dev only). Verify
discovery with `uv run wt-registry --package my_tasks --format pretty` before compiling.
