---
name: Sleep Dashboard
description: A calm, private macOS observatory for examining personal sleep patterns.
---

<!-- SEED: established with the user before implementation; re-run $impeccable document once there's code to capture the actual tokens and components. -->

# Design System: Sleep Dashboard

## Overview

**Creative North Star: "The Private Sleep Observatory"**

Sleep Dashboard is a quiet analytical workspace that feels native to macOS. It
puts personal evidence ahead of interpretation: related time series stay aligned,
one selected date brings exact values into focus, and the interface never implies
more certainty than the imported data supports. Its distinctive gesture is
coordinated inspection, not a composite score or a decorative wellness metaphor.

Use standard macOS structure, system materials, SF typography, and familiar
interaction behavior as the visual foundation. Data occupies a continuous,
low-chrome canvas; structural regions may use material and separators when they
clarify navigation or inspection. Light and dark appearances are equivalent
expressions of one system, with matching hierarchy and chart identity.

Imagery is unnecessary: user-owned data, native symbols, and precise chart marks
are the visual content. Motion should be restrained and functional, coordinating
selection and detail updates without spectacle, and respecting reduced-motion and
reduced-transparency settings.

**Key Characteristics:**

- Native, calm, and operational rather than branded or theatrical.
- Evidence-led, with exact values available from coordinated chart selection.
- Continuous analytical surfaces instead of collections of equal-weight cards.
- Quietly privacy-forward, with local-only operation expressed as product fact.
- Fully semantic across light, dark, increased-contrast, and accessibility modes.

## Colors

Use macOS semantic colors and dynamic asset-catalog roles so hierarchy survives
every system appearance. The chart palette assigns a stable identity to each
metric, while exact light- and dark-mode values remain to be resolved during
implementation and verified for contrast.

### Primary

- **System Accent** ([to be resolved during implementation]): Primary actions,
  keyboard focus, active range state, and the shared date-selection indicator.

### Secondary

- **Duration Indigo** ([to be resolved during implementation]): Sleep-duration
  marks and their related trend treatment.
- **Bedtime Navy** ([to be resolved during implementation]): Bedtime consistency.
- **Deep-Sleep Violet** ([to be resolved during implementation]): Deep-sleep
  percentage.
- **Efficiency Blue** ([to be resolved during implementation]): Sleep efficiency.
- **Sleep-BPM Coral** ([to be resolved during implementation]): Sleeping heart rate.
- **HRV Teal** ([to be resolved during implementation]): Heart-rate variability.

These are semantic identities, not fixed swatches. Each requires coordinated
light, dark, and increased-contrast variants, plus a non-color differentiator
where series could otherwise be ambiguous.

### Neutral

- **System Canvas** ([to be resolved during implementation]): The primary data
  workspace, using the appropriate macOS background role.
- **Structural Material** ([to be resolved during implementation]): Navigation,
  toolbar, or inspection regions when material helps establish hierarchy.
- **Primary Label** ([to be resolved during implementation]): Titles, selected
  values, and high-priority data.
- **Secondary Label** ([to be resolved during implementation]): Units, context,
  ranges, and explanatory text.
- **System Separator** ([to be resolved during implementation]): Hairline structure,
  chart guides, and definition-row boundaries.

**The Dual-Appearance Rule.** Preserve semantic hierarchy and chart identity across
light and dark modes; never treat one appearance as a tinted copy of the other.

**The Never-by-Color-Alone Rule.** Selection, missingness, focus, and series meaning
must remain understandable through position, shape, label, line treatment, or
VoiceOver description in addition to hue.

## Typography

Use the macOS system type family through SwiftUI's semantic text styles. Exact
sizes, weights, and leading remain [to be resolved during implementation] against
the running app and accessibility settings.

**Character:** Neutral, legible, and numerically precise. Hierarchy comes from
system roles and disciplined weight changes, not oversized editorial display type.

### Hierarchy

- **Window and Section Titles:** Native title and headline roles for location and
  structure; concise enough to scan in a desktop workspace.
- **Metric Values:** A prominent system role with tabular numerals where aligned
  values benefit from stable widths; units remain visibly subordinate.
- **Body:** The standard readable system role for explanations, import summaries,
  and empty or error states.
- **Labels:** Secondary and caption roles for axes, units, dates, provenance, and
  definition-row keys; never reduced below comfortable macOS readability.

**The System-Type Rule.** Preserve native macOS text metrics and user scaling; do
not substitute a display face or hard-code a web-style type scale.

**The Units-Stay-Visible Rule.** Present values with their exact units and source
semantics; typographic de-emphasis must never make the unit disappear.

## Layout

Use native macOS split-view, sidebar, toolbar, and inspector conventions for
multi-region analytical workspaces. The primary analytical area should read as one
continuous canvas: related time-series align to the same temporal frame, and a
single selection state coordinates what the user sees across them. Exact pane
proportions, metric count, chart order, and first-viewport composition belong to
the relevant surface brief rather than this global system.

Prefer unboxed summary values and aligned rows over a bento grid. Use whitespace,
system grouping, and hairline separators to establish rhythm. Inspectors should
present exact values as calm definition rows with clear key-value alignment, not
as nested cards.

At narrower window sizes, protect the analytical reading path and current
selection before supplementary chrome. Resolve collapse behavior and minimum
dimensions during implementation using native SwiftUI patterns, keyboard access,
and accessibility-sized text as constraints.

**The Shared-Time Rule.** When metrics describe the same nights, align their time
axes and use one selected-date state rather than independent chart interactions.

**The Surface-Brief Rule.** Keep exact pane ratios, track counts, and toolbar
arrangements local to each surface; the global system defines behavior and
hierarchy, not one frozen screen composition.

## Elevation & Depth

Depth is quiet and structural. Prefer macOS material, tonal separation, and
hairline dividers to custom shadows. Translucency belongs only in platform chrome
where it communicates navigation or panel hierarchy; data surfaces remain clear
and stable. Exact material variants and any elevation values are [to be resolved
during implementation].

**The Structural-Material Rule.** Use material to explain containment and window
structure, never as a decorative glass effect behind every region.

**The Flat-Data Rule.** Charts and summary values rest on the analytical canvas;
they do not each receive a raised card or ambient shadow.

## Shapes

Follow native macOS control geometry and continuous corner behavior. Structural
grouping may use gently rounded surfaces consistent with the approved direction,
while data rows and chart tracks remain mostly rectilinear and aligned. Exact
radius values are [to be resolved during implementation] rather than established
as provisional tokens.

Separators are fine, quiet, and purposeful. Avoid ornamental pills, oversized
rounding, decorative blobs, and card silhouettes that make every metric appear to
be an independent object.

**The Native-Geometry Rule.** System controls keep their platform-provided shape;
custom containers should not imitate mobile cards or web-dashboard tiles.

## Do's and Don'ts

### Do:

- **Do** make aligned data patterns scannable before asking the user to inspect an
  exact night.
- **Do** use one coordinated selected-date state wherever related metrics share a
  time axis.
- **Do** render missing values as visible gaps and explain uncertainty plainly;
  never imply a measured zero.
- **Do** preserve units, date context, source semantics, keyboard focus, VoiceOver
  labels, and non-color chart differentiation.
- **Do** express privacy with factual, native language and restrained iconography:
  imports and analysis remain on the Mac.
- **Do** validate every hierarchy and chart identity independently in light, dark,
  increased-contrast, and reduced-transparency modes.

### Don't:

- **Don't** reduce sleep to a gamified score, achievement ring, streak, or alarmist
  health judgment.
- **Don't** fragment the analytical canvas into a bento grid of equal cards.
- **Don't** use decorative gradients, wellness illustration, or glass effects to
  manufacture atmosphere.
- **Don't** encode meaning only by hue or hard-code colors for one appearance.
- **Don't** imply cloud processing, account dependency, AI insight, diagnosis, or
  treatment advice in the v1 visual language.
- **Don't** hide exact values, units, missing-data gaps, or provenance behind visual
  polish.
