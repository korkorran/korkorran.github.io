---
title: Owebview — a solution for your OCaml GUIs
synopsis: Write the UI as a web page, keep the logic in native OCaml. A small, portable, fast-starting alternative to binding a widget toolkit.
date: 2026-09-08
banner: logo.png
tags:
  - ocaml
  - owebview
  - gui
---

Giving an OCaml program a graphical interface has always meant picking a compromise:
bind a widget toolkit and inherit its installation story, or draw everything yourself and
reimplement decades of interface behaviour.

[owebview](https://github.com/korkorran/owebview) takes a third route. The UI is a web
page, rendered by the engine your operating system already ships; the logic stays native
OCaml. This post is the case for using it — the
[previous article](/posts/2026-08-27-introducing-owebview/) covers how the bindings
themselves are built.

## An embedded rendering engine, not a widget set

owebview embeds a web rendering engine inside your application. That is the whole idea,
and the consequence is worth stating plainly: **anything a web page can display, your
application can display.**

This is a different proposition from a toolkit binding. With GTK or Qt you get the
widgets the toolkit provides, and anything outside that set is work. Here the vocabulary
is HTML, CSS and the entire JavaScript ecosystem — charts, 3D scenes, maps, animation,
rich text, a layout engine that reflows on resize. None of it needs an OCaml binding,
because none of it crosses the OCaml boundary.

The examples in the repository make the point: a D3 chart and a three.js scene, both
running with no bindings written for either library.

## A JavaScript ↔ OCaml bridge

A rendering engine on its own would only give you a browser in a window. The useful part
is that the page can call into your program.

`Webview.bind` exposes an OCaml function to the page as `window.<name>(...)`, returning a
Promise on the JavaScript side:

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

```js
const sum = await window.add(20, 22);
```

Traffic goes the other way too: `eval` runs JavaScript in the current page, `init`
injects code before every page load, and `dispatch` schedules a function on the UI
thread — which is what you need when a background thread wants to push something into
the page.

So the interface is a web page, but the application is not a web application. There is no
server to run, no HTTP port to pick, no serialization protocol to design between two
processes. Your handlers are ordinary OCaml functions, with access to the filesystem, to
native libraries, to the rest of your program.

## Built on webview

owebview binds [webview](https://github.com/webview/webview), and inherits three
properties from it.

- **Portability.** One codebase across macOS (WebKit), Linux (WebKitGTK) and Windows
  (WebView2). The platform differences are handled at build time; your OCaml code does
  not branch on the OS.
- **Size.** No engine is bundled. The application links against the one already installed
  on the machine, so the binary is measured in megabytes rather than the hundreds an
  Electron app carries.
- **Startup.** The engine is already resident and shared with the rest of the system,
  so a window appears in milliseconds, not after a runtime unpacks itself.

The honest counterpart: you do not control the renderer. Those are three genuinely
different engines, and a layout that behaves on one may need attention on the others.
That trade — size and startup against a guaranteed rendering target — is the one
decision you are really making when you pick this design.

## Render in JavaScript, or in OCaml

Nothing forces the front-end to be JavaScript.

The straightforward path is to write real `.html`, `.css` and `.js` files and load them —
that is what the `hellowv` example does, and it means the UI can be built by anyone
comfortable with the web, with the browser devtools working as usual.

But OCaml compiles to JavaScript. Add `(modes js)` to a dune executable and the page
logic can be OCaml too, using [Brr](https://erratique.ch/software/brr) for the DOM:

```lisp
(executable
 (name app)
 (libraries brr)
 (modes js))
```

The same binding is then reached from the OCaml side of the page:

```ocaml
let promise = Jv.call Jv.global "add" [| Jv.of_int 20; Jv.of_int 22 |]
```

The `js_of_ocaml` example in the repository does exactly this. What matters is that the
choice is yours, and that it is not all-or-nothing: start with a plain HTML page, move
the parts that benefit from types over to OCaml, keep a JavaScript library where a
JavaScript library is the right answer.

## Bonus — accessibility works out of the box

This one tends to be overlooked, and it is a real argument.

Because the interface is a genuine DOM inside a genuine web engine, the platform
accessibility tree is populated for free. Screen readers see the interface. `Tab` moves
between form fields, `Shift+Tab` goes back, focus rings are drawn, `Enter` and `Space`
activate buttons, text inputs handle selection, IME and clipboard correctly. Zoom and
high-contrast settings apply.

A hand-drawn GUI has to reimplement every one of those behaviours, and most never do.
Here they are inherited from thirty years of browser work.

One caveat, and it is the same as on the web: you get this by writing semantic HTML. A
`<div>` with a click handler is exactly as unusable with a keyboard here as it is in a
browser. Use `<button>`, label your inputs, and the rest follows.

## Try it

```sh
opam install owebview
```

The repository is [on GitHub](https://github.com/korkorran/owebview) under MIT, with
runnable examples for D3, three.js, a timer, a random generator and a full
`js_of_ocaml` front-end.

owebview is developed mainly on macOS, so reports from Linux and Windows builds remain
the most useful thing to send my way.
