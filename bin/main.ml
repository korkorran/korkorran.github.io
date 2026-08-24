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
  let license_url = "https://creativecommons.org/licenses/by-sa/4.0/"
  let license_name = "CC BY-SA 4.0"

  (* Feeds redistribute the posts, so they carry the same terms as the pages. *)
  let rights = "Content licensed under " ^ license_name ^ " (" ^ license_url ^ ")"
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

(** {1 Articles as directories}

    An article is a directory, not a file: [content/articles/<slug>/] holds
    [index.md] next to the images it uses. That layout is what lets a post write
    [!\[a diagram\](diagram.png)] and have the relative link resolve, because
    the rendered page and its images end up as siblings in
    [_site/posts/<slug>/]. *)

let is_markdown = Path.has_extension "md"

(** Everything in an article directory that is not the Markdown source travels
    with it: images, and whatever else the post needs. *)
let is_asset path = not (is_markdown path)

let article_source dir = Path.(dir / "index.md")
let article_output_dir dir = Path.move ~into:Target.posts dir
let article_target dir = Path.(article_output_dir dir / "index.html")

(** The public URL of an article. The trailing slash matters twice over: it is
    what makes a relative image link resolve inside the post, and it lets the
    server hand back [index.html] without a redirect. *)
let article_url dir = Path.(move ~into:(abs [ "posts" ]) dir ++ [ "" ])

(** [Archetype.Article] validates [title], [synopsis], [date] and the page
    fields, but its set of fields is closed. Wrapping it adds [banner] — the
    file name of an image sitting in the article's own directory, displayed
    above the title — while reusing the archetype's validation for everything
    else. *)
module Article = struct
  type t = { article : Archetype.Article.t; banner : string option }

  let entity_name = Archetype.Article.entity_name

  let neutral =
    Result.map
      (fun article -> { article; banner = None })
      Archetype.Article.neutral

  let validate data =
    let open Data.Validation in
    let ( let* ) = Result.bind in
    let* article = Archetype.Article.validate data in
    let* banner = record (fun fields -> optional fields "banner" string) data in
    Ok { article; banner }

  let article { article; _ } = article
  let banner { banner; _ } = banner

  (** [banner] stays a bare file name so the template can use it as a relative
      link: the image is copied next to the rendered page. *)
  let normalize { article; banner } =
    Archetype.Article.normalize article
    @ Data.
        [
          ("banner", option string banner)
        ; ("has_banner", bool (Option.is_some banner))
        ]
end

(** The index listing. [Archetype.Articles] is hard-wired to
    [Archetype.Article], so its normalisation would drop [banner] on the floor;
    this is the same shape, built on the extended article instead. *)
module Articles = struct
  type t = { page : Archetype.Page.t; articles : (Path.t * Article.t) list }

  let from_page =
    Task.lift (fun (page, articles) -> { page; articles })

  let sort_by_date articles =
    let date (_, a) = Archetype.Article.date (Article.article a) in
    List.sort (fun a b -> Archetype.Datetime.compare (date b) (date a)) articles

  (** [banner] is a bare file name, resolved against the article's own
      directory. That works inside the article page, but the index sits at the
      site root, so the listing needs the joined path instead. [url] already
      ends with a slash. *)
  let normalize_article (url, article) =
    let url = Path.to_string url in
    let banner_url =
      Option.map (fun name -> url ^ name) (Article.banner article)
    in
    Data.record
      (("url", Data.string url)
      :: ("banner_url", Data.option Data.string banner_url)
      :: Article.normalize article)

  let normalize { page; articles } =
    ("articles", Data.list_of normalize_article articles)
    :: ("has_articles", Data.bool (articles <> []))
    :: Archetype.Page.normalize page
end

(** {1 Helpers} *)

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

(** The article list feeding the index and both syndication feeds. Each article
    directory is visited once and its [index.md] read for metadata only. *)
let all_articles =
  let open Task in
  Pipeline.fetch ~only:`Directories ~on:`Source
    (fun dir ->
      let open Eff in
      let+ metadata, _content =
        Yocaml_yaml.Eff.read_file_with_metadata
          (module Article)
          ~on:`Source (article_source dir)
      in
      (article_url dir, metadata))
    Source.articles
  >>| fun articles -> Articles.sort_by_date articles

(** The feeds only need the plain archetype, so the banner is projected away. *)
let all_articles_for_feeds =
  let open Task in
  all_articles
  >>| List.map (fun (url, article) -> (url, Article.article article))

(** [custom_error] is extensible precisely so a generator can add its own
    validation failures. Going through it, rather than a bare exception, is what
    makes YOCaml report this as an authoring mistake instead of suggesting the
    user file a bug against YOCaml itself. *)
type Data.Validation.custom_error +=
  | Missing_banner of { article : Path.t; banner : Path.t }

let error_handler ppf = function
  | Missing_banner { article; banner } ->
      Format.fprintf ppf
        "%a declares a banner that does not exist: %a@,\
         Drop the image in the article's directory, or fix the field."
        Path.pp article Path.pp banner
  | _ -> Format.fprintf ppf "Unknown error"

(** Metadata validation is pure, so it cannot look at the filesystem. This is
    the step that does: a [banner] naming a file that is not there stops the
    build, instead of publishing a page with a broken image.

    Note this runs as part of producing the article page, so it is skipped when
    that page is already up to date — deleting a banner after a successful build
    is only caught the next time the article itself changes. *)
let check_banner dir =
  Task.from_effect (fun ((metadata, _content) as document) ->
      match Article.banner metadata with
      | None -> Eff.return document
      | Some name ->
          let open Eff in
          let source = article_source dir in
          let banner = Path.(dir / name) in
          let* exists = file_exists ~on:`Source banner in
          if exists then return document
          else
            raise
              (Eff.Provider_error
                 {
                   source = Some source
                 ; target = None
                 ; error =
                     Required.Validation_error
                       {
                         entity = Article.entity_name
                       ; error =
                           Data.Validation.Custom
                             (Missing_banner { article = source; banner })
                       }
                 }))

(** {1 Rules} *)

(** Copy a directory into the target, recursively, one file at a time.

    {!Yocaml.Action.copy_directory} would be a one-liner here, but it records
    only the directory itself in the cache. {!Yocaml.Action.remove_residuals}
    compares the cache against the files actually on disk, so it would then see
    every file inside that directory as unaccounted for — and delete it. Copying
    file by file registers each target, which also makes the copy properly
    incremental. *)
let rec copy_tree ~into dir cache =
  let open Eff in
  let target = Path.move ~into dir in
  Action.batch ~only:`Files dir (Action.copy_file ~into:target) cache
  >>= Action.batch ~only:`Directories dir (copy_tree ~into:target)

(** Copy [static/css] and [static/images] verbatim into the target. These are
    the site-wide assets; per-article images travel with their article. *)
let static_files =
  let open Path.Infix in
  Action.batch_list
    [ Source.static / "css"; Source.static / "images" ]
    (copy_tree ~into:Target.root)

(** One article: render [index.md] through the article template and the layout,
    then copy the directory's assets next to the result. *)
let article dir cache =
  let open Eff in
  Action.Static.write_file_with_metadata (article_target dir)
    (let open Task in
     Pipeline.track_file Source.generator
     >>> Yocaml_yaml.Pipeline.read_file_with_metadata
           (module Article)
           (article_source dir)
     >>> check_banner dir
     >>> Yocaml_markdown.Pipeline.With_metadata.make ()
     >>> Pipeline.chain_templates
           (module Yocaml_jingoo)
           (module Article)
           [ article_template; layout ])
    cache
  >>= Action.batch ~only:`Files ~where:is_asset dir
        (Action.copy_file ~into:(article_output_dir dir))

let articles = Action.batch ~only:`Directories Source.articles article

(** One standalone page. Same shape as {!article}, with the simpler [Page]
    archetype: no date, no synopsis, no companion assets. *)
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
           (fan_out id (lift (fun _ -> ()) >>> all_articles)
           >>> Articles.from_page)
     >>> Pipeline.chain_templates
           (module Yocaml_jingoo)
           (module Articles)
           [ index_template; layout ])

let atom_feed =
  Action.Static.write_file Target.atom
    (let open Task in
     Pipeline.track_file Source.generator
     >>> all_articles_for_feeds
     >>> Yocaml_syndication.Atom.from_articles ~site_url:Config.url
           ~feed_url:(Config.url ^ "/atom.xml")
           ~title:(Yocaml_syndication.Atom.text Config.title)
           ~subtitle:(Yocaml_syndication.Atom.text Config.synopsis)
           ~rights:(Yocaml_syndication.Atom.text Config.rights)
           ~authors:(Nel.singleton author) ())

let rss_feed =
  Action.Static.write_file Target.rss
    (let open Task in
     Pipeline.track_file Source.generator
     >>> all_articles_for_feeds
     >>> Yocaml_syndication.Rss.from_articles ~title:Config.title
           ~site_url:Config.url
           ~feed_url:(Config.url ^ "/rss.xml")
           ~description:Config.synopsis ~copyright:Config.rights ())

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
  (* Anything left in _site/ that no rule above produced is stale — a renamed
     article, a deleted page — so it goes. *)
  >>= Action.remove_residuals ~target:Target.root
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
  | "build" ->
      Yocaml_unix.run ~level:`Info ~custom_error_handler:error_handler
        process_all
  | "watch" | "serve" ->
      Yocaml_unix.serve ~level:`Info ~custom_error_handler:error_handler
        ~target:Target.root ~port:Config.port process_all
  | "clean" ->
      List.iter
        (fun p -> remove (Path.to_string p))
        [ Target.root; Target.cache ];
      print_endline "cleaned _site/ and _cache"
  | _ -> usage ()
