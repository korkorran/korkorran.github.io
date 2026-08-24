# korkorran.github.io

korkorran personal blog — a static site generated with [YOCaml 3](https://github.com/xhtmlboi/yocaml),
a static site generator written as an OCaml *library* rather than a CLI tool.

## Layout

```
bin/main.ml          the generator itself: rules, metadata, feeds
content/articles/    one directory per post: index.md plus its images
content/pages/       standalone pages (Markdown + YAML front matter)
templates/           Jingoo templates
static/              site-wide CSS and images, copied verbatim
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

`watch` needs **miou >= 0.6** (0.8.0 is known good). With miou 0.5.x the server binds
and listens but never accepts a connection: requests hang with the process asleep at 0%
CPU. If you hit that, `opam update && opam install miou.0.8.0`. `build` is unaffected.

The generated site uses absolute paths (`/css/style.css`), which is correct for a user
site served at the domain root — so opening `_site/index.html` over `file://` shows an
unstyled page with broken links. Use `watch`, or any static server rooted at `_site/`.

The build is incremental: YOCaml tracks every target's dependencies — sources, templates,
and the generator binary itself — and only rewrites what changed.

Each build ends by deleting anything in `_site/` that no rule produced, so renaming or
removing a post does not leave a stale page behind. Two consequences: do not keep
hand-written files in `_site/` (a `CNAME`, for instance — add a rule for it instead), and
note that only files are removed, so an emptied directory may linger harmlessly.

## Writing a post

A post is a **directory**, not a file. Create `content/articles/YYYY-MM-DD-slug/index.md`:

```markdown
---
title: A title
synopsis: One sentence, used in the listing and in both feeds.
date: 2026-08-08
banner: yocaml.png
tags:
  - ocaml
---

The body, in Markdown.
```

`title` and `date` are required and validated at build time — a malformed date fails the
build instead of producing a broken page. `synopsis`, `banner` and `tags` are optional.

`banner` names an image **in the post's own directory**, displayed full width above the
title. A wide image keeps its proportions; a tall or square one is cropped to 18rem
rather than pushing the title off the screen. The field is not part of YOCaml's `Article`
archetype — `bin/main.ml` wraps that archetype in its own metadata type to add it, which
is the pattern to follow for any further field. A `banner` naming a file that is not
there fails the build (exit 2) with a diagnostic pointing at the article, so a typo never
reaches the published site.

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

## Images in a post

Put them in the post's own directory, next to `index.md`, and link them
**relatively**:

```
content/articles/2026-08-08-hello-yocaml/
  index.md
  diagram.png
```

```markdown
![A diagram of the pipeline](diagram.png)
```

The post is published at `/posts/<slug>/` and its images are copied alongside it
into `_site/posts/<slug>/`, so a relative link resolves without further thought.
Any file in the directory that is not Markdown travels with the post.

For images used across the whole site (a logo, a shared illustration), use
`static/images/` instead and link them absolutely: `/images/logo.svg`.

## Deployment

Pushing to `main` triggers [`.github/workflows/deploy.yml`](.github/workflows/deploy.yml),
which builds the site and publishes `_site/` to GitHub Pages. Set
*Settings → Pages → Source* to **GitHub Actions** once, and nothing else is needed.
