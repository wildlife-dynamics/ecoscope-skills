# Style guide — voice, formatting and terminology for workflow user guides

## Voice
- Written for someone who runs the workflow in Ecoscope Desktop and has never seen `spec.yaml`:
  no task names, no parameter keys, no file paths inside the package, no compile talk.
- Active voice, short sentences, one idea per bullet. Explain a term the first time it appears
  ("patrol type — the category assigned to a patrol in EarthRanger").
- Say what a setting *changes on the dashboard*, not how it is implemented.

## Formatting
- **Bold**: field and card names exactly as the form titles them (`**Patrol Status**`), product
  names (**EarthRanger**, **Ecoscope Desktop**), file-format names, the step labels in numbered
  procedures.
- `Code`: example values, defaults, option labels when quoted as values, column names, file names,
  timestamps, connection names.
- *Italics*: sparingly, for emphasis only.
- Headings: `#` title, `##` the eight sections, `###` Basic/Advanced and the results subsections,
  `####` one per card, widget, example or issue.

## Terminology
| Use | Not |
|---|---|
| workflow | process, pipeline, job |
| configuration, setting | parameter, param, argument |
| data source | connection, client, server |
| run | execution, invocation |
| dashboard, chart, map, table | widget, figure, plot output |
| time range (Since / Until / Timezone) | date range, window, period (unless it is the form's word) |
| subject group, patrol type, event type, spatial feature group | EarthRanger's own nouns, unchanged |

## Recurring patterns
- **Time range example** — the form's format, from the case:
  `Since: 2015-01-10T00:00:00`, `Until: 2015-02-28T23:59:59`,
  `Timezone: UTC (UTC+00:00)` or `Africa/Nairobi (UTC+03:00)`.
- **Grouper and interval options** are quoted by the label the form shows (`Month`, `Year`),
  never by the format code behind it.
- **File formats**, in this order with these blurbs: **CSV** (quick review in spreadsheets),
  **Parquet / GeoParquet** (large datasets, programmatic analysis). GPKG is not offered.
- **EarthRanger admin locations**: patrol types — **Activity → Patrol Types**; event types —
  **Activity → Event Types** (`https://<your-site>.pamdas.org/admin/activity/eventtype/`);
  subject groups — `https://<your-site>.pamdas.org/admin/observations/subjectgroup/`; spatial
  feature groups — **Mapping → Spatial Feature Group Profiles**.
- **Notes and warnings** sit inline under the field they concern:
  `- Note: This must match exactly, including capitalization`.

## Examples
- Values come from `test-cases.yaml`; realistic dates, never `YYYY-MM-DD` placeholders.
- Complete configurations — a reader should be able to reproduce the run from the example alone.
- Every example ends with what the dashboard will show.
- Connection names, patrol-type and event-type slugs from the cases are org constants and fine;
  nothing from a real data pull, ever.

## Quality checklist
- [ ] Eight `##` sections, in order, fixed wording where the templates fix it
- [ ] Every visible card, field and widget from the inventory named as a bold label or heading
      (`form-inventory.py --check` exit 0)
- [ ] Defaults and options quoted by their labels; `(required)`/`(optional)` per the schema
- [ ] No hidden field, `partial:`-bound param, task name or spec key mentioned
- [ ] Prerequisites name the platform (Desktop or catalog) and the data-source product the
      spec connects to — neither assumed
- [ ] The single example is the base case, values verbatim
- [ ] Results section describes what the base run rendered, in layout order, and names the
      method behind each analytical output
- [ ] Troubleshooting is workflow-specific only, as reviewed by the user
- [ ] Installation present only for a Desktop workflow; its URL matches `origin`
- [ ] In gate mode, `git diff` touches only the flagged sections
