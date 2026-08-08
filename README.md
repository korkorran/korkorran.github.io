# korkorran.github.io

korkorran personal blog — a static site generated with [YOCaml 3](https://github.com/xhtmlboi/yocaml),
a static site generator written as an OCaml *library* rather than a CLI tool.

## Layout

```
bin/main.ml          the generator itself: rules, metadata, feeds
content/articles/    blog posts (Markdown + YAML front matter)
content/pages/       standalone pages (Markdown + YAML front matter)
templates/           Jingoo templates
static/              CSS and images, copied verbatim
_site/               build output (git-ignored)
```

## Build

Requires OCaml >= 5.1.1 and the system library `oniguruma`
(`brew install oniguruma` / `apt install libonig-dev`), needed for syntax highlighting.

```sh
opam install . --deps-only --yes
dune exec bin/main.exe -- build     # generate _site/
dune exec bin/main.exe -- watch     # rebuild and serve on http://localhost:8000
dune exec bin/main.exe -- clean     # drop _site/ and the build cache
```

The build is incremental: YOCaml tracks every target's dependencies — sources, templates,
and the generator binary itself — and only rewrites what changed.

## Writing a post

Create `content/articles/YYYY-MM-DD-slug.md`:

```markdown
---
title: A title
synopsis: One sentence, used in the listing and in both feeds.
date: 2026-08-08
tags:
  - ocaml
---

The body, in Markdown.
```

`title` and `date` are required and validated at build time — a malformed date fails the
build instead of producing a broken page. `synopsis` and `tags` are optional.

A standalone page goes in `content/pages/` and uses the simpler `Page` archetype, whose
title field is `page_title` (there is no `date` and no `synopsis`):

```markdown
---
page_title: About
description: Shown in the <meta name="description"> tag.
---
```

Fenced code blocks are highlighted at build time by `yocaml_markdown`, which emits one
CSS class per TextMate scope; the palette lives in
[`static/css/style.css`](static/css/style.css).

## Deployment

Pushing to `main` triggers [`.github/workflows/deploy.yml`](.github/workflows/deploy.yml),
which builds the site and publishes `_site/` to GitHub Pages. Set
*Settings → Pages → Source* to **GitHub Actions** once, and nothing else is needed.
