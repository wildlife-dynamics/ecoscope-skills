# Section templates — the fleet's 8-section user guide

The shape every published workflow README shares (verified against the current fleet: patrol-chart,
patrol-track-density-map, wt-download-patrols, event-sum-map). Headings, numbering and the fixed
wording below are what users already know from the other workflows — keep them verbatim; fill the
brackets from the inventory, the base run and the cases, never from memory. Card and field names in
brackets are the **compiled titles** the inventory printed.

## Contents
1. Introduction
2. Prerequisites
3. Installation
4. Configuration Guide
5. Running the Workflow
6. Understanding Your Results
7. Common Use Cases & Examples
8. Troubleshooting

## 1. Introduction

```markdown
# [Workflow Title] Workflow

## Introduction

This workflow helps you to [primary purpose, one sentence]. [One sentence on what it turns the data into.]

**What this workflow does:**
- Downloads [patrols / events / observations / imagery] from **[EarthRanger | SMART | Google Earth Engine]**
- [Calculates / summarizes …]   ← one bullet per transformation stage in the spec
- [Optionally splits / groups …] ← only when the form has groupers or a comparison mode
- Creates [an interactive chart / a map / a table / files …] on a dashboard

**Who should use this:**
- Conservation managers monitoring [domain]
- Researchers analyzing [type of data]
- Anyone needing to [visualize / export] [data] stored in [source]
```

Title = the workflow's display name (spec `metadata.name` when present, else the repo name in
title case). Bold the data-source product name. Bullets come from the spec's task chain, in order.

## 2. Prerequisites

```markdown
## Prerequisites

Before using this workflow, you need:

1. **Ecoscope Desktop** installed on your computer
   - If you haven't installed it yet, please follow the installation instructions for Ecoscope Desktop

2. **[EarthRanger] Data Source** configured in Ecoscope Desktop
   - You must have already set up a connection to your [EarthRanger] server
   - Your data source should be configured with proper authentication credentials
   - You'll need to know the name of your configured data source (e.g., "[a connection name from the cases]")

3. **[The data this workflow reads]** in [EarthRanger]
   - [Patrols / events of the types you want / a subject group / a spatial feature group …]
   - [Where to find their names in the EarthRanger admin site — see the URLs in style-guide.md]
```

Always three items in this order. Item 2's product comes from the spec's connection task
(`connections.md` § Connection types and fields). Item 3 lists what the connection-fed dropdowns
(`EarthRangerEnumResolver` fields) and required inputs need to exist server-side — one bullet each.

## 3. Installation

```markdown
## Installation

1. Select "Workflow Templates" tab
2. Click "+ Add Template"
3. Copy and paste this URL https://github.com/[org]/[repo] and wait for the workflow template to be downloaded and initialized
4. The template will now appear in your available template list
```

Four steps, exact UI wording, URL from `git remote get-url origin` in https form without `.git`.

## 4. Configuration Guide

```markdown
## Configuration Guide

### Basic Configuration

#### [N]. [Card title]
[One sentence on what this card decides.]

- **[Field title]** ([required|optional]): [What it does, in the user's terms]
  - Example: `[value from a case]`
  - Default: `[default, by label]`          ← when the field has one
  - Options: [labels, comma-separated]     ← for choice fields
  - Note: [a constraint or warning the schema description carries]

### Advanced Configuration

These optional settings provide additional control over your workflow. In the app they sit under
the "Advanced Configurations" accordion of their card.

#### [Field or group] ([Card title])
[One sentence on what it controls.]

- **[Field title]**: [What it does]
  - Default: `[default]`
```

- One numbered `####` per card under Basic Configuration, **numbered in the form's order**
  (`ui:order`) so "4. Patrol and Event Types" is the fourth card the user scrolls to. Basic
  lists the card's non-advanced fields; a card whose fields are all `ADVANCED` keeps its number
  and one sentence ("All settings here sit under Advanced Configurations — see below"). The
  Advanced Configuration section collects the `ADVANCED` fields under `#### [Field or group]
  ([Card])` headings, the fleet's shape. Invisible wrapper objects (title `""`/`" "`) are never
  headings — their children belong directly under the card.
- Conditional fields ("when Chart Type = Line") go as an indented group under the field that
  reveals them, with the condition stated ("For **Line** charts:").
- Array-of-rows fields (metrics, groupers) list the row types as sub-bullets with a one-line
  meaning each; connection-fed dropdowns say where the values come from in EarthRanger.
- `(required)` = in the schema's `required` list with no default; everything else `(optional)`.

## 5. Running the Workflow

```markdown
## Running the Workflow

Once you've configured all the settings:

1. **Review your configuration**
   - Double-check your time range, data source, and [the workflow's key input]

2. **Save and run**
   - Click the "Submit" and the workflow will show up in "My Workflows" table button in Ecoscope Desktop
   - Click on "Run" and the workflow will begin processing

3. **Monitor progress and wait for completion**
   - You'll see status updates as the workflow runs
   - Processing time depends on:
     - The size of your date range
     - [Number of patrols / events / subjects in the period]
     - [Any extra fetch the options imply, e.g. spatial regions]
   - The workflow completes with status "Success" or "Failed"
```

Three steps, fixed wording; only the bracketed bullets change.

## 6. Understanding Your Results

```markdown
## Understanding Your Results

After the workflow completes successfully, open the run to view its dashboard.

### Data Outputs                    ← only when the spec persists files (a persist / filetypes task)

Your [data] will be saved in the format(s) you selected:

#### [Output name]
- **File formats**: [CSV, Parquet, GeoParquet, GPKG — the ones the filetypes field offers]
- **Opens in**: Microsoft Excel, Google Sheets (CSV), Python/R (Parquet), QGIS/ArcGIS (GPKG)
- **Contents**: [what rows are]
  - `[column]`: [meaning]            ← columns read from the run's output file or the fixture

### Visual Outputs (Dashboard)

The workflow creates an interactive dashboard with [N] main visualization(s):

#### [Widget title, as in result.json]
- **Format**: Interactive [bar/line chart | map | table | value]
- **Features**:
  - X-axis: … / Layers: … / Columns: …
  - [Legend, hover, labels — what the base run actually shows]

If you configured **Group Data** groupers, the dashboard gains a view selector — one [chart/map] per group.
```

Widgets = `result.views` of the base run (title and `widget_type`), in `layout.json` order; the
grouped-views sentence only when the form has groupers. Describe what the base run rendered, not
what the task could render.

## 7. Common Use Cases & Examples

```markdown
## Common Use Cases & Examples

Here are some typical scenarios and how to configure the workflow for each:

### Example 1: [Use case name]
**Goal**: [What the user wants to see.]

**Configuration**:
- **Time Range**:
  - Since: `[case since]`
  - Until: `[case until]`
  - Timezone: `[case timezone label]`
- **[Card]**: [field: value; …]

**Result**:
- [What the dashboard shows for this configuration]

---
```

Example 1 is the `base` case ("the workflow's default setup, submitted as-is"); the rest map one
case each to a user question, covering the form's branches (a grouper, a comparison mode, a
filter). 3–5 examples, `---` between them, complete configurations, values verbatim from the case.

## 8. Troubleshooting

```markdown
## Troubleshooting

### Common Issues and Solutions

#### [Issue name]
**Problem**: [What the user sees.]

**Solutions**:
- [Actionable step]
- [Actionable step]
```

Five or more, always including: *Workflow fails to start* (connection / credentials), *The
[chart/map] is empty or the run reports no data* (time range, status filter, type names, filters
excluding everything — the silently-empty run), one per form constraint that blocks a submission or
a run (from the schema's descriptions and `oneOf` rules), one per connection-fed input whose name
must match EarthRanger exactly, and *Workflow runs very slowly* (narrow the range; the first run
after installing a template warms up the environment). Reference the EarthRanger admin pages where
the user verifies names.
