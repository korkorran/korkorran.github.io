(** The generator for korkorran.github.io.

    A YOCaml program: it describes the rules that turn [content/], [templates/]
    and [static/] into the [_site/] directory. Every rule tracks its own
    dependencies, so a build only rewrites what actually changed. *)

open Yocaml

(** {1 Configuration} *)

module Config = struct
  let title = "korkorran"
  let url = "https://korkorran.github.io"
  let synopsis = "Notes on OCaml, type systems and the tools I build."
  let author_name = "Frédéric Lang"
  let author_email = "frederic.ln.lang@gmail.com"
  let author_uri = "https://github.com/korkorran"
  let port = 8000
end

(** {1 Paths}

    [Source] describes where things are read from, [Target] where they are
    written to. Keeping them apart makes the rules below read as plain
    sentences. *)

module Source = struct
  open Path.Infix

  let content = ~/[ "content" ]
  let articles = content / "articles"
  let pages = content / "pages"
  let index = content / "index.md"
  let static = ~/[ "static" ]
  let templates = ~/[ "templates" ]

  (** Tracking the generator's own source means that changing a rule
      invalidates every page it produces. *)
  let generator = ~/[ "bin"; "main.ml" ]

  let template name = templates / name
end

module Target = struct
  open Path.Infix

  let root = ~/[ "_site" ]
  let posts = root / "posts"
  let cache = ~/[ "_cache" ]
  let atom = root / "atom.xml"
  let rss = root / "rss.xml"
end

(** {1 Helpers} *)

let is_markdown = Path.has_extension "md"

(** Where an article file is written: [content/articles/a.md] becomes
    [_site/posts/a.html]. *)
let article_target file =
  Path.(move ~into:Target.posts (change_extension "html" file))

(** The URL of an article, absolute so that it works from any page and can be
    concatenated with {!Config.url} in the feeds. *)
let article_url file =
  Path.(move ~into:(abs [ "posts" ]) (change_extension "html" file))

(** Where a standalone page is written: [content/pages/about.md] becomes
    [_site/about.html]. *)
let page_target file =
  Path.(move ~into:Target.root (change_extension "html" file))

let layout = Source.template "layout.html"
let article_template = Source.template "article.html"
let page_template = Source.template "page.html"
let index_template = Source.template "index.html"

let author =
  Yocaml_syndication.Person.make ~uri:Config.author_uri
    ~email:Config.author_email Config.author_name

(** The article list feeding the index and both syndication feeds. *)
let all_articles =
  Archetype.Articles.fetch
    (module Yocaml_yaml)
    ~where:is_markdown ~compute_link:article_url Source.articles

(** {1 Rules} *)

(** Copy [static/css] and [static/images] verbatim into the target. *)
let static_files =
  let open Path.Infix in
  Action.batch_list
    [ Source.static / "css"; Source.static / "images" ]
    (Action.copy_directory ~into:Target.root)

(** One article: read its validated front matter, render the Markdown, then
    wrap it in the article template and the layout. *)
let article file =
  Action.Static.write_file_with_metadata (article_target file)
    (let open Task in
     Pipeline.track_file Source.generator
     >>> Yocaml_yaml.Pipeline.read_file_with_metadata
           (module Archetype.Article)
           file
     >>> Yocaml_markdown.Pipeline.With_metadata.make ()
     >>> Pipeline.chain_templates
           (module Yocaml_jingoo)
           (module Archetype.Article)
           [ article_template; layout ])

let articles = Action.batch ~only:`Files ~where:is_markdown Source.articles article

(** One standalone page. Same shape as {!article}, with the simpler [Page]
    archetype: no date, no synopsis. *)
let page file =
  Action.Static.write_file_with_metadata (page_target file)
    (let open Task in
     Pipeline.track_file Source.generator
     >>> Yocaml_yaml.Pipeline.read_file_with_metadata (module Archetype.Page) file
     >>> Yocaml_markdown.Pipeline.With_metadata.make ()
     >>> Pipeline.chain_templates
           (module Yocaml_jingoo)
           (module Archetype.Page)
           [ page_template; layout ])

let pages = Action.batch ~only:`Files ~where:is_markdown Source.pages page

(** The home page: a regular page whose metadata is enriched with the list of
    articles, so the template can render the listing. *)
let index =
  let open Path.Infix in
  Action.Static.write_file_with_metadata
    (Target.root / "index.html")
    (let open Task in
     Pipeline.track_file Source.generator
     >>> Yocaml_yaml.Pipeline.read_file_with_metadata
           (module Archetype.Page)
           Source.index
     >>> Yocaml_markdown.Pipeline.With_metadata.make ()
     >>> first
           (Archetype.Articles.compute_index
              (module Yocaml_yaml)
              ~where:is_markdown ~compute_link:article_url Source.articles)
     >>> Pipeline.chain_templates
           (module Yocaml_jingoo)
           (module Archetype.Articles)
           [ index_template; layout ])

let atom_feed =
  Action.Static.write_file Target.atom
    (let open Task in
     Pipeline.track_file Source.generator
     >>> all_articles
     >>> Yocaml_syndication.Atom.from_articles ~site_url:Config.url
           ~feed_url:(Config.url ^ "/atom.xml")
           ~title:(Yocaml_syndication.Atom.text Config.title)
           ~subtitle:(Yocaml_syndication.Atom.text Config.synopsis)
           ~authors:(Nel.singleton author) ())

let rss_feed =
  Action.Static.write_file Target.rss
    (let open Task in
     Pipeline.track_file Source.generator
     >>> all_articles
     >>> Yocaml_syndication.Rss.from_articles ~title:Config.title
           ~site_url:Config.url
           ~feed_url:(Config.url ^ "/rss.xml")
           ~description:Config.synopsis ())

(** {1 Program} *)

let process_all () =
  let open Eff in
  Action.restore_cache Target.cache
  >>= static_files
  >>= articles
  >>= pages
  >>= index
  >>= atom_feed
  >>= rss_feed
  >>= Action.store_cache Target.cache

(** {1 Entry point} *)

let rec remove path =
  if Sys.file_exists path then
    if Sys.is_directory path then begin
      Array.iter
        (fun entry -> remove (Filename.concat path entry))
        (Sys.readdir path);
      Sys.rmdir path
    end
    else Sys.remove path

let usage () =
  prerr_endline
    "usage: main.exe [build | watch | clean]\n\n\
    \  build   generate the site into _site/ (default)\n\
    \  watch   rebuild on every request and serve _site/\n\
    \  clean   remove _site/ and the build cache";
  exit 1

let () =
  let command = if Array.length Sys.argv > 1 then Sys.argv.(1) else "build" in
  match command with
  | "build" -> Yocaml_unix.run ~level:`Info process_all
  | "watch" | "serve" ->
      Yocaml_unix.serve ~level:`Info ~target:Target.root ~port:Config.port
        process_all
  | "clean" ->
      List.iter
        (fun p -> remove (Path.to_string p))
        [ Target.root; Target.cache ];
      print_endline "cleaned _site/ and _cache"
  | _ -> usage ()
