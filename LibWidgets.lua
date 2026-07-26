-- LibWidgets -- a small, addon-agnostic UI widget library for 1.12 WoW
-- addons. Currently houses nine widgets: NewButton (a flat action button),
-- NewCheckBox (a labelled checkbox), NewColorSwatch (a ColorPickerFrame swatch),
-- NewSlider (a value-carrying OptionsSliderTemplate slider), NewTextBox (a
-- tooltip-backdrop-styled edit box), NewMultiLineEditBox (a scrollable multi-line
-- edit box), NewScrollFrame (a chrome-free content scroller), NewDropButton (a
-- value-picker popup button)
-- and NewListEditor (a bordered FauxScrollFrame-backed row pool with
-- an optional leading tristate/checkbox control, a class/priority-coloured
-- name label, optional trailing per-column widgets, reorder -- arrows + full
-- drag-to-reorder with a ghost row, insertion indicator and cursor-edge
-- auto-scroll -- and an optional add row built from NewButton + NewTextBox).
-- Further widgets are expected to join it under the same library name.
--
-- Every caller-specific bit of NewListEditor -- the backing list, how to
-- reorder/remove an entry, how to paint the name/leading control/any
-- trailing columns, and the absolute path to this library's own textures --
-- comes through the `spec` table (documented below), so this file has no
-- knowledge of any particular addon's data model and holds no addon-specific
-- state of its own.
--
-- Registered through LibStub (as "LibWidgets-1.0") so multiple addons
-- vendoring their own copy of this file coexist safely: whichever copy
-- declares the highest MINOR becomes the one shared instance regardless of
-- load order, and every other copy's body no-ops immediately below.
--
-- Vendored as its own Libs\LibWidgets\ folder (own .lua, own textures)
-- rather than a loose file in the addon root. A consuming addon's .toc must
-- list every .lua file this library is made of directly (today just this
-- one) -- there is no single manifest file a consumer can reference once to
-- pull in the whole library, since this client does not process nested
-- <Script>/<Include> directives from a referenced .xml file. manifest.ps1
-- (beside this file) is a packaging-time helper only: it lists this
-- library's shippable files (.lua + textures) so a consumer's own packaging
-- script can include exactly those files without recursively copying this
-- whole folder, which would also capture files that don't belong in a
-- shipped addon (such as version-control metadata now that this folder is a
-- git submodule).
--
-- NewButton(parent, spec) -- a flat, tooltip-backdrop-styled action button (the
-- same look as the list editor's reorder/delete/leading-control buttons). spec:
--   text, width, height (default 22), onClick
-- Returns the button with a `.label` FontString and a `.setText(text)` method for
-- relabeling later (e.g. a button whose face shows a live value).
--
-- NewCheckBox(parent, spec) -- a standalone labelled checkbox (UICheckButtonTemplate
-- plus a right-hand label). spec:
--   text, width/height (default 22)
--   onClick(checked) -- called on a user toggle with the new boolean state
--   get()            -- optional: seeds the initial checked state
-- Returns the CheckButton with a `.label` FontString and a `.setChecked(on)` method
-- that resyncs from external state without firing onClick.
--
-- NewColorSwatch(parent, spec) -- a swatch button that opens the stock
-- ColorPickerFrame (with opacity). spec:
--   get() -> {r,g,b,a}   -- current colour (a defaults to 1 if absent)
--   set({r,g,b,a})       -- store a picked colour
--   width/height (default 20), swatchSize (inner fill, default 14)
-- Returns the button with a `.repaint()` method to re-read get() after an
-- external change.
--
-- NewTextBox(parent, spec) -- a single-line edit box with a tooltip-style backdrop
-- (not InputBoxTemplate -- that template's border textures render a black bar at
-- small heights). spec:
--   width (omit to size purely from the caller's own anchors, e.g. a box anchored
--   on both TOPLEFT and RIGHT), height (default 22), text (initial contents)
--   onCommit(text) -- called on Enter (the box then clears focus); Escape clears
--                     focus with no commit. Omit for a read-only display box.
--   onChange(text) -- optional: called on every keystroke (live filtering); fires
--                     on user edits, not on the initial `text` seed.
--   hint           -- optional: greyed placeholder text shown while the box is empty.
--
-- NewMultiLineEditBox(parent, spec) -- a scrollable multi-line edit box (a
-- UIPanelScrollFrameTemplate ScrollFrame wrapping a SetMultiLine EditBox) with
-- the same tooltip-style backdrop, for paste-in/copy-out blobs (import/export).
-- spec:
--   width (default 300), height (default 150), text (initial contents)
--   onChange(text) -- optional: called on every edit
-- Returns the outer frame with methods `.setText(t)`, `.getText()`,
-- `.focusSelectAll()` (focus + highlight everything, so the user can Ctrl-C an
-- export immediately) and `.clearFocus()`, plus the `.edit` EditBox itself.
--
-- NewSlider(parent, spec) -- a horizontal OptionsSliderTemplate slider whose title
-- carries the live value instead of the template's Low/High end labels. spec:
--   name          -- unique global frame name (the template needs one to address
--                    "<name>Low"/"<name>High"/"<name>Text")
--   min, max, step, width (default 150)
--   onChange(v)   -- called on every user drag, and on a committed edit-box entry
--                    when `editable` is set
--   format(v)     -- optional: -> the full title text (defaults to the number
--                    rounded to `decimals` places)
--   decimals      -- max decimal places shown in the default title format and the
--                    editable box's display (default 2); trailing zeros are
--                    trimmed (1 shows as "1", not "1.00"). The same rounding is
--                    available standalone as LibWidgets.FormatNumber(v, decimals)
--                    for a caller building its own `format`.
--   get()         -- optional: seeds the initial value through the same guard
--                    `.setValue` uses, so seeding never echoes through onChange
--   editable      -- optional: adds a small edit box to the right of the slider
--                    bar showing the current value, editable directly (commits on
--                    Enter, clamped to min/max, rounded to `decimals`); the bar
--                    itself narrows by `inputWidth` + gap to keep the total
--                    footprint at `width`
--   inputWidth    -- width of that edit box (default 44)
-- Returns the slider with a `.setValue(v)` method: sets the value and repaints the
-- title (and the edit box, if any) without firing onChange, for resyncing the
-- widget from external state.
--
-- NewScrollFrame(parent, spec) -- a chrome-free vertical content scroller: a plain
-- ScrollFrame (no Blizzard scroll template) with a slim tinted right-edge slider
-- and mouse wheel, for scrolling arbitrary content that can outgrow its frame.
-- spec:
--   wheelStep   -- pixels scrolled per wheel notch (default 30)
--   sliderInset -- x-nudge of the slider from the frame's right edge (default 0)
-- The caller anchors the returned ScrollFrame, parents its content into the
-- `.content` scroll child (managing that child's width itself -- reserve a few px
-- on the right for the slider), sets `.content`'s height, then calls `.Update()`
-- so the slider re-fits (again after any later content-height or frame-size
-- change). Also exposes `.slider` and `.wheel` (the wheel handler, so a child that
-- captures wheel focus -- e.g. a button -- can forward to it via SetScript).
--
-- NewDropButton(parent, spec) -- a button showing the current value that drops a
-- popup list of options to change it (no cycling). spec:
--   width, height (button size; height defaults to 20)
--   menuWidth (defaults to width), itemHeight (defaults to 14)
--   maxVisibleItems -- popup caps at this many rows (default 8) and scrolls the
--                    rest via a slim right-edge slider + mouse wheel; shorter
--                    menus size to fit with no slider
--   values        -- ordered array of stored values (menu order), or a function
--                    returning one: the menu rebuilds on every open (dynamic sets,
--                    e.g. profile names)
--   labels        -- value -> display label; optional (defaults to the raw value)
--   tips          -- value -> tooltip line; optional
--   onSelect(v)   -- called when a menu entry is picked
--   textureDir    -- optional: absolute path to this library's textures folder. When
--                    given, a down-arrow (grey at rest, green on hover) is drawn on
--                    the button's right edge to signal it opens a menu.
--   get()         -- optional: when given, the button self-paints from it on build
--                    and after each pick via `.setValue`. Omit it for a caller that
--                    repaints recycled instances itself each draw (`.setValue(v)`
--                    works either way).
--   menuParent, menuStrata -- override the popup's parent/strata. By default the
--                    popup is hosted on the button's top-level ancestor frame (the
--                    one parented straight to UIParent) at "FULLSCREEN_DIALOG",
--                    NOT on the button: parented under the button, a popup dropped
--                    from a control inside a ScrollFrame gets clipped where it
--                    overflows the scroll region and shares the rows' strata,
--                    landing behind the controls below it. It still anchors its
--                    position to the button, so it tracks it.
-- The popup is toplevel'd so it orders above sibling same-strata popups on
-- interaction; its high strata already puts it above the host panel. It is
-- deliberately NOT re-levelled on open -- see the open handler for why.
-- The live value is stashed on `.value` for the button's own hover tooltip. At
-- most one NewDropButton popup is ever open at once -- see CloseAllMenus below.
--
-- CloseAllMenus() -- hides whichever NewDropButton popup is currently open, if
-- any. Every widget this library builds calls it on interaction (see the
-- comment above its definition for why -- there is no generic focus-lost event
-- to hook instead), so a menu closes the moment anything else in the library
-- is touched. A consuming addon's own panel can call it too (e.g. on
-- OnMouseDown for a blank-area click, or OnHide so a menu left open under a
-- closed panel doesn't pop back up still expanded next time it opens).
--
-- NewListEditor(parent, spec) -- spec fields:
--   nameFrame     -- unique string naming the internal ScrollFrame (1.12's
--                    FauxScrollFrameTemplate needs an addressable global name
--                    for its scrollbar child, "<nameFrame>ScrollBar")
--   textureDir    -- absolute path to this library's own textures folder
--                    (e.g. "Interface\AddOns\<addon>\Libs\LibWidgets\textures\").
--                    WoW texture paths are always absolute and this file has
--                    no way to discover its own path at runtime, so each
--                    caller supplies it like any other spec field.
--   x, y          -- TOPLEFT offset from `parent`
--   rightInset    -- RIGHT inset from `parent` (default 16)
--   rowHeight, visibleRows -- when visibleRows >= #list() the scrollbar just
--                    stays inert, so a "fixed, never scrolls" list (e.g. one
--                    row per class) needs no special casing here.
--   list()                     -> the live ordered array, read fresh each refresh
--   reorder(fromIndex, before) -- before is a boundary in 1..n+1: the entry
--                    ends up just before whatever currently sits at original
--                    index `before`. Used by both the arrow buttons and
--                    drag-drop.
--   remove(index)              -- optional; omit to hide the delete button
--   add = { onAdd(text) }      -- optional; builds an edit box + Add button
--                    below the list
--   leadingControl             -- optional:
--       { kind = "tristate", states = { {key=,color={r,g,b},tooltip=}, ... },
--         get(entry) -> key, cycle(entry) }
--     or
--       { kind = "checkbox", get(entry) -> bool, set(entry, bool) }
--   nameGet(entry) -> text
--   nameColor(entry, index) -> r, g, b               -- optional
--   columns = { { width, build(row) -> widget, update(widget, entry, index, count) }, ... }
--                    -- optional trailing per-row widgets; not used by any
--                    current caller, but the hook for future per-row data.
--
-- Returns { height = <total pixel height used below (x,y)>, refresh = fn,
--           frame = <the list's outer frame> }.

local MAJOR, MINOR = "LibWidgets-1.0", 8
-- Bind the global only on the winning copy. NewLibrary returns nil for a copy
-- that loses the version race; assigning that nil straight to the global would
-- wipe out the winner's binding (an older/equal copy loading last nulls it),
-- so keep the return in a local and publish only when we actually won.
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end
LibWidgets = lib

local BTN_W   = 20
local BTN_GAP = 2
local COL_GAP = 6
local STATE_W = 20

-- Rounds to `decimals` places and trims trailing zeros (and a bare trailing
-- "." if decimals rounded away entirely), so an integer value reads as "1"
-- rather than "1.00" while a fractional one still shows up to `decimals`
-- places -- NewSlider's default title/edit-box formatting.
local function formatNumber(v, decimals)
	local s = string.format("%." .. (decimals or 2) .. "f", v)
	if string.find(s, "%.") then
		s = string.gsub(s, "0+$", "")
		s = string.gsub(s, "%.$", "")
	end
	return s
end
LibWidgets.FormatNumber = formatNumber

local WIDGET_BACKDROP = {
	bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	tile = true, tileSize = 16, edgeSize = 9,
	insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

local ICON_DELETE = "Interface\\Buttons\\UI-GroupLoot-Pass-Up"

local MOVE_OK   = { 0.2, 0.9, 0.2 }
local MOVE_NONE = { 0.5, 0.5, 0.5 }

-- Only one NewDropButton popup is ever open at a time. 1.12 has no generic
-- focus-lost event for a plain Button/Slider/CheckButton (only EditBox has
-- OnEditFocusGained/Lost), so there is no reliable way to detect "some other
-- control just gained focus" from the outside. Instead every interactive
-- widget this library builds calls CloseAllMenus() as the first thing it
-- does on interaction (a click, a drag-start, an edit box gaining focus), so
-- touching *anything* else in the library always closes a still-open menu --
-- this is an explicit, not passive, close rather than a screen-covering
-- click-catcher, so it never costs the "click a different drop button"
-- case an extra click the way a catcher would. The one gap this doesn't
-- cover is a click that lands on nothing interactive at all (bare panel
-- background, or outside the addon's own frames entirely); a consuming
-- addon can close that gap too by wiring its own panel's OnMouseDown to
-- LibWidgets.CloseAllMenus().
local activeMenu = nil
function LibWidgets.CloseAllMenus()
	if activeMenu then activeMenu:Hide() end
	activeMenu = nil
end

-- Flat, tooltip-backdrop-styled button base shared by the reorder/delete/
-- leading-control buttons.
local function styleFlatButton(b)
	b:SetBackdrop(WIDGET_BACKDROP)
	b:SetBackdropColor(0, 0, 0, 0.7)
	b:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)
	b:SetScript("OnEnter", function() this:SetBackdropBorderColor(0.9, 0.8, 0.2, 1) end)
	b:SetScript("OnLeave", function() this:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8) end)
end

-- Reorder/delete icon button. Overrides styleFlatButton's hover so a disabled
-- button (row 1's "up", the last row's "down") doesn't brighten on hover.
local function iconButton(parent, icon, onClick)
	local b = CreateFrame("Button", nil, parent)
	b:SetWidth(BTN_W); b:SetHeight(18)
	styleFlatButton(b)
	local t = b:CreateTexture(nil, "ARTWORK")
	t:SetWidth(11); t:SetHeight(11)
	t:SetPoint("CENTER", 0, 0)
	t:SetTexture(icon)
	b.icon = t
	b:SetScript("OnEnter", function() if this:IsEnabled() == 1 then this:SetBackdropBorderColor(0.9, 0.8, 0.2, 1) end end)
	b:SetScript("OnLeave", function() this:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8) end)
	b:SetScript("OnMouseDown", function() this.icon:SetPoint("CENTER", 1, -1) end)
	b:SetScript("OnMouseUp", function() this.icon:SetPoint("CENTER", 0, 0) end)
	b:SetScript("OnClick", function() LibWidgets.CloseAllMenus(); onClick() end)
	return b
end

-- Leading tristate chip: a colour-tinted circle swatch that cycles through
-- leadingControl.states on click. iconPath is the caller's spec.textureDir-
-- resolving helper (see LibWidgets.NewListEditor), passed in rather than closed over
-- since this factory is shared across every instance.
local function buildTristate(row, lc, iconPath)
	local b = CreateFrame("Button", nil, row)
	b:SetWidth(STATE_W); b:SetHeight(18)
	styleFlatButton(b)
	local sw = b:CreateTexture(nil, "ARTWORK")
	sw:SetWidth(12); sw:SetHeight(12)
	sw:SetPoint("CENTER", 0, 0)
	sw:SetTexture(iconPath("circle"))
	b:SetScript("OnClick", function()
		LibWidgets.CloseAllMenus()
		if row.entry ~= nil then lc.cycle(row.entry) end
	end)
	b:SetScript("OnEnter", function()
		this:SetBackdropBorderColor(0.9, 0.8, 0.2, 1)
		if b.tip then
			GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
			GameTooltip:AddLine(b.tip)
			GameTooltip:AddLine("Click to change", 0.5, 0.5, 0.5)
			GameTooltip:Show()
		end
	end)
	b:SetScript("OnLeave", function() this:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8); GameTooltip:Hide() end)
	b.paint = function(entry)
		local key = lc.get(entry)
		for i = 1, table.getn(lc.states) do
			local st = lc.states[i]
			if st.key == key then
				sw:SetVertexColor(st.color[1], st.color[2], st.color[3])
				b.tip = st.tooltip
			end
		end
	end
	return b
end

-- Leading checkbox: a plain enable/disable toggle.
local function buildCheckbox(row, lc)
	local b = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
	b:SetWidth(STATE_W); b:SetHeight(18)
	b:SetScript("OnClick", function()
		LibWidgets.CloseAllMenus()
		if row.entry ~= nil then lc.set(row.entry, this:GetChecked() and true or false) end
	end)
	b.paint = function(entry) b:SetChecked(lc.get(entry) and true or false) end
	return b
end

-- A flat action button in the shared style; see the header comment for spec.
function LibWidgets.NewButton(parent, spec)
	spec = spec or {}
	local b = CreateFrame("Button", nil, parent)
	b:SetWidth(spec.width or 80); b:SetHeight(spec.height or 22)
	styleFlatButton(b)
	local fs = b:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	fs:SetPoint("CENTER", 0, 0)
	fs:SetText(spec.text or "")
	b.label = fs
	function b.setText(text) fs:SetText(text or "") end
	b:SetScript("OnMouseDown", function()
		LibWidgets.CloseAllMenus()
		this.label:SetPoint("CENTER", 1, -1)
	end)
	b:SetScript("OnMouseUp", function() this.label:SetPoint("CENTER", 0, 0) end)
	if spec.onClick then b:SetScript("OnClick", spec.onClick) end
	return b
end

-- A standalone labelled checkbox; see the header comment for spec.
function LibWidgets.NewCheckBox(parent, spec)
	spec = spec or {}
	local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	cb:SetWidth(spec.width or 22); cb:SetHeight(spec.height or 22)
	local fs = cb:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	fs:SetPoint("LEFT", cb, "RIGHT", 2, 0)
	fs:SetText(spec.text or "")
	cb.label = fs
	cb:SetScript("OnClick", function()
		LibWidgets.CloseAllMenus()
		if spec.onClick then spec.onClick(this:GetChecked() and true or false) end
	end)
	-- Resync from external state without echoing back through onClick (OnClick
	-- fires only on a user click, not SetChecked).
	function cb.setChecked(on) cb:SetChecked(on and true or false) end
	if spec.get then cb:SetChecked(spec.get() and true or false) end
	return cb
end

-- A colour swatch opening the stock ColorPickerFrame; see the header comment
-- for spec. OpacitySliderFrame reports 1-alpha, hence the inversions.
function LibWidgets.NewColorSwatch(parent, spec)
	spec = spec or {}
	local get, set = spec.get, spec.set
	local sz = spec.swatchSize or 14
	local b = CreateFrame("Button", nil, parent)
	b:SetWidth(spec.width or 20); b:SetHeight(spec.height or 20)
	b:SetBackdrop(WIDGET_BACKDROP)
	b:SetBackdropColor(0, 0, 0, 1)
	b:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)
	local tex = b:CreateTexture(nil, "OVERLAY")
	tex:SetPoint("CENTER", 0, 0); tex:SetWidth(sz); tex:SetHeight(sz)
	local function paint()
		local c = get() or { 1, 1, 1, 1 }
		tex:SetTexture(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
	end
	paint()
	b.repaint = paint
	b:SetScript("OnClick", function()
		LibWidgets.CloseAllMenus()
		local c = get() or { 1, 1, 1, 1 }
		local cr, cg, cbl, ca = c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
		ColorPickerFrame.func = function()
			local r, g, bl = ColorPickerFrame:GetColorRGB()
			local a = OpacitySliderFrame and (1 - OpacitySliderFrame:GetValue()) or 1
			set({ r, g, bl, a }); paint()
		end
		ColorPickerFrame.opacityFunc = ColorPickerFrame.func
		ColorPickerFrame.cancelFunc = function() set({ cr, cg, cbl, ca }); paint() end
		ColorPickerFrame.opacity = 1 - ca
		ColorPickerFrame.hasOpacity = 1
		ColorPickerFrame:SetColorRGB(cr, cg, cbl)
		ColorPickerFrame:SetFrameStrata("DIALOG")
		ShowUIPanel(ColorPickerFrame)
	end)
	return b
end

-- A tooltip-backdrop-styled edit box; see the header comment for spec.
function LibWidgets.NewTextBox(parent, spec)
	spec = spec or {}
	local e = CreateFrame("EditBox", nil, parent)
	if spec.width then e:SetWidth(spec.width) end
	e:SetHeight(spec.height or 22)
	e:SetAutoFocus(false)
	e:SetFontObject(GameFontHighlightSmall)
	e:SetTextInsets(5, 5, 2, 2)
	e:SetBackdrop(WIDGET_BACKDROP)
	e:SetBackdropColor(0, 0, 0, 0.7)
	e:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)

	-- Greyed placeholder shown only while the box is empty (1.12 has no native
	-- placeholder/SearchBoxTemplate to borrow one from).
	local hint
	if spec.hint then
		hint = e:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		hint:SetPoint("LEFT", 5, 0)
		hint:SetText(spec.hint)
	end
	local function updateHint()
		if hint then
			if e:GetText() == "" then hint:Show() else hint:Hide() end
		end
	end

	-- Seed before wiring OnTextChanged so the initial value doesn't echo through
	-- spec.onChange (matches NewSlider's seed-doesn't-fire-onChange contract).
	if spec.text then e:SetText(spec.text) end
	updateHint()
	if spec.onChange or hint then
		e:SetScript("OnTextChanged", function()
			updateHint()
			if spec.onChange then spec.onChange(this:GetText()) end
		end)
	end

	e:SetScript("OnEditFocusGained", function() LibWidgets.CloseAllMenus() end)
	e:SetScript("OnEnterPressed", function()
		if spec.onCommit then spec.onCommit(this:GetText()) end
		this:ClearFocus()
	end)
	e:SetScript("OnEscapePressed", function() this:ClearFocus() end)
	return e
end

-- A scrollable multi-line edit box; see the header comment for spec. The
-- UIPanelScrollFrameTemplate ScrollFrame needs a unique global name (its
-- scrollbar child is "<name>ScrollBar"), so instances are counted.
local mleSeq = 0
function LibWidgets.NewMultiLineEditBox(parent, spec)
	spec = spec or {}
	mleSeq = mleSeq + 1
	local w = spec.width or 300
	local h = spec.height or 150

	local box = CreateFrame("Frame", nil, parent)
	box:SetWidth(w); box:SetHeight(h)
	box:SetBackdrop(WIDGET_BACKDROP)
	box:SetBackdropColor(0, 0, 0, 0.7)
	box:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)

	local scroll = CreateFrame("ScrollFrame", "LibWidgetsMLE" .. mleSeq .. "Scroll", box, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", box, "TOPLEFT", 5, -5)
	-- UIPanelScrollFrameTemplate parks its scrollbar ~26px in from the right.
	scroll:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -26, 5)

	local edit = CreateFrame("EditBox", nil, scroll)
	edit:SetMultiLine(true)
	edit:SetAutoFocus(false)
	edit:SetFontObject(GameFontHighlightSmall)
	edit:SetTextInsets(4, 4, 4, 4)
	edit:SetWidth(w - 5 - 26 - 8)
	edit:SetHeight(2000) -- generously tall; the scroll frame clips/scrolls it
	if spec.text then edit:SetText(spec.text) end
	edit:SetScript("OnEditFocusGained", function() LibWidgets.CloseAllMenus() end)
	edit:SetScript("OnEscapePressed", function() this:ClearFocus() end)
	edit:SetScript("OnTextChanged", function()
		local sf = this:GetParent()
		sf:UpdateScrollChildRect()
		if spec.onChange then spec.onChange(this:GetText()) end
	end)
	scroll:SetScrollChild(edit)
	scroll:EnableMouseWheel(true)
	scroll:SetScript("OnMouseWheel", function()
		local range = this:GetVerticalScrollRange()
		local v = this:GetVerticalScroll() - arg1 * 20
		if v < 0 then v = 0 elseif v > range then v = range end
		this:SetVerticalScroll(v)
	end)

	box.edit = edit
	function box.setText(t) edit:SetText(t or "") end
	function box.getText() return edit:GetText() end
	function box.clearFocus() edit:ClearFocus() end
	function box.focusSelectAll()
		edit:SetFocus()
		edit:HighlightText()
	end
	return box
end

-- A value-carrying slider; see the header comment for spec.
function LibWidgets.NewSlider(parent, spec)
	local decimals = spec.decimals or 2
	-- editable's edit box eats into the slider bar's share of `width` rather
	-- than extending the total footprint, so a caller that opts in doesn't
	-- also need to re-budget its own layout math.
	local totalW = spec.width or 150
	local inputW = spec.editable and (spec.inputWidth or 44) or 0
	local gap = spec.editable and 6 or 0
	local sliderW = totalW - inputW - gap
	if sliderW < 40 then sliderW = 40 end

	local s = CreateFrame("Slider", spec.name, parent, "OptionsSliderTemplate")
	s:SetMinMaxValues(spec.min, spec.max)
	s:SetValueStep(spec.step)
	s:SetWidth(sliderW); s:SetHeight(16)
	getglobal(spec.name .. "Low"):SetText("")
	getglobal(spec.name .. "High"):SetText("")
	local title = getglobal(spec.name .. "Text")
	local guarding = false

	local input
	if spec.editable then
		input = LibWidgets.NewTextBox(parent, { width = inputW, height = 18 })
		input:SetPoint("LEFT", s, "RIGHT", gap, 0)
	end

	local function paint(v)
		title:SetText(spec.format and spec.format(v) or formatNumber(v, decimals))
		if input then input:SetText(formatNumber(v, decimals)) end
	end

	s:SetScript("OnValueChanged", function()
		if guarding then return end
		LibWidgets.CloseAllMenus()
		if spec.onChange then spec.onChange(this:GetValue()) end
		paint(this:GetValue())
	end)

	if input then
		-- Commits on Enter only (matches NewTextBox's own contract elsewhere in
		-- this library) -- typing doesn't move the slider live, so there's no
		-- feedback loop to guard against mid-edit.
		input:SetScript("OnEnterPressed", function()
			local v = tonumber(this:GetText())
			if v then
				if spec.min and v < spec.min then v = spec.min end
				if spec.max and v > spec.max then v = spec.max end
				s:SetValue(v) -- fires OnValueChanged -> onChange + paint
			else
				paint(s:GetValue()) -- unparseable entry: revert the box
			end
			this:ClearFocus()
		end)
		input:SetScript("OnEscapePressed", function() paint(s:GetValue()); this:ClearFocus() end)
	end

	function s.setValue(v)
		-- Callers can be one step ahead of the value they read (a field added to
		-- a data model after some saved entries predate it, before their next
		-- MergeDefaults pass): SetValue throws a hard "Usage:" error on a
		-- non-number, which would otherwise take down the whole options panel
		-- over one stale field instead of just that slider.
		v = tonumber(v) or spec.min or 0
		guarding = true
		s:SetValue(v)
		guarding = false
		paint(v)
	end
	if spec.get then s.setValue(spec.get()) end
	return s
end

-- The top-level frame in `frame`'s parent chain (the one parented straight to
-- UIParent). A popup hosted here escapes any ScrollFrame that would clip it and
-- the local strata/level stacking of the controls it drops over.
local function topLevelAncestor(frame)
	local f = frame
	while f do
		local p = f:GetParent()
		if not p or p == UIParent or p == WorldFrame then return f end
		f = p
	end
	return frame
end

-- A bare content scroller; see the header comment for spec. The caller anchors
-- the returned ScrollFrame, fills `.content` and sets its height, then calls
-- `.Update()` so the slim right-edge slider re-fits.
function LibWidgets.NewScrollFrame(parent, spec)
	spec = spec or {}
	local wheelStep = spec.wheelStep or 30

	local frame = CreateFrame("ScrollFrame", nil, parent)
	local content = CreateFrame("Frame", nil, frame)
	content:SetWidth(1); content:SetHeight(1)
	frame:SetScrollChild(content)
	frame.content = content

	-- Slim tinted slider, no track/arrow chrome. A normal (non-scroll) child of
	-- the ScrollFrame, so it isn't scrolled or clipped with the content.
	local slider = CreateFrame("Slider", nil, frame)
	slider:SetOrientation("VERTICAL")
	slider:SetWidth(6)
	slider:SetPoint("TOPRIGHT", frame, "TOPRIGHT", spec.sliderInset or 0, 0)
	slider:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", spec.sliderInset or 0, 0)
	slider:SetThumbTexture(WIDGET_BACKDROP.bgFile)   -- recoloured solid below
	slider.thumb = slider:GetThumbTexture()
	slider.thumb:SetTexture(0.5, 0.5, 0.5, 0.9)
	slider.thumb:SetWidth(6)
	slider:SetScript("OnValueChanged", function() frame:SetVerticalScroll(this:GetValue()) end)
	slider:Hide()
	frame.slider = slider

	-- Refit the slider to the current content vs viewport height. Call after
	-- changing the content's height or the frame's own size.
	function frame.Update()
		local view = frame:GetHeight()
		local range = content:GetHeight() - view
		if range < 0 then range = 0 end
		slider:SetMinMaxValues(0, range)
		if range > 0 and view > 0 then
			-- Thumb sized to the visible fraction, floored so it stays grabbable.
			local th = math.floor(view * view / content:GetHeight())
			slider.thumb:SetHeight(th < 16 and 16 or th)
			slider:Show()
		else
			slider:SetValue(0)
			slider:Hide()
		end
	end

	-- arg1 is +1 up / -1 down. Exposed as `.wheel` so children that capture the
	-- wheel focus (item buttons) can forward to it.
	local function wheel()
		local range = content:GetHeight() - frame:GetHeight()
		if range <= 0 then return end
		local new = frame:GetVerticalScroll() - arg1 * wheelStep
		if new < 0 then new = 0 elseif new > range then new = range end
		frame:SetVerticalScroll(new); slider:SetValue(new)
	end
	frame:EnableMouseWheel(true)
	frame:SetScript("OnMouseWheel", wheel)
	frame.wheel = wheel

	return frame
end

-- A value-picker drop button; see the header comment for spec.
function LibWidgets.NewDropButton(parent, spec)
	local values = spec.values
	local labels = spec.labels or {}
	local tips   = spec.tips
	local width  = spec.width or 92
	local itemH  = spec.itemHeight or 14

	local b = CreateFrame("Button", nil, parent)
	b:SetWidth(width); b:SetHeight(spec.height or 20)
	styleFlatButton(b)
	local fs = b:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	fs:SetPoint("CENTER", 0, 0)
	b.label = fs

	-- A down-arrow on the right edge signals the button opens a menu. It needs
	-- the library's own textures path, so it only appears when spec.textureDir is
	-- given. Desaturated grey at rest, green on hover -- the same enabled/disabled
	-- cue the list editor's reorder arrows use.
	if spec.textureDir then
		local arrow = b:CreateTexture(nil, "OVERLAY")
		arrow:SetWidth(9); arrow:SetHeight(9)
		arrow:SetPoint("RIGHT", b, "RIGHT", -5, 0)
		arrow:SetTexture(spec.textureDir .. "down")
		arrow:SetVertexColor(MOVE_NONE[1], MOVE_NONE[2], MOVE_NONE[3])
		b.arrow = arrow
		-- Span the label from the left edge to the arrow and centre-justify, so it
		-- sits centred in the space left of the arrow rather than centred on the
		-- whole button (which the arrow would then crowd off-centre).
		fs:ClearAllPoints()
		fs:SetPoint("LEFT", b, "LEFT", 2, 0)
		fs:SetPoint("RIGHT", arrow, "LEFT", -2, 0)
		fs:SetJustifyH("CENTER")
	end

	function b.setValue(v)
		b.value = v
		fs:SetText(labels[v] or v or "")
	end

	-- Hosted on the button's top-level ancestor (not the button) so a ScrollFrame
	-- in between can't clip it and it doesn't share the rows' strata; still anchored
	-- to the button below so it tracks position.
	local menu = CreateFrame("Frame", nil, spec.menuParent or topLevelAncestor(b))
	menu:SetBackdrop(WIDGET_BACKDROP)
	menu:SetBackdropColor(0, 0, 0, 0.95)
	menu:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.9)
	menu:SetWidth(spec.menuWidth or width)
	menu:SetPoint("TOPLEFT", b, "BOTTOMLEFT", 0, 0)
	menu:SetFrameStrata(spec.menuStrata or "FULLSCREEN_DIALOG")
	menu:SetToplevel(true)
	menu:Hide()
	b.menu = menu

	-- Long menus (e.g. a condition's property list) cap at maxVisible items and
	-- scroll the rest through a NewScrollFrame (its ScrollFrame clips overflow to
	-- the menu border, and its slim slider reads the same as a short menu).
	local maxVisible = spec.maxVisibleItems or 8
	local bodyW = (spec.menuWidth or width) - 8
	local scroll = LibWidgets.NewScrollFrame(menu, { wheelStep = itemH * 2 })
	scroll:SetPoint("TOPLEFT", menu, "TOPLEFT", 4, -4)
	scroll:SetPoint("BOTTOMRIGHT", menu, "BOTTOMRIGHT", -4, 4)
	local content = scroll.content
	content:SetWidth(bodyW)

	-- Entry buttons are pooled so a dynamic menu (spec.values as a function) can be
	-- rebuilt on every open; a static menu builds once below.
	menu.items = {}
	local function menuItem(i)
		local item = menu.items[i]
		if item then return item end
		item = CreateFrame("Button", nil, content)
		item:SetHeight(itemH)
		item:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(i - 1) * itemH)
		item:SetPoint("RIGHT", content, "RIGHT", 0, 0)
		item:EnableMouseWheel(true)
		item:SetScript("OnMouseWheel", scroll.wheel)
		local ifs = item:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
		ifs:SetPoint("LEFT", item, "LEFT", 2, 0)
		item.label = ifs
		local hl = item:CreateTexture(nil, "HIGHLIGHT")
		hl:SetAllPoints(item); hl:SetTexture(0.3, 0.3, 0.8, 0.5)
		item:SetScript("OnClick", function()
			LibWidgets.CloseAllMenus()
			if spec.onSelect then spec.onSelect(this.value) end
			if spec.get then b.setValue(this.value) end
		end)
		if tips then
			item:SetScript("OnEnter", function()
				GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
				GameTooltip:AddLine(tips[this.value] or "")
				GameTooltip:Show()
			end)
			item:SetScript("OnLeave", function() GameTooltip:Hide() end)
		end
		menu.items[i] = item
		return item
	end

	local function buildItems(vals)
		local n = table.getn(vals)
		for i = 1, n do
			local item = menuItem(i)
			item.value = vals[i]
			item.label:SetText(labels[vals[i]] or vals[i])
			item:Show()
		end
		for i = n + 1, table.getn(menu.items) do menu.items[i]:Hide() end

		local visible = n < maxVisible and n or maxVisible
		menu:SetHeight(visible * itemH + 8)
		content:SetHeight(n * itemH)
		scroll:SetVerticalScroll(0)
		scroll.Update()
	end
	if type(values) ~= "function" then buildItems(values) end

	b:SetScript("OnEnter", function()
		this:SetBackdropBorderColor(0.9, 0.8, 0.2, 1)
		if this.arrow then this.arrow:SetVertexColor(MOVE_OK[1], MOVE_OK[2], MOVE_OK[3]) end
		if tips and this.value then
			GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
			GameTooltip:AddLine(tips[this.value] or "")
			GameTooltip:Show()
		end
	end)
	b:SetScript("OnLeave", function()
		this:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8); GameTooltip:Hide()
		if this.arrow then this.arrow:SetVertexColor(MOVE_NONE[1], MOVE_NONE[2], MOVE_NONE[3]) end
	end)
	b:SetScript("OnClick", function()
		if menu:IsShown() then
			LibWidgets.CloseAllMenus()
			return
		end
		-- Don't pop an empty menu -- there's nothing to select.
		local vals = (type(values) == "function") and values() or values
		if not vals or table.getn(vals) == 0 then return end
		if type(values) == "function" then buildItems(vals) end
		LibWidgets.CloseAllMenus()   -- at most one popup open at a time
		-- The high strata alone (above the host panel's) puts the popup over the
		-- controls it covers; SetToplevel handles ordering against sibling
		-- same-strata popups. Deliberately NOT re-levelling the menu on this
		-- client: SetFrameLevel doesn't carry a frame's children with it here, so
		-- bumping the menu would leave its item buttons below the menu's own
		-- near-opaque backdrop, greying them out.
		scroll:SetVerticalScroll(0)   -- always open at the top
		activeMenu = menu
		menu:Show()
		scroll.Update()   -- refit the slider now the menu is laid out
	end)

	if spec.get then b.setValue(spec.get()) end
	return b
end

function LibWidgets.NewListEditor(parent, spec)
	local rowH  = spec.rowHeight or 18
	local vis   = spec.visibleRows or 5
	local pad   = 4
	local listH = vis * rowH + pad * 2
	local function iconPath(name) return (spec.textureDir or "") .. name end

	local listBox = CreateFrame("Frame", nil, parent)
	listBox:SetPoint("TOPLEFT", parent, "TOPLEFT", spec.x or 0, spec.y or 0)
	listBox:SetPoint("RIGHT", parent, "RIGHT", -(spec.rightInset or 16), 0)
	listBox:SetHeight(listH)
	listBox:SetBackdrop(WIDGET_BACKDROP)
	listBox:SetBackdropColor(0, 0, 0, 0.5)
	listBox:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)

	local scroll = CreateFrame("ScrollFrame", spec.nameFrame, listBox, "FauxScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", listBox, "TOPLEFT", pad, -pad)
	scroll:SetPoint("BOTTOMRIGHT", listBox, "BOTTOMRIGHT", -(pad + 18), pad)

	local rows = {}
	local refresh   -- forward decl; row buttons + the drag tracker call it/spec through closures

	-- ---- drag-to-reorder -- ghost row, insertion indicator, cursor-edge
	-- auto-scroll ----
	local drag = { active = false, from = nil, before = nil }
	local trackDrag, endDrag

	local dragLayer = CreateFrame("Frame", nil, listBox)
	dragLayer:SetAllPoints(scroll)
	dragLayer:SetFrameLevel(listBox:GetFrameLevel() + 25)
	local indicator = dragLayer:CreateTexture(nil, "OVERLAY")
	indicator:SetHeight(3)
	indicator:SetTexture(0.95, 0.82, 0.2, 0.95)
	indicator:Hide()

	local ghost = CreateFrame("Frame", nil, UIParent)
	ghost:SetFrameStrata("TOOLTIP")
	ghost:SetWidth(160); ghost:SetHeight(rowH)
	ghost:EnableMouse(false)
	ghost:SetBackdrop(WIDGET_BACKDROP)
	ghost:SetBackdropColor(0, 0, 0, 0.85)
	ghost:SetBackdropBorderColor(0.9, 0.8, 0.2, 0.9)
	ghost:Hide()
	local gName = ghost:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	gName:SetPoint("LEFT", 6, 0)
	gName:SetPoint("RIGHT", ghost, "RIGHT", -6, 0)
	gName:SetJustifyH("LEFT")

	local AUTOSCROLL_EDGE    = rowH
	local AUTOSCROLL_MIN_RPS = 4
	local AUTOSCROLL_MAX_RPS = 20
	local scrollAccum = 0

	trackDrag = function(elapsed)
		local scale  = scroll:GetEffectiveScale()
		local top    = scroll:GetTop() or 0
		local bottom = scroll:GetBottom() or 0
		local _, cyraw = GetCursorPosition()
		local cy = cyraw / scale

		if elapsed and elapsed > 0 then
			local dir, intensity = 0, 0
			if cy > top - AUTOSCROLL_EDGE then
				dir = -1; intensity = (cy - (top - AUTOSCROLL_EDGE)) / AUTOSCROLL_EDGE
			elseif cy < bottom + AUTOSCROLL_EDGE then
				dir = 1; intensity = ((bottom + AUTOSCROLL_EDGE) - cy) / AUTOSCROLL_EDGE
			end
			if dir == 0 then
				scrollAccum = 0
			else
				if intensity > 1 then intensity = 1 end
				local rps = AUTOSCROLL_MIN_RPS + (AUTOSCROLL_MAX_RPS - AUTOSCROLL_MIN_RPS) * intensity
				scrollAccum = scrollAccum + dir * rps * elapsed
				local steps = (scrollAccum >= 0) and math.floor(scrollAccum) or math.ceil(scrollAccum)
				if steps ~= 0 then
					scrollAccum = scrollAccum - steps
					local bar = getglobal(spec.nameFrame .. "ScrollBar")
					if bar then
						local v = bar:GetValue() + steps * rowH
						local lo, hi = bar:GetMinMaxValues()
						if v < lo then v = lo elseif v > hi then v = hi end
						bar:SetValue(v)   -- triggers the scroll + refresh
					end
				end
			end
		end

		local list = spec.list() or {}
		local n = table.getn(list)
		local offset = FauxScrollFrame_GetOffset(scroll)
		local count = n - offset
		if count > vis then count = vis end

		local p = math.floor((top - cy) / rowH + 0.5)
		if p < 0 then p = 0 elseif p > count then p = count end
		drag.before = offset + p + 1

		indicator:ClearAllPoints()
		indicator:SetPoint("TOPLEFT", dragLayer, "TOPLEFT", 0, -p * rowH + 1)
		indicator:SetPoint("TOPRIGHT", dragLayer, "TOPRIGHT", -4, -p * rowH + 1)
		indicator:Show()

		local gscale = ghost:GetEffectiveScale()
		local cx, gcy = GetCursorPosition()
		ghost:ClearAllPoints()
		ghost:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", cx / gscale + 14, gcy / gscale + 8)
	end

	local function beginDrag(row)
		if not row.index then return end
		LibWidgets.CloseAllMenus()
		drag.active = true
		drag.from   = row.index
		drag.before = row.index
		scrollAccum = 0
		GameTooltip:Hide()
		gName:SetText(row.name:GetText())
		ghost:Show()
		trackDrag()
	end

	-- Safety net: a release over some frames (e.g. a focused edit box) can
	-- swallow OnDragStop and strand the drag until reload -- the OnUpdate
	-- poll below finishes it via IsMouseButtonDown instead.
	endDrag = function()
		if not drag.active then return end
		drag.active = false
		scrollAccum = 0
		indicator:Hide()
		ghost:Hide()
		if drag.from and drag.before then
			spec.reorder(drag.from, drag.before)
		end
		drag.from, drag.before = nil, nil
	end

	listBox:SetScript("OnUpdate", function()
		if drag.active then
			trackDrag(arg1)
			if not IsMouseButtonDown("LeftButton") then endDrag() end
		end
	end)

	-- ---- rows ----

	-- Single-step reorder (the arrow buttons): expressed as a boundary move so
	-- it shares spec.reorder's one splice implementation with drag-drop.
	-- Removing the entry first shifts every later index down by one, so
	-- landing it just before index-1 (up) or index+2 (down) both resolve to
	-- a plain swap with the adjacent row once that shift is accounted for.
	local function moveStep(index, dir)
		if dir < 0 then spec.reorder(index, index - 1)
		else spec.reorder(index, index + 2) end
	end

	local function makeRow(i)
		local row = CreateFrame("Frame", nil, listBox)
		row:SetHeight(rowH)
		row:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, -(i - 1) * rowH)
		row:SetPoint("RIGHT", scroll, "RIGHT", -4, 0)

		if spec.remove then
			row.del = iconButton(row, ICON_DELETE, function() spec.remove(row.index) end)
			row.del:SetPoint("RIGHT", 0, 0)
		end
		row.down = iconButton(row, iconPath("down"), function() moveStep(row.index, 1) end)
		if row.del then row.down:SetPoint("RIGHT", row.del, "LEFT", -BTN_GAP, 0)
		else row.down:SetPoint("RIGHT", 0, 0) end
		row.up = iconButton(row, iconPath("up"), function() moveStep(row.index, -1) end)
		row.up:SetPoint("RIGHT", row.down, "LEFT", -BTN_GAP, 0)

		local rightAnchor = row.up
		row.cols = {}
		if spec.columns then
			for ci = table.getn(spec.columns), 1, -1 do
				local coldef = spec.columns[ci]
				local w = coldef.build(row)
				w:SetWidth(coldef.width)
				w:SetPoint("RIGHT", rightAnchor, "LEFT", -COL_GAP, 0)
				row.cols[ci] = w
				rightAnchor = w
			end
		end

		if spec.leadingControl then
			if spec.leadingControl.kind == "checkbox" then
				row.leading = buildCheckbox(row, spec.leadingControl)
			else
				row.leading = buildTristate(row, spec.leadingControl, iconPath)
			end
			row.leading:SetPoint("LEFT", row, "LEFT", 0, 0)
		end

		row.name = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
		if row.leading then row.name:SetPoint("LEFT", row.leading, "RIGHT", 4, 0)
		else row.name:SetPoint("LEFT", row, "LEFT", 2, 0) end
		row.name:SetPoint("RIGHT", rightAnchor, "LEFT", -6, 0)
		row.name:SetJustifyH("LEFT")

		-- Drag handle spans just the name label -- the leading control keeps
		-- its own click-to-cycle/toggle, so it's excluded from the drag
		-- hit-zone.
		local hover = CreateFrame("Frame", nil, row)
		hover:SetPoint("TOPLEFT", row.name, "TOPLEFT", -2, 0)
		hover:SetPoint("BOTTOMRIGHT", row.name, "BOTTOMRIGHT", 0, 0)
		hover:EnableMouse(true)
		hover:RegisterForDrag("LeftButton")
		hover:SetScript("OnDragStart", function() beginDrag(row) end)
		hover:SetScript("OnDragStop", function() endDrag() end)
		row.hover = hover

		rows[i] = row
		return row
	end

	local function paintArrows(row, i, n)
		local canUp, canDown = i > 1, i < n
		local up   = canUp   and MOVE_OK or MOVE_NONE
		local down = canDown and MOVE_OK or MOVE_NONE
		row.up.icon:SetVertexColor(up[1], up[2], up[3])
		row.down.icon:SetVertexColor(down[1], down[2], down[3])
		if canUp then row.up:Enable() else row.up:Disable(); row.up:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8) end
		if canDown then row.down:Enable() else row.down:Disable(); row.down:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8) end
	end

	refresh = function()
		local list = spec.list() or {}
		local n = table.getn(list)
		FauxScrollFrame_Update(scroll, n, vis, rowH)
		local offset = FauxScrollFrame_GetOffset(scroll)
		for i = 1, vis do
			local row = rows[i] or makeRow(i)
			local di = i + offset
			if di <= n then
				local e = list[di]
				row.index = di
				row.entry = e
				row.name:SetText(spec.nameGet(e))
				if spec.nameColor then row.name:SetTextColor(spec.nameColor(e, di)) end
				if row.leading then row.leading.paint(e) end
				if spec.columns then
					for ci = 1, table.getn(spec.columns) do
						spec.columns[ci].update(row.cols[ci], e, di, n)
					end
				end
				paintArrows(row, di, n)
				row:Show()
			else
				row:Hide()
			end
		end
	end

	scroll:SetScript("OnVerticalScroll", function()
		FauxScrollFrame_OnVerticalScroll(rowH, refresh)
	end)
	local function wheel()
		local bar = getglobal(spec.nameFrame .. "ScrollBar")
		if bar then bar:SetValue(bar:GetValue() - arg1 * rowH) end
	end
	scroll:EnableMouseWheel(true); scroll:SetScript("OnMouseWheel", wheel)
	listBox:EnableMouseWheel(true); listBox:SetScript("OnMouseWheel", wheel)

	local totalH = listH
	if spec.add then
		local addBtn = LibWidgets.NewButton(parent, { text = "Add", width = 50, height = 22 })
		addBtn:SetPoint("TOPRIGHT", listBox, "BOTTOMRIGHT", 0, -8)

		-- Forward-declared so `commit` (needed as both addBox's onCommit and
		-- addBtn's onClick) can read the box back regardless of which one fired.
		local addBox
		local function commit()
			local text = addBox:GetText()
			if text and text ~= "" then spec.add.onAdd(text); addBox:SetText("") end
		end
		addBox = LibWidgets.NewTextBox(parent, { onCommit = commit })
		addBox:SetPoint("TOPLEFT", listBox, "BOTTOMLEFT", 0, -8)
		addBox:SetPoint("RIGHT", addBtn, "LEFT", -6, 0)
		addBtn:SetScript("OnClick", commit)

		totalH = totalH + 8 + 22
	end

	refresh()
	return { height = totalH, refresh = refresh, frame = listBox }
end
