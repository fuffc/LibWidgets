-- LibWidgets -- a small, addon-agnostic UI widget library for 1.12 WoW
-- addons. Currently houses one widget, NewListEditor: a bordered
-- FauxScrollFrame-backed row pool with an optional leading tristate/checkbox
-- control, a class/priority-coloured name label, optional trailing
-- per-column widgets, reorder (arrows + full drag-to-reorder with a ghost
-- row, insertion indicator and cursor-edge auto-scroll) and an optional add
-- row. Further widgets are expected to join it under the same library name.
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

local MAJOR, MINOR = "LibWidgets-1.0", 1
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
	b:SetScript("OnClick", onClick)
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
	b:SetScript("OnClick", function() if row.entry ~= nil then lc.cycle(row.entry) end end)
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
		if row.entry ~= nil then lc.set(row.entry, this:GetChecked() and true or false) end
	end)
	b.paint = function(entry) b:SetChecked(lc.get(entry) and true or false) end
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
		local addBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
		addBtn:SetWidth(50); addBtn:SetHeight(22); addBtn:SetText("Add")
		addBtn:SetPoint("TOPRIGHT", listBox, "BOTTOMRIGHT", 0, -8)

		local addBox = CreateFrame("EditBox", nil, parent)
		addBox:SetHeight(22)
		addBox:SetAutoFocus(false)
		addBox:SetFontObject(GameFontHighlightSmall)
		addBox:SetTextInsets(5, 5, 2, 2)
		addBox:SetBackdrop(WIDGET_BACKDROP)
		addBox:SetBackdropColor(0, 0, 0, 0.7)
		addBox:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)
		addBox:SetPoint("TOPLEFT", listBox, "BOTTOMLEFT", 0, -8)
		addBox:SetPoint("RIGHT", addBtn, "LEFT", -6, 0)
		local function commit()
			local text = addBox:GetText()
			if text and text ~= "" then spec.add.onAdd(text); addBox:SetText("") end
		end
		addBox:SetScript("OnEnterPressed", commit)
		addBox:SetScript("OnEscapePressed", function() this:ClearFocus() end)
		addBtn:SetScript("OnClick", commit)

		totalH = totalH + 8 + 22
	end

	refresh()
	return { height = totalH, refresh = refresh, frame = listBox }
end
