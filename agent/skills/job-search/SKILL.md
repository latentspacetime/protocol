---
name: job-search
description: Find current job openings with evidence from official postings, explicit freshness checks, transparent matching criteria, and citations for every role.
---

# Job Search

Convert the request into explicit criteria: role families, location, work mode,
seniority, compensation constraints, domain preferences, and exclusions.

## Evidence Standard

- Use official careers or applicant-tracking pages as the source of truth.
- Confirm that each posting is still live when reporting it.
- Record the exact title, location, work mode, compensation when published,
  posting URL, and observed date.
- Distinguish stated facts from inferred fit.
- Do not invent a posting date when the source omits it.
- Remove duplicates by canonical posting URL or requisition identifier.

## Result Quality

Rank roles against the user's criteria with a short evidence-backed reason.
Call out missing requirements and uncertainty. Exclude aggregator-only listings,
expired pages, inaccessible pages that cannot be independently verified, and
roles that violate a hard constraint.

Return a compact table followed by methodology, unresolved uncertainty, and
the official source links.
