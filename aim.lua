local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local WS = game:GetService("Workspace")
local GiS = game:GetService("GuiService")

local inset = Vector2.zero
pcall(function()
	local a = GiS:GetGuiInset()
	if a then inset = a end
end)

local waitT = (task and task.wait) or wait
local spawnT = (task and task.spawn) or spawn or function(f)
	coroutine.wrap(f)()
end
local deferT = (task and task.defer) or function(f)
	spawnT(f)
end

local function log(...)
	pcall(print, "[aim]", ...)
end

local lp = Players.LocalPlayer
local cam = WS.CurrentCamera
local mobile = UIS.TouchEnabled and not UIS.KeyboardEnabled

local function best()
	local t = lp and lp.PlayerGui
	if t then return t end
	local r
	pcall(function()
		r = (gethui and gethui()) or game:GetService("CoreGui")
	end)
	return r
end

local core = best()
log("start | mobile:", mobile, "| parent:", core and core:GetFullName() or "none")

local hasMousePress = type(mouse1press) == "function"
local hasMouseRelease = type(mouse1release) == "function"
local hasMouseClick = type(mouse1click) == "function"
log("triggerbot | mouse1press:", hasMousePress, "| mouse1release:", hasMouseRelease, "| mouse1click:", hasMouseClick)

-- очистка прошлых биндов
pcall(function() RunService:UnbindFromRenderStep("aimMain") end)
pcall(function() RunService:UnbindFromRenderStep("aimEsp") end)

local guis = {}
local function attach(g)
	guis[#guis + 1] = g
	pcall(function()
		g.Parent = core or best()
	end)
end

if core then
	pcall(function()
		for _, c in ipairs(core:GetChildren()) do
			if c:IsA("ScreenGui") and (c.Name == "aim_ui" or c.Name == "aim_ovl" or c.Name == "aim_esp" or c.Name == "aim_diag") then
				c:Destroy()
			end
		end
	end)
end

local diagGui = Instance.new("ScreenGui")
diagGui.Name = "aim_diag"
diagGui.IgnoreGuiInset = true
diagGui.ResetOnSpawn = false
diagGui.DisplayOrder = 999
attach(diagGui)

local diagFrame = Instance.new("Frame")
diagFrame.Position = UDim2.new(0, 10, 0, 54)
diagFrame.Size = UDim2.new(1, -20, 0, 0)
diagFrame.AutomaticSize = Enum.AutomaticSize.Y
diagFrame.BackgroundTransparency = 1
diagFrame.Parent = diagGui

local diagBox = Instance.new("TextLabel")
diagBox.Size = UDim2.new(1, 0, 0, 0)
diagBox.AutomaticSize = Enum.AutomaticSize.Y
diagBox.BackgroundColor3 = Color3.new(0, 0, 0)
diagBox.BackgroundTransparency = 0.1
diagBox.TextColor3 = Color3.fromRGB(255, 95, 95)
diagBox.Font = Enum.Font.Code
diagBox.TextSize = 11
diagBox.TextWrapped = true
diagBox.TextXAlignment = Enum.TextXAlignment.Left
diagBox.TextYAlignment = Enum.TextYAlignment.Top
diagBox.Visible = false
diagBox.Parent = diagFrame

local function setup()
	local WHITE = Color3.new(1, 1, 1)
	local DIM = Color3.fromRGB(48, 48, 52)

	local cfg = {
		aim = { enabled = true, on = false, fov = 120, draw = true, speed = 100, walls = true, team = true, holdBtn = false },
		trig = { enabled = false, react = 60, btn = false },
		move = {
			speedEnabled = true, speed = 3, btnSpd = false,
			jumpEnabled = true, jump = 3, infjump = false, btnJump = false,
			stuck = false, btnStuck = false,
		},
		vis = { esp = false, name = true, hp = true, team = true, btn = false },
	}

	local mods, btnStack, syncBtns

	local rp = RaycastParams.new()
	local ftOk = pcall(function()
		rp.FilterType = Enum.RaycastFilterType.Exclude
	end)
	if not ftOk then
		pcall(function()
			rp.FilterType = Enum.RaycastFilterType.Blacklist
		end)
	end
	rp.FilterDescendantsInstances = {}

	local tpr = RaycastParams.new()
	pcall(function()
		tpr.FilterType = rp.FilterType
	end)
	tpr.FilterDescendantsInstances = {}

	local function mk(c, p, parent)
		local o = Instance.new(c)
		for k, v in pairs(p) do o[k] = v end
		if parent then o.Parent = parent end
		return o
	end

	local function corner(o, r)
		local c = Instance.new("UICorner")
		c.CornerRadius = r
		c.Parent = o
		return c
	end

	local function stroke(o, t, a)
		local s = Instance.new("UIStroke")
		s.Color = WHITE
		s.Thickness = t
		s.Transparency = a
		s.Parent = o
		return s
	end

	local function hum()
		local ch = lp.Character
		if not ch then return end
		local h = ch:FindFirstChildOfClass("Humanoid")
		if h and h.Health > 0 then return h, ch end
	end

	local function same(p)
		if p == lp then return true end
		local t = lp.Team
		if t then return p.Team == t end
		local c = lp.TeamColor
		return p.TeamColor == c and c ~= Enum.TeamColor.White
	end

	local function body(p, tc)
		if p == lp then return end
		local ch = p.Character
		if not ch or ch.Parent == nil then return end
		local h = ch:FindFirstChildOfClass("Humanoid")
		if not h or h.Health <= 0 or h:GetState() == Enum.HumanoidStateType.Dead then return end
		if tc and same(p) then return end
		local root = ch:FindFirstChild("HumanoidRootPart")
		if not root then return end
		local head = ch:FindFirstChild("Head") or root
		return head, root, ch, h
	end

	local function clear(pos, ch)
		if not cfg.aim.walls then return true end
		rp.FilterDescendantsInstances = { lp.Character, ch }
		return WS:Raycast(cam.CFrame.Position, pos - cam.CFrame.Position, rp) == nil
	end

	local target, goal, tPos, tDist, locked

	local function aimPos(head)
		return head.Position - Vector3.new(0, math.min(head.Size.Y * 0.35, 0.5), 0)
	end

	local function score(ang, len, fov)
		return (ang / fov) * 0.5 + (len / 1200) * 0.5
	end

	local function scan()
		local o = cam.CFrame.Position
		local look = cam.CFrame.LookVector
		local fov = math.max(cfg.aim.fov, 20)

		if locked then
			local head, root, ch = body(locked, cfg.aim.team)
			if head then
				local pos = aimPos(head)
				local d = pos - o
				local len = d.Magnitude
				local ang = math.deg(math.acos(math.clamp(look:Dot(d / len), -1, 1)))
				if ang <= fov and clear(pos, ch) then
					return locked, pos, len
				end
			end
			locked = nil
		end

		local best, bp, bd, bs
		for _, p in ipairs(Players:GetPlayers()) do
			local head, root, ch = body(p, cfg.aim.team)
			if head then
				local pos = aimPos(head)
				local d = pos - o
				local len = d.Magnitude
				if len > 0 and len <= 1200 then
					local ang = math.deg(math.acos(math.clamp(look:Dot(d / len), -1, 1)))
					if ang <= fov then
						local sc = score(ang, len, fov)
						if not bs or sc < bs then
							if clear(pos, ch) then
								bs, best, bp, bd = sc, p, pos, len
							end
						end
					end
				end
			end
		end
		if best then
			locked = best
			return best, bp, bd
		end
		return nil
	end

	local function tick(dt)
		if not cam then cam = WS.CurrentCamera end
		if not cfg.aim.enabled then
			cfg.aim.on = false
			goal, target, locked = nil, nil, nil
			return
		end
		if not cfg.aim.on or not cam then
			goal, target, locked = nil, nil, nil
			return
		end
		local h = hum()
		if not h then
			goal, target, locked = nil, nil, nil
			return
		end
		local p, pos, d = scan()
		target, tPos, tDist = p, pos, d
		if not p then
			goal = nil
			return
		end
		goal = CFrame.lookAt(cam.CFrame.Position, pos)
		if cfg.aim.speed >= 95 then
			cam.CFrame = goal
		else
			local k = 0.5 + (cfg.aim.speed / 100) ^ 2 * 60
			cam.CFrame = cam.CFrame:Lerp(goal, math.clamp(1 - math.exp(-k * dt), 0.005, 1))
		end
	end

	local ring

	local function drawRing()
		if not cfg.aim.draw or not cam or not cfg.aim.enabled then
			ring.Visible = false
			return
		end
		ring.Visible = true
		ring.Position = UDim2.fromScale(0.5, 0.5)
		local vp = cam.ViewportSize
		local f = math.clamp(cfg.aim.fov, 20, 179)
		local r = (vp.Y / 2) * math.tan(math.rad(f / 2)) / math.tan(math.rad(cam.FieldOfView / 2))
		r = math.clamp(r, 4, math.min(vp.X, vp.Y) * 2)
		ring.Size = UDim2.fromOffset(r * 2, r * 2)
	end

	local baseUI = mk("ScreenGui", { Name = "aim_ovl", IgnoreGuiInset = true, ResetOnSpawn = false, DisplayOrder = 20 })
	attach(baseUI)

	ring = mk("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), BackgroundTransparency = 1, Size = UDim2.fromOffset(100, 100) }, baseUI)
	corner(ring, UDim.new(1, 0))
	stroke(ring, 1.5, 0.35)

	local ui = mk("ScreenGui", { Name = "aim_ui", IgnoreGuiInset = true, ResetOnSpawn = false, DisplayOrder = 50 })
	attach(ui)

	local menuBtn = mk("TextButton", {
		Name = "menu", Size = UDim2.fromOffset(44, 44), AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 54), BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.2, Text = "", AutoButtonColor = false, Parent = ui,
	}, ui)
	corner(menuBtn, UDim.new(0, 12))
	stroke(menuBtn, 1, 0.7)
	menuBtn.ZIndex = 20

	local micon = mk("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(20, 20), BackgroundTransparency = 1 }, menuBtn)
	local mring = mk("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(15, 15), BackgroundTransparency = 1 }, micon)
	corner(mring, UDim.new(1, 0))
	stroke(mring, 1.5, 0)
	mk("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(3, 3), BackgroundColor3 = WHITE, BorderSizePixel = 0 }, micon)
	corner(_G and nil or micon, UDim.new(1, 0)) -- placeholder, actual dot created below
	-- proper dot
	for _, c in ipairs(micon:GetChildren()) do
		if c:IsA("Frame") and c.Size == UDim2.fromOffset(3, 3) then
			local cc = Instance.new("UICorner")
			cc.CornerRadius = UDim.new(1, 0)
			cc.Parent = c
		end
	end
	for _, d in ipairs({ { 0, -7 }, { 0, 7 }, { -7, 0 }, { 7, 0 } }) do
		mk("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, d[1], 0.5, d[2]),
			Size = d[1] == 0 and UDim2.fromOffset(1, 3) or UDim2.fromOffset(3, 1),
			BackgroundColor3 = WHITE, BorderSizePixel = 0,
		}, micon)
	end

	local frame = mk("Frame", {
		Name = "frame", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 16),
		Size = UDim2.fromScale(0.9, 0.78), BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.12, Visible = false, ClipsDescendants = true, ZIndex = 1, Parent = ui,
	}, ui)
	corner(frame, UDim.new(0, 16))
	stroke(frame, 1, 0.8)

	mk("TextLabel", {
		Position = UDim2.fromOffset(0, 8), Size = UDim2.new(1, 0, 0, 20), BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold, TextSize = 15, TextColor3 = WHITE, Text = "balt.cc", Parent = frame,
	}, frame)

	local close = mk("TextButton", {
		AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 9), Size = UDim2.fromOffset(18, 18),
		BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.85, Text = "x", AutoButtonColor = false,
		Font = Enum.Font.GothamBold, TextSize = 11, TextColor3 = WHITE, Parent = frame,
	}, frame)
	corner(close, UDim.new(1, 0))

	local left = mk("Frame", {
		Position = UDim2.fromOffset(10, 36), Size = UDim2.new(0.25, -14, 1, -46),
		BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.35, Parent = frame,
	}, frame)
	corner(left, UDim.new(0, 12))
	stroke(left, 1, 0.85)

	local right = mk("Frame", {
		AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 36), Size = UDim2.new(0.75, -14, 1, -46),
		BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.35, Parent = frame,
	}, frame)
	corner(right, UDim.new(0, 12))
	stroke(right, 1, 0.85)

	mk("TextLabel", {
		Position = UDim2.fromOffset(10, 6), Size = UDim2.new(1, -20, 0, 14), BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold, TextSize = 10, TextColor3 = Color3.fromRGB(120, 120, 128),
		TextXAlignment = Enum.TextXAlignment.Left, Text = "SECTIONS", Parent = left,
	}, left)

	local tabRow = mk("Frame", {
		Position = UDim2.fromOffset(8, 24), Size = UDim2.new(1, -16, 0, 0), BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.Y, Parent = left,
	}, left)
	mk("UIListLayout", { Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder }, tabRow)
	for _, t in ipairs({ "Combat", "Movement", "Visual", "HotKeys" }) do
		local b = mk("TextButton", {
			Size = UDim2.new(1, 0, 0, 26), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.88,
			Text = t, AutoButtonColor = false, Font = Enum.Font.Gotham, TextSize = 11,
			TextColor3 = Color3.fromRGB(150, 150, 155), Parent = tabRow,
		}, tabRow)
		corner(b, UDim.new(0, 6))
		b.Name = t
	end

	mk("TextLabel", {
		Position = UDim2.fromOffset(10, 6), Size = UDim2.new(1, -20, 0, 14), BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold, TextSize = 10, TextColor3 = Color3.fromRGB(120, 120, 128),
		TextXAlignment = Enum.TextXAlignment.Left, Text = "MODULES", Parent = right,
	}, right)

	local content = mk("ScrollingFrame", {
		Position = UDim2.fromOffset(10, 24), Size = UDim2.new(1, -20, 1, -34), BackgroundTransparency = 1,
		ScrollBarThickness = 2, ScrollBarImageColor3 = Color3.new(1, 1, 1), CanvasSize = UDim2.new(),
		ScrollBarImageTransparency = 0.5, Parent = right,
	}, right)
	mk("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, content)
	mk("UIPadding", { PaddingBottom = UDim.new(0, 10), PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4) }, content)

	content.UIListLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		local y = content.UIListLayout.AbsoluteContentSize.Y
		content.CanvasSize = UDim2.fromOffset(0, y + 10)
	end)

	local function rowH(h)
		return mk("Frame", { Size = UDim2.new(1, 0, 0, h), BackgroundTransparency = 1 })
	end

	local function head(text)
		local f = mk("Frame", { Size = UDim2.new(1, 0, 0, 22), BackgroundTransparency = 1 })
		mk("TextLabel", {
			Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Font = Enum.Font.GothamBold,
			TextSize = 11, TextColor3 = Color3.fromRGB(120, 120, 128), TextXAlignment = Enum.TextXAlignment.Left,
			Text = string.upper(text), Parent = f,
		}, f)
		return f
	end

	local function toggle(parent, text, state, cb)
		local r = rowH(28)
		r.Parent = parent
		mk("TextLabel", {
			Size = UDim2.new(1, -48, 1, 0), BackgroundTransparency = 1, Font = Enum.Font.Gotham,
			TextSize = 11, TextColor3 = Color3.fromRGB(225, 225, 230), TextXAlignment = Enum.TextXAlignment.Left,
			Text = text, Parent = r,
		}, r)
		local b = mk("TextButton", {
			AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -2, 0.5, 0), Size = UDim2.fromOffset(34, 16),
			Text = "", AutoButtonColor = false, BackgroundColor3 = state and WHITE or DIM, BorderSizePixel = 0,
		}, r)
		corner(b, UDim.new(1, 0))
		local k = mk("Frame", { AnchorPoint = Vector2.new(0, 0.5), Size = UDim2.fromOffset(12, 12), BackgroundColor3 = state and Color3.new(0, 0, 0) or WHITE, BorderSizePixel = 0 }, b)
		corner(k, UDim.new(1, 0))
		k.Position = state and UDim2.new(1, -14, 0.5, 0) or UDim2.new(0, 2, 0.5, 0)
		b.MouseButton1Click:Connect(function()
			state = not state
			b.BackgroundColor3 = state and WHITE or DIM
			k.BackgroundColor3 = state and Color3.new(0, 0, 0) or WHITE
			k.Position = state and UDim2.new(1, -14, 0.5, 0) or UDim2.new(0, 2, 0.5, 0)
			cb(state)
		end)
	end

	local function slider(parent, text, min, max, def, step, fmt, cb)
		local r = rowH(34)
		r.Parent = parent
		local l = mk("TextLabel", {
			Size = UDim2.new(1, -4, 0, 13), BackgroundTransparency = 1, Font = Enum.Font.Gotham,
			TextSize = 11, TextColor3 = Color3.fromRGB(225, 225, 230), TextXAlignment = Enum.TextXAlignment.Left,
			Text = text .. ":  " .. fmt(def), Parent = r,
		}, r)
		local tr = mk("Frame", { Position = UDim2.fromOffset(0, 24), Size = UDim2.new(1, -4, 0, 4), BackgroundColor3 = DIM, BorderSizePixel = 0, Parent = r }, r)
		corner(tr, UDim.new(1, 0))
		local fill = mk("Frame", { Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = WHITE, BorderSizePixel = 0, Parent = tr }, tr)
		corner(fill, UDim.new(1, 0))
		local knob = mk("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0, 0.5), Size = UDim2.fromOffset(10, 10), BackgroundColor3 = WHITE, BorderSizePixel = 0, Parent = tr }, tr)
		corner(knob, UDim.new(1, 0))
		local v = def
		local function apply(nv, fire)
			v = math.clamp(nv, min, max)
			if step and step > 0 then
				v = math.floor(v / step + 0.5) * step
				v = math.clamp(v, min, max)
			end
			local a = (v - min) / (max - min)
			fill.Size = UDim2.fromScale(a, 1)
			knob.Position = UDim2.new(a, 0, 0.5, 0)
			l.Text = text .. ":  " .. fmt(v)
			if fire then cb(v) end
		end
		apply(def, false)
		local dg
		tr.InputBegan:Connect(function(i)
			if i.UserInputType == Enum.UserInputType.Touch or i.UserInputType == Enum.UserInputType.MouseButton1 then
				dg = i
				local x = math.clamp((i.Position.X - tr.AbsolutePosition.X) / math.max(tr.AbsoluteSize.X, 1), 0, 1)
				apply(min + (max - min) * x, true)
			end
		end)
		UIS.InputChanged:Connect(function(i)
			if not dg then return end
			local ty = i.UserInputType
			if ty == Enum.UserInputType.Touch and i ~= dg then return end
			if ty ~= Enum.UserInputType.Touch and ty ~= Enum.UserInputType.MouseMovement then return end
			local x = math.clamp((i.Position.X - tr.AbsolutePosition.X) / math.max(tr.AbsoluteSize.X, 1), 0, 1)
			apply(min + (max - min) * x, true)
		end)
		UIS.InputEnded:Connect(function(i)
			if not dg then return end
			local ty = i.UserInputType
			if ty == Enum.UserInputType.Touch and i ~= dg then return end
			dg = nil
		end)
	end

	local function text(parent, t, color)
		local f = mk("Frame", { Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1, Parent = parent }, parent)
		mk("TextLabel", {
			Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Font = Enum.Font.Gotham,
			TextSize = 9, TextColor3 = color or Color3.fromRGB(120, 120, 128), TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true, Text = t, Parent = f,
		}, f)
		return f
	end

	-- ======== CARD LAYOUT ========
	local function rowCards(parent)
		local r = mk("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1 })
		mk("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, r)
		r.Parent = parent
		return r
	end

	local function card(parent, title, enabled, onToggle, fullWidth)
		local size = fullWidth and UDim2.new(1, 0, 0, 0) or UDim2.new(0.5, -3, 0, 0)
		local c = mk("Frame", {
			Size = size,
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 0.55,
			BorderSizePixel = 0,
		})
		corner(c, UDim.new(0, 10))
		stroke(c, 1, 0.85)

		local header = mk("Frame", { Size = UDim2.new(1, 0, 0, 28), BackgroundTransparency = 1 }, c)
		mk("TextLabel", {
			Position = UDim2.fromOffset(10, 0),
			Size = UDim2.new(1, -58, 1, 0),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			TextSize = 12,
			TextColor3 = WHITE,
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = title,
			Parent = header,
		}, header)

		local tState = enabled
		local tb = mk("TextButton", {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -8, 0.5, 0),
			Size = UDim2.fromOffset(34, 16),
			BackgroundColor3 = tState and WHITE or DIM,
			BorderSizePixel = 0,
			Text = "",
			AutoButtonColor = false,
			Parent = header,
		}, header)
		corner(tb, UDim.new(1, 0))
		local tk = mk("Frame", {
			AnchorPoint = Vector2.new(0, 0.5),
			Size = UDim2.fromOffset(12, 12),
			BackgroundColor3 = tState and Color3.new(0, 0, 0) or WHITE,
			BorderSizePixel = 0,
			Parent = tb,
		}, tb)
		corner(tk, UDim.new(1, 0))
		tk.Position = tState and UDim2.new(1, -14, 0.5, 0) or UDim2.new(0, 2, 0.5, 0)
		tb.MouseButton1Click:Connect(function()
			tState = not tState
			tb.BackgroundColor3 = tState and WHITE or DIM
			tk.BackgroundColor3 = tState and Color3.new(0, 0, 0) or WHITE
			tk.Position = tState and UDim2.new(1, -14, 0.5, 0) or UDim2.new(0, 2, 0.5, 0)
			onToggle(tState)
		end)

		local body = mk("Frame", {
			Position = UDim2.fromOffset(0, 28),
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
		}, c)
		mk("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, body)
		mk("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8) }, body)

		c.Parent = parent
		return c, body
	end

	local pages = {}
	local function clearContent()
		for _, c in ipairs(content:GetChildren()) do
			if c:IsA("Frame") then c:Destroy() end
		end
	end

	pages.Combat = function()
		local row = rowCards(content)

		local _, aBody = card(row, "Aimbot", cfg.aim.enabled, function(v) cfg.aim.enabled = v end)
		slider(aBody, "Fov", 20, 179, cfg.aim.fov, 1, tostring, function(v) cfg.aim.fov = v end)
		toggle(aBody, "Draw Fov", cfg.aim.draw, function(v) cfg.aim.draw = v end)
		slider(aBody, "Aim Speed", 1, 100, cfg.aim.speed, 1, tostring, function(v) cfg.aim.speed = v end)
		toggle(aBody, "Wall Check", cfg.aim.walls, function(v) cfg.aim.walls = v end)
		toggle(aBody, "Team Check", cfg.aim.team, function(v) cfg.aim.team = v end)
		toggle(aBody, "Lock AimBtn", cfg.aim.holdBtn, function(v) cfg.aim.holdBtn = v end)

		local _, tBody = card(row, "Triggerbot", cfg.trig.enabled, function(v) cfg.trig.enabled = v; if syncBtns then syncBtns() end end)
		slider(tBody, "Reaction", 0, 500, cfg.trig.react, 1, function(v) return v .. " ms" end, function(v) cfg.trig.react = v end)
		text(tBody, "Holds mouse button while crosshair is on target.")
	end

	pages.Movement = function()
		local row1 = rowCards(content)

		local _, sBody = card(row1, "Speed", cfg.move.speedEnabled, function(v) cfg.move.speedEnabled = v; if syncBtns then syncBtns() end end)
		slider(sBody, "Speed", 1, 5, cfg.move.speed, 0.1, function(v) return string.format("%.1f", v) end, function(v) cfg.move.speed = v end)

		local _, jBody = card(row1, "Jump", cfg.move.jumpEnabled, function(v) cfg.move.jumpEnabled = v; if syncBtns then syncBtns() end end)
		slider(jBody, "Jump", 1, 5, cfg.move.jump, 0.1, function(v) return string.format("%.1f", v) end, function(v) cfg.move.jump = v end)
		toggle(jBody, "Inf Jump", cfg.move.infjump, function(v) cfg.move.infjump = v; if syncBtns then syncBtns() end end)

		local row2 = rowCards(content)
		local _, stBody = card(row2, "AirStuck", cfg.move.stuck, function(v) cfg.move.stuck = v; if syncBtns then syncBtns() end end)
		text(stBody, "Anchors you in place.")
	end

	pages.Visual = function()
		local row = rowCards(content)
		local _, eBody = card(row, "ESP", cfg.vis.esp, function(v) cfg.vis.esp = v; if syncBtns then syncBtns() end end, true)
		toggle(eBody, "Name", cfg.vis.name, function(v) cfg.vis.name = v end)
		toggle(eBody, "Hp", cfg.vis.hp, function(v) cfg.vis.hp = v end)
		toggle(eBody, "Team Check", cfg.vis.team, function(v) cfg.vis.team = v end)
	end

	pages.HotKeys = function()
		head("On-screen Buttons").Parent = content
		toggle(content, "Triggerbot Button", cfg.trig.btn, function(v) cfg.trig.btn = v; syncBtns() end)
		toggle(content, "Speed Button", cfg.move.btnSpd, function(v) cfg.move.btnSpd = v; syncBtns() end)
		toggle(content, "InfJump Button", cfg.move.btnJump, function(v) cfg.move.btnJump = v; syncBtns() end)
		toggle(content, "AirStuck Button", cfg.move.btnStuck, function(v) cfg.move.btnStuck = v; syncBtns() end)
		toggle(content, "ESP Button", cfg.vis.btn, function(v) cfg.vis.btn = v; syncBtns() end)
	end

	local function show(name)
		clearContent()
		for _, b in ipairs(tabRow:GetChildren()) do
			if b:IsA("TextButton") then
				local act = b.Name == name
				b.BackgroundTransparency = act and 0.1 or 0.88
				b.TextColor3 = act and WHITE or Color3.fromRGB(150, 150, 155)
			end
		end
		pages[name]()
		deferT(function()
			content.CanvasSize = UDim2.fromOffset(0, content.UIListLayout.AbsoluteContentSize.Y + 10)
		end)
	end

	for _, b in ipairs(tabRow:GetChildren()) do
		if b:IsA("TextButton") then
			b.MouseButton1Click:Connect(function() show(b.Name) end)
		end
	end

	local function setMenu(v)
		frame.Visible = v
		menuBtn.BackgroundTransparency = v and 0.6 or 0.2
	end

	menuBtn.MouseButton1Click:Connect(function()
		setMenu(not frame.Visible)
		if frame.Visible then show("Combat") end
	end)
	close.MouseButton1Click:Connect(function() setMenu(false) end)

	local lock, lockShackle, lx, ly, tx, ty, lockMoved, lockIn

	local function syncLock()
		if not lock then return end
		if cfg.aim.on and cfg.aim.enabled then
			lockShackle.Position = UDim2.new(0.5, 0, 0, 8)
			lockShackle.Rotation = 0
		else
			lockShackle.Position = UDim2.new(0.5, 7, 0, 4)
			lockShackle.Rotation = 24
		end
	end

	function syncBtns()
		if not mods then return end
		for _, m in ipairs(mods) do
			local vis = m.flag()
			if m.b.Visible ~= vis then
				m.b.Visible = vis
			end
			local on = vis and m.getv()
			m.b.BackgroundColor3 = on and WHITE or Color3.new(0, 0, 0)
			m.b.TextColor3 = on and Color3.new(0, 0, 0) or WHITE
			m.b.BackgroundTransparency = on and 0.1 or 0.2
		end
	end

	if mobile then
		lx, ly = 18, math.floor((cam and cam.ViewportSize.Y or 720) * 0.42)
		tx, ty = lx, ly
		lock = mk("TextButton", {
			AnchorPoint = Vector2.new(0, 0), Position = UDim2.fromOffset(lx, ly), Size = UDim2.fromOffset(92, 92),
			BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.2, ZIndex = 20,
			Text = "", AutoButtonColor = false, BorderSizePixel = 0, Parent = ui,
		}, ui)
		corner(lock, UDim.new(0, 20))
		stroke(lock, 1.2, 0.6)

		local icon = mk("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(46, 46), BackgroundTransparency = 1 }, lock)
		lockShackle = mk("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 8), Size = UDim2.fromOffset(26, 30), BackgroundTransparency = 1 }, icon)
		corner(lockShackle, UDim.new(1, 0))
		stroke(lockShackle, 5, 0)
		local lockBody = mk("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 20), Size = UDim2.fromOffset(34, 24), BackgroundColor3 = WHITE, BorderSizePixel = 0 }, icon)
		corner(lockBody, UDim.new(0, 7))
		local hole = mk("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.42), Size = UDim2.fromOffset(4, 7), BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0 }, lockBody)
		corner(hole, UDim.new(1, 0))

		local px2, py2
		lock.InputBegan:Connect(function(i)
			if i.UserInputType ~= Enum.UserInputType.Touch and i.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
			lockIn = i
			px2, py2 = i.Position.X, i.Position.Y
			lockMoved = false
		end)
		UIS.InputChanged:Connect(function(i)
			if not lockIn then return end
			local tp = i.UserInputType
			if tp == Enum.UserInputType.Touch then
				if i ~= lockIn then return end
			elseif tp ~= Enum.UserInputType.MouseMovement then
				return
			end
			local x = i.Position.X - px2
			local y = i.Position.Y - py2
			px2, py2 = i.Position.X, i.Position.Y
			if cfg.aim.holdBtn then return end
			if not lockMoved then
				if math.abs(x) < 6 and math.abs(y) < 6 then return end
				lockMoved = true
			end
			local vp = cam.ViewportSize
			tx = math.clamp(tx + x, 0, math.max(vp.X - 92, 0))
			ty = math.clamp(ty + y, 0, math.max(vp.Y - 92, 0))
		end)
		UIS.InputEnded:Connect(function(i)
			if not lockIn then return end
			local tp = i.UserInputType
			if tp == Enum.UserInputType.Touch then
				if i ~= lockIn then return end
			elseif tp ~= Enum.UserInputType.MouseButton1 then
				return
			end
			lockIn = nil
			if not lockMoved and cfg.aim.enabled then
				cfg.aim.on = not cfg.aim.on
				syncLock()
			end
		end)
		syncLock()
	end

	btnStack = mk("Frame", {
		Position = UDim2.fromOffset(0, 104), Size = UDim2.new(0, 150, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1, ZIndex = 20,
	}, lock or ui)
	if not lock then
		btnStack.Position = UDim2.fromOffset(18, 320)
	end
	mk("UIListLayout", { Padding = UDim.new(0, 8) }, btnStack)

	mods = {}
	local function addBtn(label, flag, getv, setv)
		local b = mk("TextButton", {
			Size = UDim2.fromOffset(150, 92), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.2,
			Text = label, Visible = false, AutoButtonColor = false, Font = Enum.Font.GothamBold, TextSize = 15,
			TextColor3 = WHITE, BorderSizePixel = 0, ZIndex = 20, Parent = btnStack,
		}, btnStack)
		corner(b, UDim.new(0, 20))
		stroke(b, 1.2, 0.6)
		b.MouseButton1Click:Connect(function()
			setv(not getv())
			syncBtns()
		end)
		mods[#mods + 1] = { b = b, flag = flag, getv = getv }
	end
	addBtn("TRIGGER", function() return cfg.trig.btn end, function() return cfg.trig.enabled end, function(v) cfg.trig.enabled = v end)
	addBtn("SPEED", function() return cfg.move.btnSpd end, function() return cfg.move.speedEnabled end, function(v) cfg.move.speedEnabled = v end)
	addBtn("INFJUMP", function() return cfg.move.btnJump end, function() return cfg.move.infjump end, function(v) cfg.move.infjump = v end)
	addBtn("AIRSTUCK", function() return cfg.move.btnStuck end, function() return cfg.move.stuck end, function(v) cfg.move.stuck = v end)
	addBtn("ESP", function() return cfg.vis.btn end, function() return cfg.vis.esp end, function(v) cfg.vis.esp = v end)

	if mobile then
		RunService.RenderStepped:Connect(function()
			if math.abs(tx - lx) < 0.4 and math.abs(ty - ly) < 0.4 then
				lx, ly = tx, ty
			else
				lx = lx + (tx - lx) * 0.3
				ly = ly + (ty - ly) * 0.3
			end
			lock.Position = UDim2.fromOffset(lx, ly)
		end)
	end

	local espUI = mk("ScreenGui", { Name = "aim_esp", IgnoreGuiInset = true, ResetOnSpawn = false, DisplayOrder = 10 })
	attach(espUI)

	local pool = {}

	local function entry(p)
		local e = pool[p]
		if e then return e end
		local root = mk("Frame", { BackgroundTransparency = 1, BorderSizePixel = 0, Visible = false, Parent = espUI }, espUI)
		corner(root, UDim.new(0, 2))
		local fill = mk("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BackgroundTransparency = 0.92, BorderSizePixel = 0, Parent = root }, root)
		corner(fill, UDim.new(0, 2))
		local st = stroke(root, 1.4, 0.05)
		local nm = mk("TextLabel", {
			AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0, -3), Size = UDim2.new(1, 90, 0, 13),
			BackgroundTransparency = 1, Font = Enum.Font.GothamMedium, TextSize = 11, TextColor3 = WHITE,
			TextStrokeTransparency = 0.4, Visible = false, Parent = root,
		}, root)
		local hpb = mk("Frame", { Position = UDim2.new(0, -7, 0, 0), Size = UDim2.new(0, 3, 1, 0), BackgroundColor3 = Color3.fromRGB(18, 18, 18), BorderSizePixel = 0, Parent = root }, root)
		local hpf = mk("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0), Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(90, 220, 120), BorderSizePixel = 0, Parent = hpb }, hpb)
		e = { root = root, st = st, nm = nm, hpb = hpb, hpf = hpf }
		pool[p] = e
		return e
	end

	Players.PlayerRemoving:Connect(function(p)
		if pool[p] then
			pcall(function()
				if pool[p].root then pool[p].root:Destroy() end
			end)
			pool[p] = nil
		end
	end)

	-- ESP: 8 углов каждой части тела через part.CFrame (жёстко на теле, не зависит от камеры)
	local CORNERS = {
		Vector3.new(-0.5, -0.5, -0.5),
		Vector3.new(-0.5, -0.5,  0.5),
		Vector3.new(-0.5,  0.5, -0.5),
		Vector3.new(-0.5,  0.5,  0.5),
		Vector3.new( 0.5, -0.5, -0.5),
		Vector3.new( 0.5, -0.5,  0.5),
		Vector3.new( 0.5,  0.5, -0.5),
		Vector3.new( 0.5,  0.5,  0.5),
	}

	local function esp()
		if not cfg.vis.esp or not cam then
			for _, e in pairs(pool) do e.root.Visible = false end
			return
		end
		local seen = {}
		for _, p in ipairs(Players:GetPlayers()) do
			if p ~= lp and not (cfg.vis.team and same(p)) then
				local head, root, ch, h = body(p, false)
				if ch then
					local minX, minY, maxX, maxY
					local any = false
					for _, part in ipairs(ch:GetChildren()) do
						if part:IsA("BasePart") and part.Transparency < 1 then
							local cf = part.CFrame
							local sz = part.Size
							for _, cornerV in ipairs(CORNERS) do
								local wp = cf * Vector3.new(sz.X * cornerV.X, sz.Y * cornerV.Y, sz.Z * cornerV.Z)
								local sp = cam:WorldToScreenPoint(wp)
								if sp.Z > 0 then
									minX = math.min(minX or sp.X, sp.X)
									maxX = math.max(maxX or sp.X, sp.X)
									minY = math.min(minY or sp.Y, sp.Y)
									maxY = math.max(maxY or sp.Y, sp.Y)
									any = true
								end
							end
						end
					end
					if any then
						local w = maxX - minX
						local hh = maxY - minY
						if w > 1 and hh > 1 then
							local e = entry(p)
							seen[p] = true
							e.root.Position = UDim2.fromOffset(math.floor(minX + 0.5), math.floor(minY + 0.5))
							e.root.Size = UDim2.fromOffset(math.floor(w + 0.5), math.floor(hh + 0.5))
							e.root.Visible = true
							e.nm.Visible = cfg.vis.name
							e.nm.Text = p.Name
							e.hpb.Visible = cfg.vis.hp
							local frac = math.clamp(h.Health / math.max(h.MaxHealth, 1), 0, 1)
							e.hpf.Size = UDim2.fromScale(1, frac)
							e.hpf.BackgroundColor3 = frac > 0.7 and Color3.fromRGB(90, 220, 120) or frac > 0.45 and Color3.fromRGB(235, 220, 90) or frac > 0.2 and Color3.fromRGB(240, 160, 60) or Color3.fromRGB(235, 70, 70)
						end
					end
				end
			end
		end
		for p, e in pairs(pool) do
			if not seen[p] then e.root.Visible = false end
		end
	end

	local pressing = false
	local onSince

	local function releaseMouse()
		if not pressing then return end
		pressing = false
		if hasMouseRelease then pcall(mouse1release) end
	end

	local function trig()
		if not cfg.trig.enabled then
			releaseMouse()
			return
		end
		if not cam then return end
		if not hasMousePress and not hasMouseClick then return end
		tpr.FilterDescendantsInstances = lp.Character and { lp.Character } or {}
		local hit = WS:Raycast(cam.CFrame.Position, cam.CFrame.LookVector * 1200, tpr)
		local p = hit and Players:GetPlayerFromCharacter(hit.Instance:FindFirstAncestorOfClass("Model"))
		local ok = p and p ~= lp and not (cfg.aim.team and same(p))
		local hh = hum()
		if ok and not hh then ok = false end
		if ok then
			onSince = onSince or os.clock()
			if not pressing and (os.clock() - onSince) * 1000 >= cfg.trig.react then
				if hasMousePress then
					pcall(mouse1press)
					pressing = true
				elseif hasMouseClick then
					pcall(mouse1click)
					pressing = true
					deferT(function()
						waitT(0.05)
						releaseMouse()
					end)
				end
			end
		else
			onSince = nil
			releaseMouse()
		end
	end

	local function spd(v)
		if v <= 3 then return 0.2 + 0.8 * (v - 1) / 2 end
		return 1 + 9 * (v - 3) / 2
	end

	local function jmp(v)
		if v <= 3 then return 0.2 + 0.8 * (v - 1) / 2 end
		return 1 + 4 * (v - 3) / 2
	end

	local baseSpeed, savedVel, stuckOn

	local function moveTick()
		local h, ch = hum()
		if not h then
			stuckOn = nil
			return
		end
		baseSpeed = baseSpeed or h.WalkSpeed
		if baseSpeed <= 0 then baseSpeed = 16 end
		if cfg.move.speedEnabled then
			h.WalkSpeed = baseSpeed * spd(cfg.move.speed)
		else
			h.WalkSpeed = baseSpeed
		end
		if cfg.move.jumpEnabled then
			local f = jmp(cfg.move.jump)
			if h.UseJumpPower then
				h.JumpPower = 50 * f
			else
				h.JumpHeight = 7.2 * f
			end
		end
		local root = ch:FindFirstChild("HumanoidRootPart")
		if root then
			if cfg.move.stuck then
				if not stuckOn then
					stuckOn = true
					savedVel = root.AssemblyLinearVelocity
				end
				if not root.Anchored then root.Anchored = true end
				root.AssemblyLinearVelocity = Vector3.zero
			elseif stuckOn then
				stuckOn = nil
				root.Anchored = false
				if savedVel then root.AssemblyLinearVelocity = savedVel end
			end
		end
	end

	local function airJump()
		if not cfg.move.jumpEnabled or not cfg.move.infjump or cfg.move.stuck then return end
		local h, ch = hum()
		if not h then return end
		local root = ch:FindFirstChild("HumanoidRootPart")
		if not root then return end
		local st = h:GetState()
		if st ~= Enum.HumanoidStateType.Freefall and st ~= Enum.HumanoidStateType.Jumping then return end
		local v = root.AssemblyLinearVelocity
		local vy = h.UseJumpPower and h.JumpPower or math.sqrt(2 * WS.Gravity * h.JumpHeight)
		root.AssemblyLinearVelocity = Vector3.new(v.X, vy, v.Z)
		h:ChangeState(Enum.HumanoidStateType.Jumping)
	end

	lp.CharacterAdded:Connect(function()
		baseSpeed = nil
		stuckOn = nil
		savedVel = nil
	end)

	UIS.InputBegan:Connect(function(i)
		if i.KeyCode == Enum.KeyCode.Space then
			airJump()
		end
		if i.UserInputType == Enum.UserInputType.Touch and mobile then
			local vp = cam.ViewportSize
			if i.Position.X > vp.X * 0.6 and i.Position.Y > vp.Y * 0.5 then
				airJump()
			end
		end
		if not mobile then
			if i.KeyCode == Enum.KeyCode.C and cfg.aim.enabled then
				cfg.aim.on = true
			end
		end
	end)

	UIS.InputEnded:Connect(function(i)
		if not mobile and i.KeyCode == Enum.KeyCode.C then cfg.aim.on = false end
	end)

	WS:GetPropertyChangedSignal("CurrentCamera"):Connect(function() cam = WS.CurrentCamera end)

	spawnT(function()
		while true do
			waitT(0.12)
			if lock then syncLock() end
			syncBtns()
		end
	end)

	pcall(function()
		RunService:BindToRenderStep("aimMain", Enum.RenderPriority.Camera.Value + 10, function(dt)
			tick(dt)
			drawRing()
		end)
	end)

	pcall(function()
		RunService:BindToRenderStep("aimEsp", Enum.RenderPriority.Camera.Value + 11, esp)
	end)

	RunService.RenderStepped:Connect(trig)
	RunService.Heartbeat:Connect(moveTick)

	show("Combat")
	syncBtns()
end

spawnT(function()
	while true do
		waitT(1)
		if not lp then lp = Players.LocalPlayer end
		if not cam then cam = WS.CurrentCamera end
		local up = lp and lp.PlayerGui
		if up and core ~= up then
			core = up
			for _, g in ipairs(guis) do
				pcall(function()
					g.Parent = up
				end)
			end
		end
		for _, g in ipairs(guis) do
			pcall(function()
				if g.Parent == nil then g.Parent = core or best() end
			end)
		end
	end
end)

local ok, err = xpcall(setup, function(e)
	local msg = tostring(e)
	pcall(function()
		msg = msg .. "\n" .. tostring(debug.traceback("", 2))
	end)
	return msg
end)

if not ok then
	diagBox.Text = err
	diagBox.Visible = true
	log("ERROR", err)
else
	log("ready | parent:", core and core:GetFullName() or "none")
end
