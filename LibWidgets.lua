-- LibWidgets -- a small, addon-agnostic UI widget library for 1.12 WoW
-- addons. Currently houses five widgets: NewButton (a flat action button),
-- NewSlider (a value-carrying OptionsSliderTemplate slider), NewTextBox (a
-- tooltip-backdrop-styled edit box), NewDropButton (a value-picker popup
-- button) and NewListEditor (a bordered FauxScrollFrame-backed row pool with
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
-- NewTextBox(parent, spec) -- a single-line edit box with a tooltip-style backdrop
-- (not InputBoxTemplate -- that template's border textures render a black bar at
-- small heights). spec:
--   width (omit to size purely from the caller's own anchors, e.g. a box anchored
--   on both TOPLEFT and RIGHT), height (default 22), text (initial contents)
--   onCommit(text) -- called on Enter (the box then clears focus); Escape clears
--                     focus with no commit. Omit for a read-only display box.
--
-- NewSlider(parent, spec) -- a horizontal OptionsSliderTemplate slider whose title
-- carries the live value instead of the template's Low/High end labels. spec:
--   name          -- unique global frame name (the template needs one to address
--                    "<name>Low"/"<name>High"/"<name>Text")
--   min, max, step, width (default 150)
--   onChange(v)   -- called on every user drag
--   format(v)     -- optional: -> the full title text (defaults to just the number)
--   get()         -- optional: seeds the initial value through the same guard
--                    `.setValue` uses, so seeding never echoes through onChange
-- Returns the slider with a `.setValue(v)` method: sets the value and repaints the
-- title without firing onChange, for resyncing the widget from external state.
--
-- NewDropButton(parent, spec) -- a button showing the current value that drops a
-- popup list of options to change it (no cycling). spec:
--   width, height (button size; height defaults to 20)
--   menuWidth (defaults to width), itemHeight (defaults to 14)
--   values        -- ordered array of stored values (menu order), or a function
--                    returning one: the menu rebuilds on every open (dynamic sets,
--                    e.g. profile names)
--   labels        -- value -> display label; optional (defaults to the raw value)
--   tips          -- value -> tooltip line; optional
--   onSelect(v)   -- called when a menu entry is picked
--   get()         -- optional: when given, the button self-paints from it on build
--                    and after each pick via `.setValue`. Omit it for a caller that
--                    repaints recycled instances itself each draw (`.setValue(v)`
--                    works either way).
--   menuParent, menuStrata -- override the popup's parent/strata; it defaults to
--                    the button itself at "DIALOG", which is enough unless the
--                    button lives inside a ScrollFrame that would clip it.
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

local MAJOR, MINOR = "LibWidgets-1.0", 4
LibWidgets = LibStub:NewLibrary(MAJOR, MINOR)
if not LibWidgets then return end

local BTN_W   = 20
local BTN_GAP = 2
local COL_GAP = 6
local STATE_W = 20

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
	if spec.text then e:SetText(spec.text) end
	e:SetScript("OnEditFocusGained", function() LibWidgets.CloseAllMenus() end)
	e:SetScript("OnEnterPressed", function()
		if spec.onCommit then spec.onCommit(this:GetText()) end
		this:ClearFocus()
	end)
	e:SetScript("OnEscapePressed", function() this:ClearFocus() end)
	return e
end

-- A value-carrying slider; see the header comment for spec.
function LibWidgets.NewSlider(parent, spec)
	local s = CreateFrame("Slider", spec.name, parent, "OptionsSliderTemplate")
	s:SetMinMaxValues(spec.min, spec.max)
	s:SetValueStep(spec.step)
	s:SetWidth(spec.width or 150); s:SetHeight(16)
	getglobal(spec.name .. "Low"):SetText("")
	getglobal(spec.name .. "High"):SetText("")
	local title = getglobal(spec.name .. "Text")
	local guarding = false
	local function paint(v)
		title:SetText(spec.format and spec.format(v) or tostring(v))
	end
	s:SetScript("OnValueChanged", function()
		if guarding then return end
		LibWidgets.CloseAllMenus()
		if spec.onChange then spec.onChange(this:GetValue()) end
		paint(this:GetValue())
	end)
	function s.setValue(v)
		guarding = true
		s:SetValue(v)
		guarding = false
		paint(v)
	end
	if spec.get then s.setValue(spec.get()) end
	return s
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

	function b.setValue(v)
		b.value = v
		fs:SetText(labels[v] or v or "")
	end

	local menu = CreateFrame("Frame", nil, spec.menuParent or b)
	menu:SetBackdrop(WIDGET_BACKDROP)
	menu:SetBackdropColor(0, 0, 0, 0.95)
	menu:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.9)
	menu:SetWidth(spec.menuWidth or width)
	menu:SetPoint("TOPLEFT", b, "BOTTOMLEFT", 0, 0)
	menu:SetFrameStrata(spec.menuStrata or "DIALOG")
	menu:Hide()
	b.menu = menu

	-- Entry buttons are pooled so a dynamic menu (spec.values as a function) can be
	-- rebuilt on every open; a static menu builds once below.
	menu.items = {}
	local function menuItem(i)
		local item = menu.items[i]
		if item then return item end
		item = CreateFrame("Button", nil, menu)
		item:SetHeight(itemH)
		item:SetPoint("TOPLEFT", menu, "TOPLEFT", 4, -(4 + (i - 1) * itemH))
		item:SetPoint("RIGHT", menu, "RIGHT", -4, 0)
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
		menu:SetHeight(n * itemH + 8)
	end
	if type(values) ~= "function" then buildItems(values) end

	b:SetScript("OnEnter", function()
		this:SetBackdropBorderColor(0.9, 0.8, 0.2, 1)
		if tips and this.value then
			GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
			GameTooltip:AddLine(tips[this.value] or "")
			GameTooltip:Show()
		end
	end)
	b:SetScript("OnLeave", function() this:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8); GameTooltip:Hide() end)
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
		activeMenu = menu
		menu:Show()
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
