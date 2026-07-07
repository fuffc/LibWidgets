# LibWidgets — Developer Notes

## What this is

A small, addon-agnostic UI widget library for 1.12 WoW addons. It currently
houses one widget, `NewListEditor`: a bordered `FauxScrollFrame`-backed row
pool with an optional leading tristate/checkbox control, a colour-able name
label, optional trailing per-column widgets, reorder (arrows + full
drag-to-reorder with a ghost row, insertion indicator and cursor-edge
auto-scroll), and an optional add row. Further widgets are expected to join it
under the same library name over time.

`NewListEditor` has no knowledge of any particular addon's data model — every
list-specific behavior (the backing array, how to reorder/remove an entry,
how to paint the name/leading control/any trailing columns, even the absolute
path to its own textures) comes through the `spec` table passed to
`LibWidgets.NewListEditor(parent, spec)`, and it holds no addon-specific state
of its own. See the header comment in [LibWidgets.lua](LibWidgets.lua) for the
full `spec` field list.

## Comment style

Comments in `LibWidgets.lua` (and any future file in this folder) should stand
alone: state what the code does and why it's built that way *now*, without
narrating how that came to be. Two things to keep out of them, both because
this file is meant to be identical across every addon that vendors it:

- **Development history.** Not "we tried X, then confirmed by testing that Y
  doesn't work" — just state the design that was settled on and its rationale,
  as a fact about the code, not a story about arriving at it.
- **Cross-references to other addons.** Sibling addons (or their libraries)
  elsewhere in whatever tree this file happens to be edited in are useful
  context while working on it, but they don't belong in the comment once
  written — a copy of this file vendored into a different addon has no reason
  to know or care about them.

That context still belongs somewhere — it goes in this CLAUDE.md (or the
consuming addon's own), which persists across sessions without living inside
shared code. (References to [LibStub](../LibStub/LibStub.lua) are the
exception: it's a real runtime dependency of this file, not incidental
context, so citing it is describing the code, not its history.)

## Client constraints that shaped this design

- **No self-path introspection.** WoW texture paths (`SetTexture`,
  `SetBackdrop`'s `bgFile`/`edgeFile`) are always absolute
  `Interface\AddOns\<addon>\...` strings, with no "relative to the
  currently-executing file" resolution. A shared library normally could work
  around that with a `debug.getinfo`-based self-path trick, but this client's
  Lua sandbox doesn't expose the `debug` library at all (`type(debug)` is
  `"nil"`, confirmed in-game) — so a loaded chunk has no way to discover its
  own path at runtime, full stop. Consequence: `spec.textureDir` is a required
  field on every `LibWidgets.NewListEditor(...)` call, same as `nameFrame` or
  `rowHeight` — the caller supplies its own addon's absolute textures path
  like any other caller-specific value, rather than this file assuming or
  hardcoding one.
- **No working multi-file XML manifest.** The common convention for a growable
  vendored library is a single `.xml` manifest a consumer's `.toc` references
  once, which pulls in every `.lua` file the library is made of via nested
  `<Script>`/`<Include>` tags — so growing the library never touches a
  consumer's `.toc` again. That doesn't work on this client: a nested `.xml`'s
  `<Script file="...">` silently fails to load, regardless of whether the path
  is spelled relative to the `.xml` file or to the addon root, while a direct
  `.lua` reference in the consumer's own `.toc` loads fine (confirmed
  in-game). Consequence: every consuming addon's `.toc` must list each of this
  library's `.lua` files directly (currently just
  `Libs\LibWidgets\LibWidgets.lua`). If this library ever grows past one
  file, every consumer's `.toc` needs a new line too — there's no avoiding it
  here.
- **File-load-time chat output is unreliable.** `DEFAULT_CHAT_FRAME:AddMessage`
  calls made while a file is first loading (top-level chunk execution) appear
  to get silently dropped on this client, even though the identical call works
  fine later (e.g. from a slash command). A load-time diagnostic should
  capture its result into a table and be read back on demand later, not try to
  print immediately.

## Growing this beyond one file

If a second widget joins this library, see the "load order in the `.toc`",
"Lua `local`s don't cross files", and especially the "versioning gate doesn't
automatically cover new files" issues before splitting anything out — only one
file may call `LibStub:NewLibrary`, and every additional file needs its own
matching version check (`local L, loadedMinor = LibStub:GetLibrary(MAJOR); if
not L or loadedMinor ~= MINOR then return end`) to avoid an older vendored
copy's second file silently overwriting a newer copy's first file. Absent a
concrete need to split, prefer keeping new widgets in this one file — nothing
about this ecosystem rewards splitting (every file loads eagerly and in full
regardless), so the only good reason to split later is human readability, not
architecture.

## Multi-addon coexistence

`LibWidgets = LibStub:NewLibrary("LibWidgets-1.0", MINOR)` at the top of the
file, guarded by `if not LibWidgets then return end`, is what makes it safe
for more than one addon to vendor this library at the same time. All addons
share a single global Lua environment, so a plain `LibWidgets = {}` at file
scope would mean whichever addon's copy happens to load *last* silently
overwrites every earlier addon's global table. LibStub instead picks a winner
by version number (whichever copy declares the highest `MINOR`) and every
other copy's body no-ops immediately — so which addon's copy of the *code*
ends up bound to the global name no longer matters, since (combined with
`spec.textureDir` above) no addon-specific state is baked into it either way.
[LibStub.lua](../LibStub/LibStub.lua) is vendored in its own sibling
`Libs\LibStub\` folder — it's a shared bootstrap other libraries can register
through too, not something owned by LibWidgets specifically — and must load
before `LibWidgets.lua` in the consumer's `.toc`.

## Packaging

[manifest.ps1](manifest.ps1) is a packaging-time helper only, not a load-time
manifest — `Get-LibWidgetsManifest` returns this library's shippable files
(its `.lua` files, listed explicitly since there's no working `.xml` to read
them from, plus everything under `textures\`) so a consumer's own packaging
script can include exactly those files instead of a blind recursive copy of
this folder. That distinction matters because this folder is a git submodule:
a blind copy would also sweep up version-control metadata that doesn't belong
in a shipped addon. It only covers this library's own folder — `Libs\LibStub\
LibStub.lua` is a plain `.toc` entry in the consumer, already covered by the
consumer's own packaging script the same way any other directly-listed file
is.

## Vendoring model

A real git submodule ([fuffc/LibWidgets](https://github.com/fuffc/LibWidgets)), checked out
identically at `Libs\LibWidgets\` in every consuming addon. The widget code
itself avoids anything consumer-specific: the caller supplies its own texture
path via `spec`, and LibStub means it doesn't matter whose checkout of the
submodule ends up executing if two consumers happen to be pinned to different
commits.
