---
briefId: chrome.sidebar-quick-nav
schemaVersion: 1
kind: chrome
title: Sidebar Quick-Nav Strip + Search + Empty Category
coversPreviews:
  - storyRef: { group: "Task App / Pages", name: "Inbox", kind: page, index: 0 }
    backends: [web]
captureViewports:
  - { width: 1440, height: 900, label: "laptop" }
  - { width: 1920, height: 1080, label: "wide" }
reviewerSchemaVersion: 1
scoringDimensions:
  - { id: chrome, label: "Editor Chrome", weight: 1.0, scale: { min: 1, max: 10 } }
relatedBriefs: [chrome.shell-wide, chrome.shell-laptop]
---


## What You're Reviewing

The post-M-EVP-9 sidebar header: the search input + the five-icon
quick-navigation strip. This brief focuses specifically on the
sidebar interactions:

- The five icons in the strip with one selected (active).
- The real-time search filter narrowing the visible tree.
- An empty category (the Guidelines / User Journeys icon, whichever
  has zero stories in the demo workspace) appearing disabled.

The screenshot captures the **sidebar after** the screenshot tool:

1. Types `spacing` into the search field, waits for the tree to
   filter (only the Foundations / Spacing & Radii story should
   remain visible), then clears the search.
2. Clicks the Components quick-nav icon — its `aria-pressed` flips
   to `true` and the active-category styling becomes visible.
3. Leaves the search empty so the active-category visual is the
   focal point.

Captured by `editor-screenshot.mjs` view `sidebar-quick-nav` at
viewport `laptop`: file `screenshots/sidebar-quick-nav-laptop.png`.
A `wide` variant is also captured for completeness:
`screenshots/sidebar-quick-nav-wide.png`.

## Design Goals

- The quick-nav strip should feel like a visual index across the
  five canonical design-system categories — not a generic toolbar.
- Active category: clearly differentiated background colour /
  accent border. Disabled categories: clearly muted (≥ 40 % opacity
  drop OR a grey colour shift), with a `not-allowed` cursor on
  hover (verify in DOM if not on screenshot).
- Empty-category visual must be unambiguous: a reviewer should be
  able to tell at a glance that the disabled icon is non-clickable.
- Search input + quick-nav strip form a visually unified header;
  hairline divider beneath them separates the header from the
  story tree body.

## Color Expectations

- Strip background: same as sidebar surface OR one shade lighter.
- Active icon: accent colour fill OR accent-bordered chip; the
  active state must use the same accent the chrome bar's backend
  chip uses (single accent across the editor).
- Disabled icon: muted grey, low contrast (~ 30–40 % opacity of the
  base icon colour).
- 1 px `borderFaint` hairline beneath the strip separating it from
  the story tree.

## What is Expected on the Screenshot

### Strip header (top of sidebar)

- Exactly one `[data-sidebar-search="true"]` input above the strip
  with the placeholder `Search stories…`. The input must be empty
  (the screenshot setup clears the search after the typed-then-
  cleared probe).
- Exactly one `[data-sidebar-quicknav="true"]` strip below the
  search.
- The strip contains exactly **five icons**. In document order
  left-to-right, their `data-category-kind` attributes must be:
  `skFoundation`, `skComponent`, `skPage`, `skFlow`, `skGuideline`.
- Each icon carries `role="button"` and an `aria-label` of
  `Focus <Label> category` (`Foundations`, `Components`, `Pages`,
  `User Journeys`, `Guidelines`).

### Active category

- The **Components** icon (data-category-kind="skComponent") must
  appear visually active: `aria-pressed="true"` and a distinct
  background / border colour relative to its peers.
- The Components section in the story tree below is **expanded**
  (chevron pointing down); other sections are collapsed by the
  active-category handler.

### Disabled category

- At least one quick-nav icon corresponds to a category with zero
  stories in the demo workspace and must carry
  `aria-disabled="true"`, `tabindex="-1"`, and visibly reduced
  opacity (estimate ≤ 50 %).
- For the seeded demo workspace (`task_app` + `settings_app`) the
  most likely empty category is **User Journeys** (skFlow) — verify
  by inspecting `aria-disabled` directly.

### Story tree body

- The Components section is expanded showing groups like `TaskRow`
  and `TaskList` underneath.
- Other sections appear collapsed (chevron pointing right) per the
  active-category-selects-and-collapses-siblings behaviour.

## What to Evaluate

1. **Active-state visual clarity** — can you tell at a glance which
   category is active without reading the DOM?
2. **Disabled-state clarity** — is the disabled icon unambiguous,
   or does it look like an inactive-but-clickable peer?
3. **Hit-target spacing** — icons should be ≥ 24 × 24 px with
   ≥ 4 px gap between adjacent icons.
4. **Alignment** — five icons evenly distributed across the strip
   width (`justify-content: space-around`); first / last icon not
   flush against the panel edge.
5. **Search input + strip cohesion** — does the search + strip
   read as one header unit, or do they feel like two stacked
   panels?
6. **Section behaviour** — does the Components section's expanded
   state line up with the active-category selection? Are other
   sections clearly collapsed?
7. **Typography / iconography** — five icons share the same visual
   weight and stroke thickness; no icon looks heavier or lighter
   than the rest.

## How to Report

- Keep under 250 words.
- **First line:** `Expected elements: present` OR
  `Expected elements: missing-<X>` / `replaced-by-<Y>`.
- Lead with one-sentence aesthetic impression.
- List specific issues with selectors / data-category-kind values.
- End with **1–2 highest-priority fixes**.
- Rate 1–10.
- Call out specifically whether the **active** and **disabled**
  states are visually unambiguous — that is the M-EVP-9
  load-bearing affordance.
