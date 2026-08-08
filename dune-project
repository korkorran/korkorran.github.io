(lang dune 3.18)

(name korkorran_site)

(generate_opam_files true)

(source
 (github korkorran/korkorran.github.io))

(authors "Frederic Lang")

(maintainers "frederic.ln.lang@gmail.com")

(license MIT)

(package
 (name korkorran_site)
 (synopsis "Static site generator for korkorran.github.io")
 (description
  "The YOCaml program that builds korkorran.github.io: articles, pages, an index and syndication feeds.")
 (depends
  (ocaml
   (>= 5.1.1))
  (yocaml
   (>= 3.0.0))
  (yocaml_unix
   (>= 3.0.0))
  (yocaml_yaml
   (>= 3.0.0))
  (yocaml_markdown
   (>= 3.0.0))
  (yocaml_jingoo
   (>= 3.0.0))
  (yocaml_syndication
   (>= 3.0.0))))
