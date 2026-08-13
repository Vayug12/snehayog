# Design System

## Philosophy

This app follows a premium, minimal design language inspired by:

- ChatGPT
- Apple Human Interface Guidelines
- Linear
- Notion

The interface should feel calm, modern, intelligent, and effortless.

Never use flashy gradients, heavy shadows, oversized icons, or excessive colors.

The UI should prioritize whitespace, typography, hierarchy, and subtle animations over decoration.

---

# Core Principles

1. Less is more.
2. Every element must have a purpose.
3. Every word must earn its place.
4. Prefer whitespace over borders.
5. Avoid visual clutter.
6. Use smooth motion, never distracting animations.
7. Everything should feel premium.

---

# Color System

This is a dark theme, matching the Vayug app's navy/blue palette (see `lib/core/design/colors.dart`).

## Background

Primary Background
#0F172A

Secondary Background
#1E293B

Surface
#1E293B

Card
#1E293B

Divider
#334155

---

## Text

Primary
#FFFFFF

Secondary
#94A3B8

Muted
#64748B

Disabled
#64748B (60% opacity)

Inverse (on light surfaces)
#0F172A

---

## Accent

Primary Accent
#2563EB

Light
#3B82F6

Dark / Pressed
#1D4ED8

Success
#10B981

Warning
#F59E0B

Danger
#EF4444

Never use multiple accent colors in one screen.

---

# Corner Radius

Buttons
14px

Cards
18px

Dialogs
20px

Bottom Sheets
28px

Input Fields
14px

Images
16px

---

# Shadows

Avoid heavy shadows.

Use extremely soft elevation.

Example

0 2 12 rgba(0,0,0,0.05)

or

0 4 20 rgba(0,0,0,0.04)

---

# Typography

Use Inter.

Weights

Regular 400

Medium 500

SemiBold 600

Bold 700

Never use more than four font sizes on one screen.

Display
32

Title
24

Heading
20

Body
16

Caption
14

Small
12

Line height should always feel spacious.

---

# Copy

Fewer words, more meaning.

Text is UI. Every extra line is clutter, exactly like an extra border.

Write the shortest version that still works, then cut one more word.

## Limits

Heading

5 words. No full stop.

Body

1 line. A second line only if the user loses something without it.

Button

Verb first. 2 words. "Sign in", never "Sign in to continue".

Helper text

Only for rules the user cannot guess: limits, formats, cost, consequences.

Error

What broke, what to do. 1 line.

## Delete any text that

repeats what the control already says

states the obvious

describes what the user can already see

apologises or over-explains

## Rules

Never stack a heading, a subtitle and a button that all say the same thing.

Never explain a heading with a subtitle. Rewrite the heading instead.

One idea per screen. One line per idea.

An icon and one button is a finished screen, not an unfinished one.

Reference: `lib/shared/widgets/auth_sign_in_prompt.dart` — the button carries the meaning, the copy above it is optional.

---

# Spacing

Use an 8-point grid.

Allowed spacing

4

8

12

16

20

24

32

40

48

64

Never invent random spacing values.

---

# Buttons

Primary

Filled

Blue accent

White text

Height

52px

Radius

14px

Secondary

Surface background

Subtle border

Light text

Text Button

No border

Accent text

Never use gradients.

---

# Inputs

Height

52px

Rounded corners

14px

Soft gray background

No hard borders.

Focus should use the accent color.

---

# Cards

Cards should:

have lots of padding

soft corners

minimal shadow

no unnecessary outlines

avoid multiple nested cards

---

# Icons

Use Lucide icons.

Size

20 or 24

Stroke width

2

Never mix icon styles.

---

# Lists

Generous vertical spacing.

Each item should breathe.

Avoid dense layouts.

---

# Navigation

Bottom navigation should be simple.

No floating colorful effects.

Active item uses accent color.

Inactive items use muted gray.

---

# Animations

Duration

200–300ms

Use easeInOut.

Use fade, scale, or slide.

Never bounce.

Never over animate.

---

# Images

Rounded corners.

Consistent aspect ratios.

No decorative frames.

---

# Empty States

Every empty state should include:

simple icon

primary action

Add a title only when the action alone is ambiguous.

Never add a sentence explaining the title.

---

# Loading

Prefer skeleton loading.

Avoid full-screen spinners.

Never label a spinner with "Loading...". The spinner already says it.

---

# Error States

One line: what broke.

One action: how to fix it.

No apologies, no technical detail, no second paragraph.

---

# Accessibility

Minimum touch target

44x44

Contrast should remain high.

Support dynamic text.

---

# Screen Layout

Every screen follows:

Top App Bar

↓

Page Title

↓

Primary Content

↓

Secondary Content

↓

Primary CTA

Use generous whitespace between sections.

A description is not a step in this layout. Add one only when the title cannot carry the meaning, and keep it to one line.

---

# DO

✓ Minimal

✓ Premium

✓ Calm

✓ Spacious

✓ Consistent

✓ Few words

✓ Apple quality

✓ ChatGPT style

✓ Linear style

✓ Professional

---

# DON'T

✗ Glassmorphism

✗ Neon colors

✗ Heavy gradients

✗ Large drop shadows

✗ Rounded blobs everywhere

✗ Material 3 colorful defaults

✗ Inconsistent spacing

✗ Different button styles

✗ Random font sizes

✗ Crowded layouts

✗ Helper text that repeats the button

✗ A subtitle under every heading

✗ Paragraphs where a label works

✗ Marketing copy inside the product

---

# AI Instructions

Whenever creating a new screen:

- Reuse existing components whenever possible.
- Maintain identical spacing patterns.
- Do not invent new colors.
- Follow the typography scale.
- Keep interfaces minimal.
- Write the least text that still works: no subtitle where a title is enough, no title where the button is enough.
- Before shipping a screen, delete every line the UI already communicates.
- Optimize for readability first.
- Every screen should look like it belongs in the same product.
- If unsure, choose the simpler option.
- The result should resemble a premium Apple-quality productivity app with the calm visual language of ChatGPT.