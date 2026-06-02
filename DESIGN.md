---
version: alpha
name: Clip4X Material System
description: Google-inspired visual system for a local macOS clip repurposer.
colors:
  primary: "#1A73E8"
  primary-hover: "#1558B0"
  primary-container: "#E8F0FE"
  accent: "#8E6CFB"
  canvas: "#F8FAFD"
  surface: "#FFFFFF"
  surface-muted: "#F1F3F4"
  on-surface: "#202124"
  on-surface-muted: "#5F6368"
  outline: "#DADCE0"
  outline-strong: "#BDC1C6"
  success: "#188038"
  warning: "#F9AB00"
  error: "#D93025"
typography:
  headline-lg:
    fontFamily: SF Pro
    fontSize: 28px
    fontWeight: 700
    lineHeight: 1.15
    letterSpacing: 0em
  headline-md:
    fontFamily: SF Pro
    fontSize: 20px
    fontWeight: 700
    lineHeight: 1.25
    letterSpacing: 0em
  body-md:
    fontFamily: SF Pro
    fontSize: 14px
    fontWeight: 400
    lineHeight: 1.45
    letterSpacing: 0em
  label-sm:
    fontFamily: SF Pro
    fontSize: 12px
    fontWeight: 600
    lineHeight: 1.25
    letterSpacing: 0em
spacing:
  xs: 4px
  sm: 8px
  md: 16px
  lg: 24px
  xl: 32px
rounded:
  sm: 4px
  md: 8px
  pill: 9999px
components:
  app-canvas:
    backgroundColor: "{colors.canvas}"
    textColor: "{colors.on-surface}"
  button-primary:
    backgroundColor: "{colors.primary}"
    textColor: "{colors.surface}"
    rounded: "{rounded.pill}"
    typography: "{typography.body-md}"
  button-tonal:
    backgroundColor: "{colors.primary-container}"
    textColor: "{colors.primary-hover}"
    rounded: "{rounded.pill}"
    typography: "{typography.body-md}"
  chip-neutral:
    backgroundColor: "{colors.surface-muted}"
    textColor: "{colors.on-surface-muted}"
    rounded: "{rounded.pill}"
  card:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.on-surface}"
    rounded: "{rounded.md}"
  divider:
    backgroundColor: "{colors.outline}"
    height: 1px
  focus-outline:
    backgroundColor: "{colors.outline-strong}"
    height: 1px
  chip-selected:
    backgroundColor: "{colors.primary-container}"
    textColor: "{colors.primary-hover}"
    rounded: "{rounded.pill}"
  status-success:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.success}"
    rounded: "{rounded.pill}"
  status-warning:
    backgroundColor: "{colors.warning}"
    textColor: "{colors.on-surface}"
    rounded: "{rounded.pill}"
  status-error:
    backgroundColor: "{colors.error}"
    textColor: "{colors.surface}"
    rounded: "{rounded.pill}"
  icon-accent:
    backgroundColor: "{colors.accent}"
    size: 36px
---

## Overview

Clip4X should feel like a focused Google productivity tool: bright, direct, approachable, and functional. The UI should favor clear surfaces, blue primary actions, subtle outlines, and dense-but-readable workflow controls.

## Colors

Use `primary` only for the main action, selected chips, links, and progress/status emphasis. Use `accent` sparingly for the app icon or small status accents, not for page-wide gradients. Default surfaces are white over a very light blue-gray canvas.

## Typography

Use system typography with Google-like hierarchy: bold titles, medium-weight labels, and readable body text. Keep letter spacing at `0em`. Avoid oversized marketing type inside the app shell.

## Layout

Use an app bar, left workflow panel, and right review surface. Panels use 24px outer padding and 16px internal spacing. Cards are individual repeated items only; do not nest cards inside cards.

## Elevation & Depth

Prefer outlines and soft background contrast over heavy macOS materials. Shadows should be subtle and reserved for elevated repeated cards or the app icon.

## Shapes

Cards and panels use 8px radius. Buttons and selection chips may use pill radius because they are controls, not content cards.

## Components

Primary buttons are blue pills with leading icons. Secondary buttons are outlined or tonal. Ratio selection uses chips, not the default macOS segmented control. Status and metadata use compact chips.

## Do's and Don'ts

Do keep the workflow obvious: drop, analyze, select, export. Do make selected clips visually distinct. Do keep repeated cards scan-friendly. Do not use translucent glass, native sidebar chrome, broad purple gradients, nested cards, or decorative UI copy.
