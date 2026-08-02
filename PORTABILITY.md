# Portability

This engine must itself stay free of live customer project data.

| In this repo | Not in this repo |
|--------------|------------------|
| Isolation rubric, scanners, wiring docs | Live `projects/<slug>/` factories |
| Generic forbidden-pattern lists (placeholders) | Real epic keys, STG hostnames, tokens |

Product/engine repos keep their own CR rules. They **invoke** Themis isolation as a
sub-step (see `docs/WIRING.md`).
