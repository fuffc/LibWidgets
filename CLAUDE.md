# LibWidgets — Developer Notes

## What this is

A small, addon-agnostic UI widget library for 1.12 WoW addons. It currently
houses fourteen widgets:

- `NewButton` — a flat, tooltip-backdrop-styled action button (text label,
  press-nudge feedback).
- `NewTabButton` — a `NewButton` plus the lit "selected" look and a `value`
  identifying it. A selected tab ignores hover so the active one stays lit.
- `NewTabStrip` — a row of `NewTabButton`s that lays itself out. Each tab is
  sized to **its own label**, not to an equal share of the strip, and the row
  wraps onto as many lines as it needs; `onReflow(rows, height)` tells the
  consumer to re-anchor whatever sits below. The layout is AceGUI
  `TabGroup:BuildTabs` — measure, greedy-wrap, pull a lone last tab up beside
  its neighbours, stretch a row to fill — with one deliberate change: the
  fill test is applied **per row** rather than only to a lone row, so a short
  second row keeps its natural widths instead of ballooning two tabs across
  the whole strip. Equal shares are the obvious alternative and they fail as
  soon as a strip grows: every tab shrinks to the narrowest one's needs, and a
  label with no width set does not clip on this client — it overflows into its
  neighbours. `select(nil)` deselects every tab, for a panel showing something
  that belongs to no tab.
- `NewIconButton` — the same button styling with a texture face instead of a
  label; the list editor's own reorder/delete buttons are these, published so a
  consumer can build the same control outside a list (a section header's
  collapse arrow or delete affordance). `LibWidgets.ICON_DELETE` is the delete
  art it uses.
- `NewCheckBox` — a standalone `UICheckButtonTemplate` checkbox with a
  right-hand label and a `.setChecked(on)` resync method (the leading-control
  checkbox inside `NewListEditor` is a separate, row-bound thing).
- `NewColorSwatch` — a swatch button opening the stock `ColorPickerFrame` (with
  opacity) over a caller-supplied `get`/`set` on a `{r,g,b,a}` array. The
  `OpacitySliderFrame` reports `1 - alpha`; that inversion is contained here.
- `NewTextBox` — a single-line edit box with the same tooltip-style backdrop
  (not `InputBoxTemplate` — its border renders a black bar at small heights),
  committing on Enter. Optional `onChange` (live per-keystroke callback) and
  `hint` (greyed placeholder shown while empty) fields cover live-filter/search
  boxes without a separate widget.
- `NewMultiLineEditBox` — a scrollable multi-line edit box with the same
  tooltip-style backdrop, for paste-in/copy-out blobs (import/export) and as the
  base of `NewCodeEditBox`. Scrolled by this library's own `NewScrollFrame`, not
  `UIPanelScrollFrameTemplate`, so it matches every other scroller here. A
  multi-line `EditBox` does **not** size itself to its text on this client, so
  the content height is measured with a zero-alpha `FontString` carrying the
  same font and wrap width — without that the scroll range is meaningless (the
  old version pinned the child at a flat 2000px). Anything that changes the
  text, the size or the font must therefore go through `setText`/`setSize`/
  `setFont` rather than the raw frame methods, or the range goes stale.
- `NewScrollFrame` — a chrome-free vertical content scroller: a plain
  `ScrollFrame` (no Blizzard scroll template) with a slim tinted right-edge
  slider and mouse wheel. The caller fills its `.content` scroll child, sets that
  child's height, and calls `.Update()` to re-fit the slider. `NewDropButton`'s
  scrolling popup and WeakestAuras' options content pane both sit on it, so every
  scrollbar in the addon reads as the same slim widget.
- `NewSlider` — an `OptionsSliderTemplate` slider whose title carries the live
  value instead of the template's Low/High end labels, with a `.setValue(v)`
  method that resyncs the widget from external state without echoing back
  through `onChange`.
- `NewSpinBox` — the same job as `NewSlider` for a value that has to be set
  exactly: a caption above a filled track, the number typeable inside the track
  as a centred edit box, and a step button just outside each end. Drag for
  coarse, type for exact, step for fine. Typing commits on Enter *and* on focus
  loss (clicking away keeps the number rather than discarding it), reverts on
  Escape, and snaps/clamps to min/max/step. The two step buttons are the one
  `up` arrow under `textures\` given a quarter turn each way via `SetTexCoord`,
  so a consumer ships one arrow file rather than four.
- `NewDropButton` — a button showing the current value that drops a popup list
  of options to change it (no cycling), for small fixed or dynamic value sets
  (an anchor point, a mode, a profile name). With `spec.textureDir` it draws a
  right-edge down-arrow (grey at rest, green on hover) as a menu affordance. A
  long popup caps at `spec.maxVisibleItems` (default 8) rows and scrolls the
  rest via a `NewScrollFrame`, so it reads like a short menu. `spec.swatches`
  (value -> texture path) turns it into a *preview* picker: the face and every
  menu row draw that texture as a filled green bar, so a status-bar texture is
  picked by how it looks rather than by its name. `LibWidgets.BAR_TEXTURES` +
  `LibWidgets.BarTexturePath(dir, name)` are the bar-texture set to feed it
  (names here, `.tga` files in the consumer — see "no self-path introspection"
  below; "Blizzard" resolves to the client's own art and needs no file).
- `NewIconPicker` — a modal icon browser: a live search box over a scrolling
  grid of every icon the client knows, a preview of the current pick, and
  Okay/Cancel/Clear. Built once and reused via `.Open(current)`/`.Close()`.
  Only `columns * visibleRows` cell buttons ever exist — they are repainted as
  the grid scrolls — so a ~5000-icon database costs a fixed ~230 frames rather
  than one button per icon.
- `NewListEditor` — a bordered `FauxScrollFrame`-backed row pool with an
  optional leading tristate/checkbox control, a colour-able name label,
  optional trailing per-column widgets, reorder (arrows + full
  drag-to-reorder with a ghost row, insertion indicator and cursor-edge
  auto-scroll), and an optional add row built from `NewButton` + `NewTextBox`
  (so the add row shares the same flat-button/edit-box look as everything
  else instead of a separately hand-rolled pair). The add row is parented to
  the editor's own outer frame, not to the caller's parent, so a consumer that
  repaints a panel by hiding the returned `frame` takes the add row down with
  it rather than stranding an orphaned edit box + button on the page.

- `NewCodeEditBox` — `NewMultiLineEditBox` decorated into a syntax-coloured Lua
  editor. Colouring happens **on blur, never while typing**: the plain code
  lives in a private upvalue and the edit box holds the display form, so a
  focused box contains exactly what the user typed and the caret can never
  land inside a colour escape. The coloured form is padded with blank lines the
  same way the live path pads, so an unterminated string's runaway colour ends
  on those rather than on the user's last line of code. Carries its
  own red error line under the box
  (driven by a caller-supplied `validate`) and, when given `spec.default`, a
  two-click-confirm Reset button above it. The button is always built and
  merely hidden without a default, so a pooling consumer can rebind one
  instance across fields that do and don't have one. **Tab re-indents** the
  whole buffer (`spec.tabWidth`, or `false` for hard tabs). Font face and size
  are settable after construction (`setFont`/`setFontSize`), so a pooled box
  picks up a changed setting on repaint instead of needing a rebuild. Optional
  `spec.live` colours per keystroke instead of on blur, which needs the caret
  saved and restored around each pass — it is off unless asked for, and
  **bracket matching rides on it**: the matched pair under the caret is painted
  in `colorTable.match`, and there is no caret to match against unless the box
  is focused and colouring live.

Further widgets are expected to join it under the same library name over time.

One non-widget group also lives here, at the bottom of the file: a **Lua source
tokenizer** and the syntax-colouring helpers built on it — `LuaColorize`,
`LuaIndent`, `LuaEncode`/`LuaDecode`, `LuaStripColors`/`LuaStripColorsWithPos`,
`LuaPadWithLinebreaks`, `LuaMatchBracket`, plus `LuaNextToken`/`LuaTokens`/
`LuaKeywords`/`DEFAULT_LUA_COLORS`. Ported from *For All Indents And Purposes*
(Kristofer Karlsson). They are here because the code edit box
that consumes them is library code, not because they are generally useful:
the rule this library follows is **it owns what its own widgets call**. A
consumer's own validation policy (which wrapper the code is compiled behind,
what counts as an error) stays in the consumer.

They are pure `string -> string` and touch no frame, which makes them the one
part of this library testable off the client.

None of them have any knowledge of a particular addon's data model —
every caller-specific behavior (what a button does, a slider's range/label,
a text box's commit, a drop button's values, a list editor's backing
array/reorder/paint) comes through the `spec` table (or plain args, for the
simpler widgets) passed to each `LibWidgets.New*(parent, spec)` call, and the
widgets hold no addon-specific state of their own. `NewButton`/`NewTextBox`/
`NewSlider`/`NewDropButton` reuse the list editor's own flat-button/backdrop
styling (`styleFlatButton`, `WIDGET_BACKDROP`) so every widget in the library
reads as one visual system, and the more composite widgets (`NewListEditor`'s
add row) are themselves built from the simpler ones rather than duplicating
their construction. See the header comment in [LibWidgets.lua](LibWidgets.lua)
for the full `spec` field list of each.

## Closing a `NewDropButton` popup

At most one `NewDropButton` popup is open at a time, tracked by a single
private `activeMenu` upvalue and closed through the public
`LibWidgets.CloseAllMenus()`.

1.12 gives a plain `Button`/`Slider`/`CheckButton` no generic focus-lost
event — only `EditBox` has `OnEditFocusGained`/`OnEditFocusLost` — so there is
no reliable way to detect "some other control just gained focus" by
listening from the outside. The alternative most addons reach for is a
screen-covering invisible "click-catcher" frame raised above everything
while a menu is open, closing it on any `OnMouseDown` that lands outside the
menu. That works for "click on blank space", but it actively hurts the
"switch directly to a different drop button" case: the catcher, being above
everything so it can catch a background click, also swallows the click meant
for the *next* drop button, so opening it needs a second click (close, then
open) instead of one.

This library takes the opposite approach: no passive catcher at all. Instead
every interactive widget it builds — `NewButton`'s `OnMouseDown`,
`NewSlider`'s `OnValueChanged`, `NewTextBox`'s `OnEditFocusGained`,
`NewDropButton`'s own item clicks and toggle, and the list editor's
reorder/delete/leading-control buttons and drag-start — calls
`CloseAllMenus()` as the first thing it does. Touching *anything* else in
the library closes a still-open menu immediately, and clicking a different
`NewDropButton` opens it in one click (its own `OnClick` closes the old menu
and opens its own in the same handler, no catcher in the way).

The one gap this leaves is a click that lands on nothing interactive at all
— bare panel background, or somewhere outside the addon's own frames
entirely. A consuming addon can close that gap for its own panel by wiring
`OnMouseDown` (blank-area clicks) and `OnHide` to `LibWidgets.CloseAllMenus()`
too; FearWardHelper's config panel does both (`FearWardHelper.lua`'s
`buildConfig`). The `OnHide` half matters for correctness, not just polish:
hiding a parent frame only suppresses a child's *visibility*, not its own
`Shown` flag, so a menu left open when its host panel closes would otherwise
pop back up still expanded the next time the panel reopens.

### Edit focus rides the same signal

The missing focus-lost event cuts the other way too: an `EditBox` *does* get
told it lost focus, but only when something takes focus away from it, and
clicking a button or a checkbox is not that. A box the user clicked away from
therefore keeps focus indefinitely — and with it anything it only commits on
blur, which for `NewCodeEditBox` is the commit, the syntax colouring and the
error line all at once.

So `CloseAllMenus()` also drops the focused edit box, tracked in a
`focusedEdit` upvalue that every `OnEditFocusGained` in the file claims through
the private `takeFocus`. One event, one call site, and every consumer that
already wired a panel's `OnMouseDown`/`OnHide` gets the focus half for free.
`LibWidgets.ClearFocus()` is the focus half alone, for a caller that must not
disturb an open menu.

`takeFocus` drops the recorded box *before* closing the menus rather than
clearing it: the engine has already taken focus off whoever held it, and
clearing a recorded box that is the one now gaining focus fires its own
focus-lost handler underneath it. A pooled inline rename box reopened on a
second row closes itself that way.

## Where a `NewDropButton` popup is hosted

The popup is parented to the button's **top-level ancestor** (the frame parented
straight to `UIParent`, found by walking up the parent chain), not to the button
itself — and defaults to `FULLSCREEN_DIALOG` strata. Hosting it on the button is
the obvious choice but wrong for any drop button living inside a `ScrollFrame`:
the popup then sits inside the scroll region, gets clipped where it overflows,
and shares the scrolled rows' strata/level so it renders *behind* the controls
below it. Hosting it on the top-level frame escapes both. It still `SetPoint`s
its position to the button, so it tracks the button as normal. `spec.menuParent`
/`spec.menuStrata` override both for callers that need to.

The consequence for consumers: a popup is no longer a child of its button, so
hiding the button (e.g. repainting a tab's controls) no longer hides the popup
with it. A consuming addon that rebuilds its option controls in place must call
`LibWidgets.CloseAllMenus()` at the top of that repaint (in addition to the
`OnHide`/`OnMouseDown` wiring below), or a menu left open across a repaint
orphans, floating over the newly-painted controls.

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

## Where the icon list comes from

`NewIconPicker` defaults to `LibWidgets.GetIconDatabase()`, which prefers the
four append-to-table enumerators a patched client can surface —
`GetLooseMacroIcons` / `GetLooseMacroItemIcons` / `GetMacroIcons` /
`GetMacroItemIcons`, called in that order — and falls back to vanilla's
`GetNumMacroIcons` / `GetMacroIconInfo`.

The fallback is genuinely worse, not merely older: the vanilla engine's icon DB
is filtered to `Ability_*` / `Spell_*`, so `GetMacroIconInfo` never returns a
single `INV_*` item icon even though thousands exist. The four-function surface
captures them before that filter. Prefer it whenever it's there.

Two normalisation duties fall on this library rather than the caller. The four
calls do **not** dedup against each other — an icon present both as a loose
drop-in and inside an MPQ comes back twice — and the fallback returns full
paths where the modern calls return bare basenames. Everything is therefore
stored as an **uppercase basename**: it dedups case and prefix variants
together, keeps a ~5000-entry table light, and makes the search a plain
uppercase substring test. `LibWidgets.IconPath(name)` rebuilds the path, which
is safe because WoW resolves texture paths case-insensitively.

The scan walks thousands of files, so the result is built once per session on
first use. A caller with its own source passes `spec.icons` and skips all of
this.

## Client constraints that shaped this design

- **`SetFrameLevel` doesn't carry children on this client.** On modern WoW,
  re-levelling a frame shifts its children to keep their relative order; on 1.12
  it does not — the children keep their absolute levels. So bumping a container
  frame's level to force it above same-strata siblings leaves its own child
  frames *below* the container, where the container's backdrop draws over them.
  This is why `NewDropButton`'s popup is not re-levelled on open (it would grey
  out its own item buttons under the near-opaque menu backdrop); it relies on a
  strata above the host panel plus `SetToplevel` instead. Order popups by strata
  or `SetToplevel`, not by `SetFrameLevel` on a frame that has children.
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

### LibStub cannot be trusted to arbitrate

On at least one 1.12 client this library is used on, `LibStub:NewLibrary` does
not honour version numbers at all: its body assigns the minor a hardcoded
constant before comparing, discarding what the caller passed. Every major
therefore records the same number, and every registration after the first is
refused — a strictly newer copy included. The observable signature is every
library in `LibStub.minors` reading back as the same small value while the
libraries themselves declare 3, 6, 8, 44. Whichever copy registers first owns
the global for the session, forever.

Because of that, **this library does its own version arbitration** and treats
LibStub as a place to park the shared table, not as an authority. Every copy
publishes its own version as `LibWidgets.MINOR` on that shared table; a copy
that `NewLibrary` rejects compares its own `MINOR` against the *live* copy's
published one and takes over when it is strictly newer. A copy predating that
field publishes nothing and is correctly treated as older than anything.

This is the normal upgrade path, not a workaround for a broken client: it is
safe everywhere because it never displaces an equal or newer copy, and on a
healthy LibStub it simply never fires.

### The development hazard version-picking creates

Picking a winner by version means the copy that runs is not necessarily the
copy being edited. A consumer developing this library sees its edits silently
do nothing — everything keeps working, from someone else's checkout — until it
calls a function only its own copy defines, which then fails as
`attempt to call field 'X' (a nil value)` somewhere far from the version
mismatch that caused it. Raising MINOR fixes it only until another consumer
raises theirs.

`LIBWIDGETS_DEV`, set by the consumer before this file loads, makes this copy
register even when an equal-or-newer one already did. It is a development aid
and displaces whatever the other consumers were using, so it must not ship
enabled. `LibWidgets.MINOR` is published so a consumer can report which copy
actually won instead of discovering it through a nil call.

### How coexistence works

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
