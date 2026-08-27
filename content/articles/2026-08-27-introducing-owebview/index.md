---
title: Introducing owebview
synopsis: OCaml bindings for webview — a desktop window with an HTML UI, drawn by the web engine your operating system already ships.
date: 2026-08-27
tags:
  - ocaml
  - owebview
  - bindings
banner: globe_html_css_js_logo.svg
---

[owebview](https://github.com/korkorran/owebview) gives an OCaml program a native
desktop window with a web UI. No Electron, no bundler, no build pipeline. The whole
application is this:

```ocaml
let () =
  let w = Webview.create () in
  Webview.set_title w "My first owebview app";
  Webview.set_size w ~width:480 ~height:320 Webview.Hint_none;
  Webview.set_html w
    {|<!doctype html>
      <html>
        <body style="font-family: system-ui; text-align: center">
          <h1>Hello from OCaml 👋</h1>
        </body>
      </html>|};
  Webview.run w;
  Webview.destroy w
```

It is a thin binding over [webview](https://github.com/webview/webview), covering the
whole 0.12 C API and staying deliberately low-level.

## The architecture: borrow the engine, don't ship one

The interesting decision is one owebview inherits from webview, and it is the opposite
of the usual approach. Electron and its descendants bundle a full Chromium with every
application: the runtime is part of the artifact, which is why a trivial app weighs in
at hundreds of megabytes and why every application on your machine carries its own
private copy of a browser.

owebview ships no engine at all. It links against the one your operating system already
has:

- **macOS** — WebKit and Cocoa, system frameworks. Nothing to install.
- **Linux** — GTK 3 and WebKitGTK, through `gtk+-3.0` and `webkit2gtk-4.1`.
- **Windows** — WebView2, built through the MinGW toolchain. The runtime ships with
  Windows 10 and 11.

The consequences run both ways, and it is worth being clear about them. The binary stays
small and the application starts fast, because the engine is already resident and shared
with the rest of the system. But you no longer control the renderer: your page is
drawn by whatever engine the user's OS happens to provide, and those are three different
engines — WebKit, WebKitGTK, and Chromium wearing a WebView2 badge. A layout that behaves
on one may need attention on the others. This is a real trade, not a free lunch: it buys
size and startup at the cost of a guaranteed rendering target.

## Finding the native libraries

Linking against a system library means finding it first, and that differs per platform.
owebview resolves it at build time with `dune-configurator`, in `lib/config/discover.ml`:
macOS emits the framework flags directly, Linux queries `pkg-config` for both packages and
merges the results, and Windows locates the WebView2 SDK header. The flags land in two
generated `.sexp` files that `lib/dune` includes; nothing is edited by hand.

On Windows that SDK is installed with NuGet:

```sh
nuget install Microsoft.Web.WebView2
```

The header is then picked up from the NuGet cache automatically — or from
`MICROSOFT_WEB_WEBVIEW2`, if you would rather point at the package directory yourself.

When a dependency is missing the configurator stops the build with a message naming what
to install, rather than letting it fail later at link time with something cryptic. On
Linux the packages are also declared as opam `depexts`, per distribution family, so
`opam pin` offers to install them.

webview itself needs no such treatment: its amalgamated single-header is vendored in
`vendor/webview.h`, the entire C API and its C++ implementation inlined into one file.
Only the system engine is actually linked.

## Two sensitive points, made explicit

The bindings are hand-written C stubs rather than `ctypes`. That is a deliberate choice:
crossing this particular boundary has two hazards, and manual stubs put both in plain
sight.

**`webview_run` blocks.** It does not return until the window closes, so holding the
OCaml runtime lock across it would freeze the garbage collector and every other thread
for the lifetime of the window. The stub releases it around the call and takes it back
afterwards:

```c
caml_release_runtime_system();
webview_error_t err = webview_run(w);
caml_acquire_runtime_system();
```

Which creates the second half of the problem: callbacks fire from inside that blocking
call, with the lock released. The trampoline that dispatches to your OCaml closure has to
re-acquire it before touching a single OCaml value, and release it again on the way out.

**Closures must survive the GC.** A closure handed to `bind` is stored on the C side and
called much later, from code the OCaml heap knows nothing about. Left alone it would be
collected. Each one is registered with `caml_register_generational_global_root`, and
released when the binding goes away.

Neither hazard is exotic — they are the standard ones for any blocking C library with
callbacks — but they are exactly what a generated binding layer would hide.

## Calling OCaml from the page

Once a window renders, the useful part is the bridge. `bind` exposes an OCaml function to
JavaScript as `window.<name>(...)`, returning a Promise on the JS side:

```ocaml
(* Expose window.add(a, b) to the page. *)
Webview.bind w "add" (fun id req ->
    let result =
      match Scanf.sscanf_opt req "[%d,%d]" (fun a b -> a + b) with
      | Some n -> string_of_int n
      | None -> "null"
    in
    Webview.return w id ~error:false ~result)
```

Arguments arrive as a raw JSON string and the result goes back as one. The binding does
not (de)serialize for you — that is the low-level stance again, and plugging in `yojson`
is left to the caller. Alongside it: `navigate` for a URL or a local `file://` page,
`init` and `eval` to inject JavaScript, `dispatch` to run OCaml on the UI thread, and
`get_native_handle` if you need the underlying `NSWindow` or `GtkWindow`.

The bundled examples go further than the snippet above: `hellowv` loads real `.html`,
`.css` and `.js` files, and there are examples driving D3 and three.js with no bindings
at all.

## Where it stands

All three backends now build, Windows included — the MinGW path compiles, the runtime
locks behave. But owebview is developed and exercised mainly on macOS, and that is
precisely the weak spot of a design leaning on the system engine: the Linux and Windows
paths are implemented and their dependencies are detected, yet they have seen far less
use than the platform I run daily.

So if you build it somewhere other than macOS, reporting what happened is the single most
useful thing you can contribute. On Linux: do the `depexts` resolve, does WebKitGTK
behave? On Windows: does the NuGet cache get found, does your WebView2 Runtime cooperate?
Build logs welcome either way.

It is [on GitHub](https://github.com/korkorran/owebview), under MIT.
