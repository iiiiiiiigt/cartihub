-- CartoonHubUI.lua
-- A cartoony Roblox UI library for in-game script hubs.
-- GitHub/loadstring use:
-- local CartoonHubUI = loadstring(game:HttpGet("https://raw.githubusercontent.com/YOUR_NAME/YOUR_REPO/main/CartoonHubUI.lua"))()
-- Normal ModuleScript use:
-- local CartoonHubUI = require(game.ReplicatedStorage:WaitForChild("CartoonHubUI"))

local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")

local LocalPlayer = Players.LocalPlayer

local CartoonHubUI = {}
CartoonHubUI.__index = CartoonHubUI
CartoonHubUI.Version = "1.2.1"

local WINDOW_SIZE = Vector2.new(620, 390)
local SHADOW_SIZE = Vector2.new(640, 410)

local DEFAULT_THEME = {
	Background = Color3.fromRGB(16, 16, 19),
	Panel = Color3.fromRGB(25, 25, 29),
	PanelAlt = Color3.fromRGB(34, 34, 39),
	PanelShadow = Color3.fromRGB(0, 0, 0),
	Primary = Color3.fromRGB(246, 47, 169),
	PrimaryDark = Color3.fromRGB(160, 34, 118),
	Accent = Color3.fromRGB(246, 47, 169),
	AccentDark = Color3.fromRGB(255, 90, 194),
	Success = Color3.fromRGB(75, 217, 154),
	Danger = Color3.fromRGB(255, 80, 111),
	Text = Color3.fromRGB(245, 245, 248),
	Muted = Color3.fromRGB(155, 155, 165),
	Stroke = Color3.fromRGB(55, 55, 64),
	White = Color3.fromRGB(255, 255, 255),
}

local function mergeTheme(theme)
	local merged = {}
	for key, value in pairs(DEFAULT_THEME) do
		merged[key] = value
	end
	for key, value in pairs(theme or {}) do
		merged[key] = value
	end
	return merged
end

local function make(className, props, children)
	local instance = Instance.new(className)
	for key, value in pairs(props or {}) do
		instance[key] = value
	end
	for _, child in ipairs(children or {}) do
		child.Parent = instance
	end
	return instance
end

local function corner(radius)
	return make("UICorner", {
		CornerRadius = UDim.new(0, radius),
	})
end

local function stroke(color, thickness, transparency)
	return make("UIStroke", {
		Color = color,
		Thickness = thickness or 2,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

local function gradient(colorA, colorB, rotation, transparency)
	return make("UIGradient", {
		Color = ColorSequence.new(colorA, colorB),
		Rotation = rotation or 0,
		Transparency = transparency or NumberSequence.new(0),
	})
end

local function padding(left, right, top, bottom)
	return make("UIPadding", {
		PaddingLeft = UDim.new(0, left or 0),
		PaddingRight = UDim.new(0, right or left or 0),
		PaddingTop = UDim.new(0, top or left or 0),
		PaddingBottom = UDim.new(0, bottom or top or left or 0),
	})
end

local function tween(instance, info, props)
	local animation = TweenService:Create(instance, info, props)
	animation:Play()
	return animation
end

local function spring(instance, props)
	return tween(instance, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), props)
end

local function softTween(instance, props)
	return tween(instance, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props)
end

local function textSize(label, minSize, maxSize)
	make("UITextSizeConstraint", {
		MinTextSize = minSize or 12,
		MaxTextSize = maxSize or 18,
		Parent = label,
	})
	label.TextScaled = true
end

local function addHover(button, normalColor, hoverColor)
	button.MouseEnter:Connect(function()
		softTween(button, { BackgroundColor3 = hoverColor })
	end)
	button.MouseLeave:Connect(function()
		softTween(button, { BackgroundColor3 = normalColor })
	end)
end

local function createDragger(handle, target)
	local dragging = false
	local dragStart
	local startPosition

	handle.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end

		dragging = true
		dragStart = input.Position
		startPosition = target.Position

		input.Changed:Connect(function()
			if input.UserInputState == Enum.UserInputState.End then
				dragging = false
			end
		end)
	end)

	UserInputService.InputChanged:Connect(function(input)
		if not dragging then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end

		local delta = input.Position - dragStart
		target.Position = UDim2.new(
			startPosition.X.Scale,
			startPosition.X.Offset + delta.X,
			startPosition.Y.Scale,
			startPosition.Y.Offset + delta.Y
		)
	end)
end

local Window = {}
Window.__index = Window

local Tab = {}
Tab.__index = Tab

local Section = {}
Section.__index = Section

function CartoonHubUI.new(config)
	config = config or {}

	local self = setmetatable({}, CartoonHubUI)
	self.Theme = mergeTheme(config.Theme)
	self.Title = config.Title or "Cartoon Hub"
	self.Subtitle = config.Subtitle or "Adventure tools"
	self.ToggleKey = config.ToggleKey or Enum.KeyCode.RightShift
	self.Tabs = {}

	local parent = config.Parent
	if not parent then
		local playerGui = LocalPlayer and LocalPlayer:WaitForChild("PlayerGui")
		parent = playerGui
	end

	local guiName = config.Name or "CartoonHubUI"
	if parent and config.DestroyExisting ~= false then
		local existing = parent:FindFirstChild(guiName)
		if existing then
			existing:Destroy()
		end
	end

	local gui = make("ScreenGui", {
		Name = guiName,
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = parent,
	})

	local shadow = make("Frame", {
		Name = "Shadow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = self.Theme.PanelShadow,
		BackgroundTransparency = 0.42,
		BorderSizePixel = 0,
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(SHADOW_SIZE.X, SHADOW_SIZE.Y),
		Parent = gui,
	}, {
		corner(24),
	})

	local window = make("Frame", {
		Name = "Window",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = self.Theme.Background,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(WINDOW_SIZE.X, WINDOW_SIZE.Y),
		Parent = gui,
	}, {
		corner(22),
		stroke(self.Theme.Stroke, 1, 0.15),
		gradient(Color3.fromRGB(22, 22, 26), Color3.fromRGB(11, 11, 14), 35),
	})

	local titleBar = make("Frame", {
		Name = "TitleBar",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(0, 196, 0, 76),
		Parent = window,
	})

	local titleCover = make("Frame", {
		Name = "TitleCover",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 0, 1, -18),
		Size = UDim2.new(1, 0, 0, 18),
		Parent = titleBar,
	})

	local icon = make("TextLabel", {
		Name = "Icon",
		BackgroundColor3 = self.Theme.PanelAlt,
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBlack,
		Position = UDim2.fromOffset(18, 22),
		Size = UDim2.fromOffset(30, 30),
		Text = string.sub(self.Title, 1, 1),
		TextColor3 = self.Theme.Text,
		TextSize = 16,
		Parent = titleBar,
	}, {
		corner(8),
		stroke(self.Theme.Stroke, 1, 0.25),
	})

	local title = make("TextLabel", {
		Name = "Title",
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Position = UDim2.fromOffset(60, 18),
		Size = UDim2.new(1, -72, 0, 22),
		Text = self.Title,
		TextColor3 = self.Theme.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = 18,
		Parent = titleBar,
	})

	local subtitle = make("TextLabel", {
		Name = "Subtitle",
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamMedium,
		Position = UDim2.fromOffset(60, 41),
		Size = UDim2.new(1, -72, 0, 16),
		Text = self.Subtitle,
		TextColor3 = self.Theme.Muted,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = 11,
		Parent = titleBar,
	})

	local titleDrag = make("TextButton", {
		Name = "DragHandle",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Text = "",
		Parent = titleBar,
	})

	local close = make("TextButton", {
		Name = "Close",
		AnchorPoint = Vector2.new(1, 0),
		BackgroundColor3 = self.Theme.PanelAlt,
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBold,
		Position = UDim2.new(1, -18, 0, 18),
		Size = UDim2.fromOffset(30, 30),
		Text = "X",
		TextColor3 = self.Theme.Muted,
		TextSize = 14,
		Parent = window,
	}, {
		corner(9),
		stroke(self.Theme.Stroke, 1, 0.25),
	})
	addHover(close, self.Theme.PanelAlt, self.Theme.Danger)

	local profileName = config.ProfileName or "Nimbus"

	local profile = make("Frame", {
		Name = "Profile",
		BackgroundColor3 = self.Theme.Panel,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(18, 78),
		Size = UDim2.fromOffset(164, 48),
		Parent = window,
	}, {
		corner(13),
		stroke(self.Theme.Stroke, 1, 0.32),
		gradient(Color3.fromRGB(42, 42, 48), Color3.fromRGB(28, 28, 33), 0),
	})

	make("TextLabel", {
		Name = "ProfileIcon",
		BackgroundColor3 = self.Theme.PanelAlt,
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBlack,
		Position = UDim2.fromOffset(10, 10),
		Size = UDim2.fromOffset(28, 28),
		Text = string.sub(profileName, 1, 1),
		TextColor3 = self.Theme.Text,
		TextSize = 14,
		Parent = profile,
	}, {
		corner(9),
	})

	make("TextLabel", {
		Name = "ProfileName",
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Position = UDim2.fromOffset(48, 0),
		Size = UDim2.new(1, -74, 1, 0),
		Text = profileName,
		TextColor3 = self.Theme.Text,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = profile,
	})

	make("TextLabel", {
		Name = "Chevron",
		AnchorPoint = Vector2.new(1, 0.5),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(18, 18),
		Text = "v",
		TextColor3 = self.Theme.Muted,
		TextSize = 16,
		Parent = profile,
	})

	local profileDrag = make("TextButton", {
		Name = "DragHandle",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Text = "",
		Parent = profile,
	})

	local sidebar = make("Frame", {
		Name = "Sidebar",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(18, 144),
		Size = UDim2.fromOffset(164, 226),
		Parent = window,
	}, {
		make("UIListLayout", {
			Padding = UDim.new(0, 9),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})

	local divider = make("Frame", {
		Name = "Divider",
		BackgroundColor3 = self.Theme.Stroke,
		BackgroundTransparency = 0.5,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(202, 0),
		Size = UDim2.new(0, 1, 1, 0),
		Parent = window,
	})

	local contentClip = make("Frame", {
		Name = "ContentClip",
		BackgroundColor3 = Color3.fromRGB(13, 13, 16),
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Position = UDim2.fromOffset(224, 58),
		Size = UDim2.new(1, -242, 1, -76),
		Parent = window,
	}, {
		corner(20),
		stroke(self.Theme.Stroke, 1, 0.35),
	})

	local notificationHolder = make("Frame", {
		Name = "Notifications",
		AnchorPoint = Vector2.new(1, 1),
		BackgroundTransparency = 1,
		Position = UDim2.new(1, -18, 1, -18),
		Size = UDim2.fromOffset(260, 250),
		Parent = gui,
	}, {
		make("UIListLayout", {
			Padding = UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
			VerticalAlignment = Enum.VerticalAlignment.Bottom,
		}),
	})

	self.Gui = gui
	self.Shadow = shadow
	self.Window = window
	self.TitleBar = titleBar
	self.Sidebar = sidebar
	self.ContentClip = contentClip
	self.NotificationHolder = notificationHolder

	createDragger(titleDrag, window)
	createDragger(titleDrag, shadow)
	createDragger(profileDrag, window)
	createDragger(profileDrag, shadow)

	close.Activated:Connect(function()
		self:SetVisible(false)
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == self.ToggleKey then
			self:SetVisible(not self.Visible)
		end
	end)

	self.Visible = true
	return setmetatable(self, Window)
end

function Window:SetVisible(visible)
	self.Visible = visible
	local targetSize = visible and UDim2.fromOffset(WINDOW_SIZE.X, WINDOW_SIZE.Y) or UDim2.fromOffset(WINDOW_SIZE.X, 0)
	local shadowSize = visible and UDim2.fromOffset(SHADOW_SIZE.X, SHADOW_SIZE.Y) or UDim2.fromOffset(SHADOW_SIZE.X, 0)
	self.Gui.Enabled = true
	spring(self.Window, { Size = targetSize })
	spring(self.Shadow, { Size = shadowSize })
	task.delay(0.18, function()
		if not self.Visible then
			self.Gui.Enabled = false
		end
	end)
end

function Window:Destroy()
	self.Gui:Destroy()
end

function Window:Notify(options)
	options = options or {}

	local card = make("Frame", {
		Name = "Notification",
		BackgroundColor3 = self.Theme.Panel,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(240, 70),
		Parent = self.NotificationHolder,
	}, {
		corner(15),
		stroke(self.Theme.Stroke, 1, 0.25),
		gradient(Color3.fromRGB(31, 31, 36), Color3.fromRGB(20, 20, 24), 0),
		padding(14, 14, 10, 10),
	})

	make("TextLabel", {
		Name = "Title",
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Size = UDim2.new(1, 0, 0, 21),
		Text = options.Title or "Heads up!",
		TextColor3 = self.Theme.Text,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = card,
	})

	make("TextLabel", {
		Name = "Body",
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamSemibold,
		Position = UDim2.fromOffset(0, 25),
		Size = UDim2.new(1, 0, 0, 28),
		Text = options.Body or "",
		TextColor3 = self.Theme.Muted,
		TextSize = 12,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Parent = card,
	})

	card.Position = UDim2.fromOffset(18, 0)
	card.BackgroundTransparency = 1
	spring(card, {
		Position = UDim2.fromOffset(0, 0),
		BackgroundTransparency = 0,
	})

	task.delay(options.Duration or 3, function()
		if card.Parent then
			softTween(card, {
				Position = UDim2.fromOffset(24, 0),
				BackgroundTransparency = 1,
			})
			task.wait(0.2)
			card:Destroy()
		end
	end)
end

function Window:CreateTab(name, iconText)
	local tab = setmetatable({
		Window = self,
		Name = name,
		Sections = {},
		Active = false,
	}, Tab)

	local button = make("TextButton", {
		Name = name .. "Tab",
		BackgroundColor3 = Color3.fromRGB(18, 18, 22),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBold,
		Size = UDim2.new(1, 0, 0, 44),
		Text = "",
		Parent = self.Sidebar,
	}, {
		corner(16),
		stroke(self.Theme.Stroke, 1, 1),
		gradient(Color3.fromRGB(42, 43, 50), Color3.fromRGB(25, 25, 30), 0),
	})

	local glow = make("Frame", {
		Name = "Glow",
		AnchorPoint = Vector2.new(1, 0.5),
		BackgroundColor3 = self.Theme.Primary,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.new(1, -4, 0.5, 0),
		Size = UDim2.fromOffset(4, 30),
		Parent = button,
	}, {
		corner(99),
	})

	make("TextLabel", {
		Name = "Icon",
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Position = UDim2.fromOffset(14, 8),
		Size = UDim2.fromOffset(28, 28),
		Text = iconText or "#",
		TextColor3 = self.Theme.Muted,
		TextSize = 16,
		Parent = button,
	})

	local label = make("TextLabel", {
		Name = "Label",
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Position = UDim2.fromOffset(48, 0),
		Size = UDim2.new(1, -64, 1, 0),
		Text = name,
		TextColor3 = self.Theme.Muted,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = button,
	})

	local page = make("ScrollingFrame", {
		Name = name .. "Page",
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.fromOffset(0, 0),
		Position = UDim2.fromOffset(14, 14),
		ScrollBarImageColor3 = self.Theme.AccentDark,
		ScrollBarThickness = 5,
		Size = UDim2.new(1, -28, 1, -28),
		Visible = false,
		Parent = self.ContentClip,
	}, {
		make("UIListLayout", {
			Padding = UDim.new(0, 9),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
		padding(0, 8, 0, 4),
	})

	tab.Button = button
	tab.Glow = glow
	tab.Label = label
	tab.Page = page
	table.insert(self.Tabs, tab)

	button.Activated:Connect(function()
		self:SelectTab(tab)
	end)

	if #self.Tabs == 1 then
		self:SelectTab(tab)
	end

	return tab
end

function Window:SelectTab(selectedTab)
	for _, tab in ipairs(self.Tabs) do
		local isActive = tab == selectedTab
		tab.Active = isActive
		tab.Page.Visible = isActive
		softTween(tab.Button, {
			BackgroundTransparency = isActive and 0 or 1,
		})
		softTween(tab.Glow, {
			BackgroundTransparency = isActive and 0 or 1,
		})
		softTween(tab.Label, {
			TextColor3 = isActive and self.Theme.Text or self.Theme.Muted,
		})
	end
end

function Tab:CreateSection(name)
	local section = setmetatable({
		Tab = self,
		Window = self.Window,
		Name = name,
	}, Section)

	local frame = make("Frame", {
		Name = name .. "Section",
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Color3.fromRGB(20, 20, 24),
		BorderSizePixel = 0,
		Size = UDim2.new(1, -2, 0, 0),
		Parent = self.Page,
	}, {
		corner(18),
		stroke(self.Window.Theme.Stroke, 1, 0.35),
		gradient(Color3.fromRGB(27, 27, 32), Color3.fromRGB(17, 17, 20), 90),
		padding(12, 12, 10, 12),
		make("UIListLayout", {
			Padding = UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})

	make("TextLabel", {
		Name = "Header",
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Size = UDim2.new(1, 0, 0, 24),
		Text = name,
		TextColor3 = self.Window.Theme.Text,
		TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = frame,
	})

	section.Frame = frame
	table.insert(self.Sections, section)
	return section
end

function Section:AddLabel(text)
	local label = make("TextLabel", {
		Name = "Label",
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Size = UDim2.new(1, 0, 0, 19),
		Text = text,
		TextColor3 = self.Window.Theme.Muted,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = self.Frame,
	})

	return {
		SetText = function(_, newText)
			label.Text = newText
		end,
		Instance = label,
	}
end

function Section:AddButton(options)
	options = options or {}

	local button = make("TextButton", {
		Name = options.Name or "Button",
		BackgroundColor3 = options.Color or self.Window.Theme.PanelAlt,
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBold,
		Size = UDim2.new(1, 0, 0, 36),
		Text = options.Name or "Button",
		TextColor3 = self.Window.Theme.White,
		TextSize = 14,
		Parent = self.Frame,
	}, {
		corner(12),
		stroke(self.Window.Theme.Stroke, 1, 0.25),
		gradient(Color3.fromRGB(48, 48, 56), Color3.fromRGB(28, 28, 34), 0),
	})

	textSize(button, 12, 15)
	addHover(button, options.Color or self.Window.Theme.PanelAlt, self.Window.Theme.PrimaryDark)

	button.Activated:Connect(function()
		spring(button, { Size = UDim2.new(1, 0, 0, 33) })
		task.delay(0.08, function()
			if button.Parent then
				spring(button, { Size = UDim2.new(1, 0, 0, 36) })
			end
		end)
		if options.Callback then
			options.Callback()
		end
	end)

	return button
end

function Section:AddToggle(options)
	options = options or {}
	local value = options.Default == true

	local row = make("TextButton", {
		Name = options.Name or "Toggle",
		BackgroundColor3 = self.Window.Theme.PanelAlt,
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBold,
		Size = UDim2.new(1, 0, 0, 38),
		Text = "",
		Parent = self.Frame,
	}, {
		corner(12),
		stroke(self.Window.Theme.Stroke, 1, 0.28),
	})

	make("TextLabel", {
		Name = "Label",
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Position = UDim2.fromOffset(14, 0),
		Size = UDim2.new(1, -82, 1, 0),
		Text = options.Name or "Toggle",
		TextColor3 = self.Window.Theme.Text,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = row,
	})

	local track = make("Frame", {
		Name = "Track",
		AnchorPoint = Vector2.new(1, 0.5),
		BackgroundColor3 = value and self.Window.Theme.Primary or Color3.fromRGB(52, 52, 60),
		BorderSizePixel = 0,
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(46, 24),
		Parent = row,
	}, {
		corner(99),
		stroke(self.Window.Theme.Stroke, 1, 0.2),
	})

	local knob = make("Frame", {
		Name = "Knob",
		BackgroundColor3 = self.Window.Theme.White,
		BorderSizePixel = 0,
		Position = value and UDim2.fromOffset(24, 4) or UDim2.fromOffset(4, 4),
		Size = UDim2.fromOffset(16, 16),
		Parent = track,
	}, {
		corner(99),
	})

	local function set(newValue, skipCallback)
		value = newValue
		softTween(track, {
			BackgroundColor3 = value and self.Window.Theme.Primary or Color3.fromRGB(52, 52, 60),
		})
		spring(knob, {
			Position = value and UDim2.fromOffset(24, 4) or UDim2.fromOffset(4, 4),
		})
		if options.Callback and not skipCallback then
			options.Callback(value)
		end
	end

	row.Activated:Connect(function()
		set(not value)
	end)

	return {
		Set = set,
		Get = function()
			return value
		end,
		Instance = row,
	}
end

function Section:AddSlider(options)
	options = options or {}
	local min = options.Min or 0
	local max = options.Max or 100
	local value = math.clamp(options.Default or min, min, max)
	local dragging = false

	local row = make("Frame", {
		Name = options.Name or "Slider",
		BackgroundColor3 = self.Window.Theme.PanelAlt,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 54),
		Parent = self.Frame,
	}, {
		corner(12),
		stroke(self.Window.Theme.Stroke, 1, 0.28),
	})

	make("TextLabel", {
		Name = "Label",
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Position = UDim2.fromOffset(12, 7),
		Size = UDim2.new(1, -92, 0, 18),
		Text = options.Name or "Slider",
		TextColor3 = self.Window.Theme.Text,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = row,
	})

	local valueLabel = make("TextLabel", {
		Name = "Value",
		AnchorPoint = Vector2.new(1, 0),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Position = UDim2.new(1, -12, 0, 7),
		Size = UDim2.fromOffset(64, 18),
		Text = tostring(value),
		TextColor3 = self.Window.Theme.Accent,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = row,
	})

	local bar = make("TextButton", {
		Name = "Bar",
		BackgroundColor3 = Color3.fromRGB(52, 52, 60),
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(12, 34),
		Size = UDim2.new(1, -24, 0, 9),
		Text = "",
		Parent = row,
	}, {
		corner(99),
		stroke(self.Window.Theme.Stroke, 1, 0.35),
	})

	local fill = make("Frame", {
		Name = "Fill",
		BackgroundColor3 = self.Window.Theme.Primary,
		BorderSizePixel = 0,
		Size = UDim2.fromScale((value - min) / (max - min), 1),
		Parent = bar,
	}, {
		corner(99),
	})

	local function setFromX(x, skipCallback)
		local percent = math.clamp((x - bar.AbsolutePosition.X) / bar.AbsoluteSize.X, 0, 1)
		local raw = min + (max - min) * percent
		local step = options.Step or 1
		value = math.floor((raw / step) + 0.5) * step
		value = math.clamp(value, min, max)
		valueLabel.Text = tostring(value)
		softTween(fill, { Size = UDim2.fromScale((value - min) / (max - min), 1) })
		if options.Callback and not skipCallback then
			options.Callback(value)
		end
	end

	bar.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			setFromX(input.Position.X)
		end
	end)

	UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			setFromX(input.Position.X)
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)

	return {
		Set = function(_, newValue, skipCallback)
			value = math.clamp(newValue, min, max)
			valueLabel.Text = tostring(value)
			softTween(fill, { Size = UDim2.fromScale((value - min) / (max - min), 1) })
			if options.Callback and not skipCallback then
				options.Callback(value)
			end
		end,
		Get = function()
			return value
		end,
		Instance = row,
	}
end

function Section:AddDropdown(options)
	options = options or {}
	local choices = options.Choices or {}
	local selected = options.Default or choices[1] or "Select"
	local open = false

	local holder = make("Frame", {
		Name = options.Name or "Dropdown",
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = self.Window.Theme.PanelAlt,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 38),
		Parent = self.Frame,
	}, {
		corner(12),
		stroke(self.Window.Theme.Stroke, 1, 0.28),
		make("UIListLayout", {
			Padding = UDim.new(0, 4),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})

	local button = make("TextButton", {
		Name = "Button",
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Size = UDim2.new(1, 0, 0, 38),
		Text = "",
		Parent = holder,
	})

	local label = make("TextLabel", {
		Name = "Label",
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Position = UDim2.fromOffset(12, 0),
		Size = UDim2.new(0.45, 0, 1, 0),
		Text = options.Name or "Dropdown",
		TextColor3 = self.Window.Theme.Text,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = button,
	})

	local selectedLabel = make("TextLabel", {
		Name = "Selected",
		AnchorPoint = Vector2.new(1, 0),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Position = UDim2.new(1, -34, 0, 0),
		Size = UDim2.new(0.5, 0, 1, 0),
		Text = tostring(selected),
		TextColor3 = self.Window.Theme.Accent,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = button,
	})

	make("TextLabel", {
		Name = "Arrow",
		AnchorPoint = Vector2.new(1, 0.5),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(18, 18),
		Text = "v",
		TextColor3 = self.Window.Theme.Text,
		TextSize = 14,
		Parent = button,
	})

	local list = make("Frame", {
		Name = "List",
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		Visible = false,
		Parent = holder,
	}, {
		padding(10, 10, 0, 10),
		make("UIListLayout", {
			Padding = UDim.new(0, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})

	local function selectChoice(choice)
		selected = choice
		selectedLabel.Text = tostring(choice)
		open = false
		list.Visible = false
		if options.Callback then
			options.Callback(choice)
		end
	end

	local function rebuild(newChoices)
		for _, child in ipairs(list:GetChildren()) do
			if child:IsA("TextButton") then
				child:Destroy()
			end
		end
		choices = newChoices or choices
		for _, choice in ipairs(choices) do
			local item = make("TextButton", {
				Name = tostring(choice),
				BackgroundColor3 = Color3.fromRGB(36, 36, 42),
				BorderSizePixel = 0,
				Font = Enum.Font.GothamBold,
				Size = UDim2.new(1, 0, 0, 28),
				Text = tostring(choice),
				TextColor3 = self.Window.Theme.Text,
				TextSize = 12,
				Parent = list,
			}, {
				corner(10),
				stroke(self.Window.Theme.Stroke, 1, 0.35),
			})
			addHover(item, Color3.fromRGB(36, 36, 42), Color3.fromRGB(48, 48, 56))
			item.Activated:Connect(function()
				selectChoice(choice)
			end)
		end
	end

	rebuild(choices)

	button.Activated:Connect(function()
		open = not open
		list.Visible = open
	end)

	return {
		Set = function(_, choice)
			selectChoice(choice)
		end,
		SetChoices = function(_, newChoices)
			rebuild(newChoices)
		end,
		Get = function()
			return selected
		end,
		Instance = holder,
	}
end

function Section:AddTextbox(options)
	options = options or {}

	local row = make("Frame", {
		Name = options.Name or "Textbox",
		BackgroundColor3 = self.Window.Theme.PanelAlt,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 40),
		Parent = self.Frame,
	}, {
		corner(12),
		stroke(self.Window.Theme.Stroke, 1, 0.28),
	})

	make("TextLabel", {
		Name = "Label",
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Position = UDim2.fromOffset(12, 0),
		Size = UDim2.new(0.36, 0, 1, 0),
		Text = options.Name or "Text",
		TextColor3 = self.Window.Theme.Text,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = row,
	})

	local box = make("TextBox", {
		Name = "Box",
		AnchorPoint = Vector2.new(1, 0.5),
		BackgroundColor3 = Color3.fromRGB(16, 16, 20),
		BorderSizePixel = 0,
		ClearTextOnFocus = false,
		Font = Enum.Font.GothamBold,
		PlaceholderText = options.Placeholder or "Type...",
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.new(0.58, 0, 0, 28),
		Text = options.Default or "",
		TextColor3 = self.Window.Theme.Text,
		PlaceholderColor3 = self.Window.Theme.Muted,
		TextSize = 12,
		Parent = row,
	}, {
		corner(10),
		stroke(self.Window.Theme.Stroke, 1, 0.35),
		padding(10, 10, 0, 0),
	})

	box.FocusLost:Connect(function(enterPressed)
		if options.Callback then
			options.Callback(box.Text, enterPressed)
		end
	end)

	return {
		Set = function(_, text)
			box.Text = text
		end,
		Get = function()
			return box.Text
		end,
		Instance = row,
	}
end

function Section:AddKeybind(options)
	options = options or {}
	local currentKey = options.Default or Enum.KeyCode.F
	local listening = false

	local row = make("TextButton", {
		Name = options.Name or "Keybind",
		BackgroundColor3 = self.Window.Theme.PanelAlt,
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBold,
		Size = UDim2.new(1, 0, 0, 38),
		Text = "",
		Parent = self.Frame,
	}, {
		corner(12),
		stroke(self.Window.Theme.Stroke, 1, 0.28),
	})

	make("TextLabel", {
		Name = "Label",
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Position = UDim2.fromOffset(12, 0),
		Size = UDim2.new(1, -130, 1, 0),
		Text = options.Name or "Keybind",
		TextColor3 = self.Window.Theme.Text,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = row,
	})

	local keyButton = make("TextLabel", {
		Name = "Key",
		AnchorPoint = Vector2.new(1, 0.5),
		BackgroundColor3 = self.Window.Theme.Primary,
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBold,
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.fromOffset(78, 26),
		Text = currentKey.Name,
		TextColor3 = self.Window.Theme.White,
		TextSize = 12,
		Parent = row,
	}, {
		corner(10),
		stroke(self.Window.Theme.Stroke, 1),
	})

	local function setKey(keyCode)
		currentKey = keyCode
		keyButton.Text = currentKey.Name
		if options.Changed then
			options.Changed(currentKey)
		end
	end

	row.Activated:Connect(function()
		listening = true
		keyButton.Text = "Press..."
		softTween(keyButton, { BackgroundColor3 = self.Window.Theme.Accent })
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end

		if listening then
			if input.KeyCode ~= Enum.KeyCode.Unknown then
				listening = false
				softTween(keyButton, { BackgroundColor3 = self.Window.Theme.Primary })
				setKey(input.KeyCode)
			end
			return
		end

		if input.KeyCode == currentKey and options.Callback then
			options.Callback(currentKey)
		end
	end)

	return {
		Set = function(_, keyCode)
			setKey(keyCode)
		end,
		Get = function()
			return currentKey
		end,
		Instance = row,
	}
end

local sharedEnvironment
if typeof(getgenv) == "function" then
	sharedEnvironment = getgenv()
else
	sharedEnvironment = _G
end

sharedEnvironment.CartoonHubUI = CartoonHubUI
return CartoonHubUI
