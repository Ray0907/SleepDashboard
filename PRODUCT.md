# Product

<!-- impeccable:product-schema 1 -->

## Platform

macos

## Stack

Native SwiftUI app using SwiftData for local persistence and Swift Charts for
visualization. AutoSleep CSV import uses a streaming parser and a transactional
SwiftData import coordinator. There is no backend and no outbound network
entitlement.

## Users

The primary user is an individual who tracks sleep with AutoSleep on an iPhone
and wants to inspect longer-term patterns on a Mac without creating an account
or sending health data to a third party.

## Product Purpose

Sleep Dashboard imports user-owned AutoSleep history and turns it into an
interactive, trustworthy view of nightly sleep duration, consistency, recovery,
and related metrics. Success means the user can move from a CSV export to useful
trend evidence quickly, inspect exact nights, and remain confident that the data
never leaves the Mac.

## Positioning

The product is a private, local-first analysis workspace rather than another
sleep account or cloud service. Its differentiator is a transparent pipeline
from an exported source file to deterministic calculations and native charts,
with no sign-in, backend, or remote processing.

## Operating Context

The user exports a History CSV from AutoSleep on an iPhone, transfers or saves
the file to the Mac, selects it with the system file importer, reviews an import
summary, and explores Home and Detail Metrics dashboards over 7-day, 30-day,
90-day, all-time, or custom ranges. Imports can be cancelled, re-importing the
same rows is safe, malformed rows are reported, and all imported data can be
deleted from the app.

## Capabilities and Constraints

- v1 imports AutoSleep CSV only. Apple Health `export.zip` support is deferred
  because its overlapping interval and multi-source semantics require a separate
  normalization design.
- v1 analytics are deterministic Swift functions. Missing metrics render as
  gaps and are never silently converted to zero.
- All parsing, persistence, aggregation, and rendering happen locally. The app
  has no cloud sync, account system, multi-user mode, or Apple Health write-back.
- The app follows the macOS system appearance and must provide complete light
  and dark modes with equivalent hierarchy, contrast, and chart legibility.
- AI-generated Sleep Insights are a future optional capability, not part of v1.
  If introduced, they remain on-device, consume verified analytic summaries
  rather than raw files, stay visually secondary to the charts, and do not make
  medical diagnoses or treatment recommendations.

## Brand Commitments

The product name is **Sleep Dashboard**. Product language is calm, factual, and
privacy-forward. It should explain uncertainty and missing data plainly rather
than presenting a false sense of medical precision.

## Evidence on Hand

- Product and engineering specification:
  `docs/superpowers/specs/2026-08-11-sleep-dashboard-design.md`
- Current Home dashboard visual reference:
  `/Users/ray/Documents/Codex/2026-08-11/new-chat/outputs/sleep-dashboard-home-mockup.png`
- No runnable application code, user research, testimonials, clinical claims,
  or validated brand assets exist yet. Future work must not fabricate them.

## Product Principles

1. Privacy is an architectural property, not a settings promise.
2. Show deterministic evidence before interpretation.
3. Imports are reversible, transactional, and explicit about skipped data.
4. Preserve source semantics, units, time zones, and missing values.
5. Feel native to macOS in navigation, interaction, appearance, and accessibility.

## Accessibility & Inclusion

Support system light and dark appearance, increased contrast, readable Dynamic
Type-equivalent scaling on macOS, keyboard navigation, VoiceOver labels, and
non-color chart differentiation. Health-related language must remain descriptive
and avoid diagnosis or alarmist framing.
