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
- Creates [an interactive chart / a map / a table / files …] on a dashboard
```

Title = the workflow's display name (spec `metadata.name` when present, else the repo name in
title case). Bold the data-source product name. Bullets come from the spec's task chain, in order.

## 2. Prerequisites

```markdown
## Prerequisites

Before using this workflow, you need:

1. **Ecoscope Desktop** installed on your computer            ← Desktop-installed workflows
   - If you haven't installed it yet, please follow the installation instructions for Ecoscope Desktop
   — or, for a catalog workflow —
1. **Access to Ecoscope** — this workflow is available from the workflow catalog

2. **[EarthRanger | SMART | Google Earth Engine] Data Source** configured in Ecoscope
   - You must have already set up a connection to your [product] [server / account]
   - Your data source should be configured with proper authentication credentials
   - You'll need to know the name of your configured data source (e.g., "[a connection name from the cases]")

3. **[The data this workflow reads]** in [product]
   - [Patrols / events of the types you want / a subject group / a spatial feature group / an image collection …]
   - [Where to find their names in the product's admin site — see the URLs in style-guide.md]
```

Three items in this order. Item 1 follows the platform from the skill's § 0 — Desktop is
**not** assumed. Item 2's product comes from the spec's connection task (`connections.md` §
Connection types and fields) — EarthRanger is **not** assumed. Item 3 lists what the
connection-fed dropdowns and required inputs need to exist server-side — one bullet each.

## 3. Installation

**Desktop-installed workflows only.**

```markdown
## Installation

These steps are for Ecoscope Desktop.

1. Select "Workflow Templates" tab
2. Click "+ Add Template"
3. Copy and paste this URL https://github.com/[org]/[repo] and wait for the workflow template to be downloaded and initialized
4. The template will now appear in your available template list
```

Four steps, exact UI wording, URL from `git remote get-url origin` in https form without `.git`.
A catalog workflow gets instead:

```markdown
## Installation

No installation is needed — open the workflow catalog in Ecoscope and choose **[Workflow Title]**.
```

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
- `(required)` = the form will not submit without it (a scalar in the schema's `required`
  list with no default) or the workflow cannot run without it (then state the default);
  arrays and objects that submit empty are `(optional)` and follow their description.

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
- **File formats**: [CSV, Parquet / GeoParquet — the ones the filetypes field offers]
- **Opens in**: Microsoft Excel, Google Sheets (CSV), Python/R (Parquet)
- **Contents**: [what rows are]
  - `[column]`: [meaning]            ← columns read from the run's output file or the fixture

### Visual Outputs (Dashboard)

The workflow creates an interactive dashboard with [N] main visualization(s):

#### [Widget title, as in result.json]
- **Format**: Interactive [bar/line chart | map | table | value]
- **How it is calculated**: [the method in one plain sentence — e.g. "Home ranges are estimated
  with a Brownian Bridge Movement Model (BBMM) from each subject's track"; "Density is the time
  each patrol spent in every grid cell"; omit for a plain count or table]
- **Features**:
  - X-axis: … / Layers: … / Columns: …
  - [Legend, hover, labels — what the base run actually shows]

If you configured **Group Data** groupers, the dashboard gains a view selector — one [chart/map] per group.
```

Widgets = `result.views` of the base run (title and `widget_type`), in `layout.json` order; the
grouped-views sentence only when the form has groupers. Describe what the base run rendered, not
what the task could render. The method line comes from the spec's task and its parameters
(`method: bbmm`, a kernel, a weighting) — the algorithm is the one thing a user cannot see on
the dashboard and must be told.

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
```

**One example**: the `base` case ("the workflow's default setup, submitted as-is") — a complete
configuration with values verbatim from the case and what the dashboard then shows. Other
cases are not examples; the Configuration Guide already explains the branches.

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

Only issues **specific to this workflow**, as few as that is — no minimum, no generic
connection or performance boilerplate. Candidates: a form constraint that blocks a submission or
a run (from the schema's descriptions and `oneOf` rules), an input whose name must match the
server exactly, an output that is empty when a filter excludes everything. The list is proposed
in the skill's § 2 and the user prunes it before it is written.
