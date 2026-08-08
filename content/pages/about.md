---
page_title: About
description: Who writes here and what this site is built with.
---

I am Frédéric Lang. I write software, mostly in OCaml, and this is where I keep notes
worth more than a scratch file.

## This site

Every page you see here is produced by a small OCaml program living in
[`bin/main.ml`](https://github.com/korkorran/korkorran.github.io/blob/main/bin/main.ml).
It uses [YOCaml 3](https://github.com/xhtmlboi/yocaml) as a library: articles are Markdown
files with validated YAML front matter, templates are Jingoo, and the Atom and RSS feeds
are generated from the same article list that feeds the index page.

There is no database, no JavaScript, and no tracking. The build is incremental — YOCaml
tracks each target's dependencies, including the generator binary itself, and rewrites
only what changed.

## Elsewhere

- GitHub: [@korkorran](https://github.com/korkorran)
- Feed: [Atom](/atom.xml) · [RSS](/rss.xml)
