---
name: hermes-multi-asset-web-project
description: Use when the user asks for multiple HTML/CSS/JS artifacts in one request such as creating 10 websites for 10 businesses. Complements claude-design for project structure, per-category design differentiation, and ZIP archive output. Treat as a project with structured directories.
version: 1.0.0
author: Hermes Agent
license: MIT
metadata:
  hermes:
    tags: [html, css, multi-asset, project, web, creative, design]
    related_skills: [claude-design, sketch, popular-web-designs]
---

# Multi-Asset Web Project

## When to Use

- User asks: "create N websites for N businesses", "generate multiple HTML pages for different clients", "make a bundle of landing pages"
- The deliverable is N distinct HTML artifacts bundled together (ZIP, tar.gz, directory)

## Core Method

intake  arrow  structure  arrow  design-each  arrow  verify-each  arrow  archive

## Directory Structure

```
project_root/
item_1_business_slug/
  index.html
  style.css
item_2_business_slug/
  index.html
  style.css
...
archive.zip
```

### Naming Convention
- Project root: descriptive name based on the deliverable
- Item subfolders: sortable prefix + business slug (e.g., negocio_1_casa_tia_ciata)
- Item files: index.html + style.css only (flat, no nested directories)

## Design Differentiation by Category

When each artifact maps to a business type, each should get a genuinely different design system.

Rule: Each site must differ in at least 3 of these 6 dimensions:
1. Background: light, dark, gradient direction
2. Palette: warm, cool, monochrome, accent color
3. Typography: serif-ish, bold, airy, compact
4. Layout: grid, list, card-based, two-column
5. Section structure: sticky nav, hero+grid, info+description
6. Button treatment: pill, boxed, outlined, inline

### Business-Type Design Postures

| Type | Posture | Key choices |
|---|---|---|
| Restaurant/Bar | Warm, inviting | Earth-tone gradient header, sticky nav, center-aligned tagline |
| Fast food/Burger | Bold, playful | Menu grid, prominent CTA, red/orange palette, burger cards |
| Market/Mall | Informational | Two-column layout, clean sans-serif, high readability |
| Liquor store | Dark, premium | Dark bg, green/black gradient, gold accent for ratings |
| Hardware/Construction | Industrial | Brown/tan gradient, bordered list items, sturdy sans-serif |
| Bakery/Sweets | Sweet, light | Specialty grid, soft pastels, decorative header, card layout |
| Gym/Fitness | High-energy | Black bg, red gradient, white cards with red accents, gold ratings |
| Automotive/Mechanic | Functional | List-based services, contact card with shadow, blue/white palette |
| Pharmacy/24h | Clean, clinical | Services grid, 24h badge, professional blue, contact emphasis |
| Hotel/Lodging | Elegant, calming | Hero area, amenity grid, booking CTA, warm neutral palette |

## Steps

### 1. Intake and Planning
List all items with their data: name, category, address, phone, hours, ratings
Assign a sortable prefix + slug to each
Sketch the design posture for each

### 2. Project Structure
Create the project root directory
Create one subdirectory per item
Each subdirectory gets index.html + style.css

### 3. Build Each Artifact
For each item: index.html with semantic HTML and all collected data, style.css with unique design system, self-contained with no remote dependencies

### 4. Verify Each Artifact
Confirm both files exist in each subdirectory
Read back at least 2 files to confirm content quality
Check that each has a genuinely different design

### 5. Archive
From the project root use zip or Python zipfile to create a single archive
Report the archive path and project root in the final response

## Verification Checklist
- One subdirectory per item created
- Each subdirectory has index.html + style.css only
- Each site uses a different design system (3+ different dimensions)
- All sites use real collected data
- No remote dependencies in any CSS/JS
- Each file verified by reading back
- Archive created and path confirmed