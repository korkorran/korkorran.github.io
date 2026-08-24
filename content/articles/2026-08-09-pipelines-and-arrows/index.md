---
title: Pipelines and arrows
synopsis: How YOCaml models building a page as a composition of arrows, and why that makes incremental builds fall out for free.
date: 2026-08-09
banner: arrows.png
tags:
  - ocaml
  - yocaml
---

The central type in YOCaml is `('a, 'b) Task.t`: a task turning a value of type `'a` into
a value of type `'b` while accumulating a **set of dependencies**.

## Compose, don't configure

Building a page means chaining tasks together:

```ocaml
Pipeline.read_file_with_metadata (module Metadata.Article) source
>>> Yocaml_markdown.content_to_html ()
>>> Pipeline.chain_templates ~templates
```

Every `>>>` composes two tasks. The interesting part is implicit: reading a file adds that
file to the dependency set, applying a template adds the template. When YOCaml decides
whether a target needs rebuilding, it compares the target against that set — which nobody
had to declare by hand.

## The generator depends on itself

The detail I find elegant: `track_file` lets you declare the generator binary as a
dependency of every page. Change the OCaml code that emits the HTML and the entire site is
invalidated. That is exactly the behaviour you want, and it costs one line.

## Validated front matter

The YAML header of an article is not a bag of strings. It goes through a module with a
`validate` function that either builds a typed value or fails. In practice that means an
article dated `2026-13-45` does not render a slightly wrong page — it breaks the build
immediately, with a message pointing at the offending file.
