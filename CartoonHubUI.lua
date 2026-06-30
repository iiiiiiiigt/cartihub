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
CartoonHubUI.Version = "1.1.0"

local DEFAULT_THEME = {
	Background = Color3.fromRGB(255, 246, 222),
	Panel = Color3.fromRGB(255, 255, 250),
	PanelShadow = Color3.fromRGB(83, 58, 68),
	Primary = Color3.fromRGB(82, 183, 255),
	PrimaryDark = Color3.fromRGB(38, 118, 205),
	Accent = Color3.fromRGB(255, 190, 72),
	AccentDark = Color3.fromRGB(226, 124, 55),
	Success = Color3.fromRGB(93, 214, 124),
	Danger = Color3.fromRGB(255, 99, 116),
	Text = Color3.fromRGB(48, 38, 54),
	Muted = Color3.fromRGB(124, 100, 116),
	Stroke = Color3.fromRGB(73, 52, 63),
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
		BackgroundTransparency = 0.78,
		BorderSizePixel = 0,
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(622, 432),
		Parent = gui,
	}, {
		corner(18),
	})

	local window = make("Frame", {
		Name = "Window",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = self.Theme.Background,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(610, 420),
		Parent = gui,
	}, {
		corner(18),
		stroke(self.Theme.Stroke, 3),
	})

	local titleBar = make("Frame", {
		Name = "TitleBar",
		BackgroundColor3 = self.Theme.Accent,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 76),
		Parent = window,
	}, {
		corner(18),
		stroke(self.Theme.Stroke, 2),
	})

	local titleCover = make("Frame", {
		Name = "TitleCover",
		BackgroundColor3 = self.Theme.Accent,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 0, 1, -18),
		Size = UDim2.new(1, 0, 0, 18),
		Parent = titleBar,
	})

	local icon = make("TextLabel", {
		Name = "Icon",
		BackgroundColor3 = self.Theme.White,
		BorderSizePixel = 0,
		Font = Enum.Font.FredokaOne,
		Position = UDim2.fromOffset(18, 14),
		Size = UDim2.fromOffset(46, 46),
		Text = "*",
		TextColor3 = self.Theme.AccentDark,
		TextSize = 30,
		Parent = titleBar,
	}, {
		corner(14),
		stroke(self.Theme.Stroke, 2),
	})

	local title = make("TextLabel", {
		Name = "Title",
		BackgroundTransparency = 1,
		Font = Enum.Font.FredokaOne,
		Position = UDim2.fromOffset(76, 12),
		Size = UDim2.new(1, -150, 0, 30),
		Text = self.Title,
		TextColor3 = self.Theme.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = 25,
		Parent = titleBar,
	})

	local subtitle = make("TextLabel", {
		Name = "Subtitle",
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Position = UDim2.fromOffset(78, 42),
		Size = UDim2.new(1, -160, 0, 18),
		Text = self.Subtitle,
		TextColor3 = self.Theme.Muted,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = 13,
		Parent = titleBar,
	})

	local close = make("TextButton", {
		Name = "Close",
		AnchorPoint = Vector2.new(1, 0),
		BackgroundColor3 = self.Theme.Danger,
		BorderSizePixel = 0,
		Font = Enum.Font.FredokaOne,
		Position = UDim2.new(1, -18, 0, 17),
		Size = UDim2.fromOffset(42, 42),
		Text = "X",
		TextColor3 = self.Theme.White,
		TextSize = 20,
		Parent = titleBar,
	}, {
		corner(13),
		stroke(self.Theme.Stroke, 2),
	})
	addHover(close, self.Theme.Danger, Color3.fromRGB(255, 125, 138))

	local sidebar = make("Frame", {
		Name = "Sidebar",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(16, 92),
		Size = UDim2.fromOffset(158, 312),
		Parent = window,
	}, {
		make("UIListLayout", {
			Padding = UDim.new(0, 9),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})

	local contentClip = make("Frame", {
		Name = "ContentClip",
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		Position = UDim2.fromOffset(190, 92),
		Size = UDim2.new(1, -206, 1, -108),
		Parent = window,
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

	createDragger(titleBar, window)
	createDragger(titleBar, shadow)

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
	local targetSize = visible and UDim2.fromOffset(610, 420) or UDim2.fromOffset(610, 0)
	local shadowSize = visible and UDim2.fromOffset(622, 432) or UDim2.fromOffset(622, 0)
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
		Size = UDim2.fromOffset(260, 76),
		Parent = self.NotificationHolder,
	}, {
		corner(15),
		stroke(self.Theme.Stroke, 2),
		padding(14, 14, 10, 10),
	})

	make("TextLabel", {
		Name = "Title",
		BackgroundTransparency = 1,
		Font = Enum.Font.FredokaOne,
		Size = UDim2.new(1, 0, 0, 23),
		Text = options.Title or "Heads up!",
		TextColor3 = self.Theme.Text,
		TextSize = 17,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = card,
	})

	make("TextLabel", {
		Name = "Body",
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamSemibold,
		Position = UDim2.fromOffset(0, 27),
		Size = UDim2.new(1, 0, 0, 30),
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
		BackgroundColor3 = self.Theme.Panel,
		BorderSizePixel = 0,
		Font = Enum.Font.FredokaOne,
		Size = UDim2.new(1, 0, 0, 48),
		Text = "",
		Parent = self.Sidebar,
	}, {
		corner(14),
		stroke(self.Theme.Stroke, 2),
	})

	make("TextLabel", {
		Name = "Icon",
		BackgroundTransparency = 1,
		Font = Enum.Font.FredokaOne,
		Position = UDim2.fromOffset(12, 8),
		Size = UDim2.fromOffset(30, 30),
		Text = iconText or "#",
		TextColor3 = self.Theme.AccentDark,
		TextSize = 20,
		Parent = button,
	})

	make("TextLabel", {
		Name = "Label",
		BackgroundTransparency = 1,
		Font = Enum.Font.FredokaOne,
		Position = UDim2.fromOffset(46, 0),
		Size = UDim2.new(1, -54, 1, 0),
		Text = name,
		TextColor3 = self.Theme.Text,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = button,
	})

	local page = make("ScrollingFrame", {
		Name = name .. "Page",
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.fromOffset(0, 0),
		ScrollBarImageColor3 = self.Theme.AccentDark,
		ScrollBarThickness = 5,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		Parent = self.ContentClip,
	}, {
		make("UIListLayout", {
			Padding = UDim.new(0, 12),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
		padding(0, 8, 0, 4),
	})

	tab.Button = button
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
			BackgroundColor3 = isActive and self.Theme.Primary or self.Theme.Panel,
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
		BackgroundColor3 = self.Window.Theme.Panel,
		BorderSizePixel = 0,
		Size = UDim2.new(1, -2, 0, 0),
		Parent = self.Page,
	}, {
		corner(16),
		stroke(self.Window.Theme.Stroke, 2),
		padding(14, 14, 12, 14),
		make("UIListLayout", {
			Padding = UDim.new(0, 10),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})

	make("TextLabel", {
		Name = "Header",
		BackgroundTransparency = 1,
		Font = Enum.Font.FredokaOne,
		Size = UDim2.new(1, 0, 0, 24),
		Text = name,
		TextColor3 = self.Window.Theme.Text,
		TextSize = 19,
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
		Size = UDim2.new(1, 0, 0, 22),
		Text = text,
		TextColor3 = self.Window.Theme.Muted,
		TextSize = 14,
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
		BackgroundColor3 = options.Color or self.Window.Theme.Primary,
		BorderSizePixel = 0,
		Font = Enum.Font.FredokaOne,
		Size = UDim2.new(1, 0, 0, 44),
		Text = options.Name or "Button",
		TextColor3 = self.Window.Theme.White,
		TextSize = 16,
		Parent = self.Frame,
	}, {
		corner(14),
		stroke(self.Window.Theme.Stroke, 2),
	})

	textSize(button, 13, 17)
	addHover(button, options.Color or self.Window.Theme.Primary, self.Window.Theme.PrimaryDark)

	button.Activated:Connect(function()
		spring(button, { Size = UDim2.new(1, 0, 0, 40) })
		task.delay(0.08, function()
			if button.Parent then
				spring(button, { Size = UDim2.new(1, 0, 0, 44) })
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
		BackgroundColor3 = Color3.fromRGB(255, 250, 239),
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBold,
		Size = UDim2.new(1, 0, 0, 46),
		Text = "",
		Parent = self.Frame,
	}, {
		corner(14),
		stroke(self.Window.Theme.Stroke, 2),
	})

	make("TextLabel", {
		Name = "Label",
		BackgroundTransparency = 1,
		Font = Enum.Font.FredokaOne,
		Position = UDim2.fromOffset(14, 0),
		Size = UDim2.new(1, -82, 1, 0),
		Text = options.Name or "Toggle",
		TextColor3 = self.Window.Theme.Text,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = row,
	})

	local track = make("Frame", {
		Name = "Track",
		AnchorPoint = Vector2.new(1, 0.5),
		BackgroundColor3 = value and self.Window.Theme.Success or Color3.fromRGB(218, 206, 199),
		BorderSizePixel = 0,
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(54, 28),
		Parent = row,
	}, {
		corner(99),
		stroke(self.Window.Theme.Stroke, 2),
	})

	local knob = make("Frame", {
		Name = "Knob",
		BackgroundColor3 = self.Window.Theme.White,
		BorderSizePixel = 0,
		Position = value and UDim2.fromOffset(28, 4) or UDim2.fromOffset(4, 4),
		Size = UDim2.fromOffset(20, 20),
		Parent = track,
	}, {
		corner(99),
	})

	local function set(newValue, skipCallback)
		value = newValue
		softTween(track, {
			BackgroundColor3 = value and self.Window.Theme.Success or Color3.fromRGB(218, 206, 199),
		})
		spring(knob, {
			Position = value and UDim2.fromOffset(28, 4) or UDim2.fromOffset(4, 4),
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
		BackgroundColor3 = Color3.fromRGB(255, 250, 239),
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 66),
		Parent = self.Frame,
	}, {
		corner(14),
		stroke(self.Window.Theme.Stroke, 2),
	})

	make("TextLabel", {
		Name = "Label",
		BackgroundTransparency = 1,
		Font = Enum.Font.FredokaOne,
		Position = UDim2.fromOffset(14, 8),
		Size = UDim2.new(1, -100, 0, 20),
		Text = options.Name or "Slider",
		TextColor3 = self.Window.Theme.Text,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = row,
	})

	local valueLabel = make("TextLabel", {
		Name = "Value",
		AnchorPoint = Vector2.new(1, 0),
		BackgroundTransparency = 1,
		Font = Enum.Font.FredokaOne,
		Position = UDim2.new(1, -14, 0, 8),
		Size = UDim2.fromOffset(72, 20),
		Text = tostring(value),
		TextColor3 = self.Window.Theme.AccentDark,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = row,
	})

	local bar = make("TextButton", {
		Name = "Bar",
		BackgroundColor3 = Color3.fromRGB(230, 218, 208),
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(14, 40),
		Size = UDim2.new(1, -28, 0, 12),
		Text = "",
		Parent = row,
	}, {
		corner(99),
		stroke(self.Window.Theme.Stroke, 1),
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
		BackgroundColor3 = Color3.fromRGB(255, 250, 239),
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 46),
		Parent = self.Frame,
	}, {
		corner(14),
		stroke(self.Window.Theme.Stroke, 2),
		make("UIListLayout", {
			Padding = UDim.new(0, 4),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})

	local button = make("TextButton", {
		Name = "Button",
		BackgroundTransparency = 1,
		Font = Enum.Font.FredokaOne,
		Size = UDim2.new(1, 0, 0, 46),
		Text = "",
		Parent = holder,
	})

	local label = make("TextLabel", {
		Name = "Label",
		BackgroundTransparency = 1,
		Font = Enum.Font.FredokaOne,
		Position = UDim2.fromOffset(14, 0),
		Size = UDim2.new(0.45, 0, 1, 0),
		Text = options.Name or "Dropdown",
		TextColor3 = self.Window.Theme.Text,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = button,
	})

	local selectedLabel = make("TextLabel", {
		Name = "Selected",
		AnchorPoint = Vector2.new(1, 0),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Position = UDim2.new(1, -38, 0, 0),
		Size = UDim2.new(0.5, 0, 1, 0),
		Text = tostring(selected),
		TextColor3 = self.Window.Theme.AccentDark,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = button,
	})

	make("TextLabel", {
		Name = "Arrow",
		AnchorPoint = Vector2.new(1, 0.5),
		BackgroundTransparency = 1,
		Font = Enum.Font.FredokaOne,
		Position = UDim2.new(1, -14, 0.5, 0),
		Size = UDim2.fromOffset(18, 18),
		Text = "v",
		TextColor3 = self.Window.Theme.Text,
		TextSize = 16,
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
				BackgroundColor3 = self.Window.Theme.White,
				BorderSizePixel = 0,
				Font = Enum.Font.GothamBold,
				Size = UDim2.new(1, 0, 0, 34),
				Text = tostring(choice),
				TextColor3 = self.Window.Theme.Text,
				TextSize = 13,
				Parent = list,
			}, {
				corner(10),
				stroke(self.Window.Theme.Stroke, 1),
			})
			addHover(item, self.Window.Theme.White, Color3.fromRGB(245, 239, 230))
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
		BackgroundColor3 = Color3.fromRGB(255, 250, 239),
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 50),
		Parent = self.Frame,
	}, {
		corner(14),
		stroke(self.Window.Theme.Stroke, 2),
	})

	make("TextLabel", {
		Name = "Label",
		BackgroundTransparency = 1,
		Font = Enum.Font.FredokaOne,
		Position = UDim2.fromOffset(14, 0),
		Size = UDim2.new(0.36, 0, 1, 0),
		Text = options.Name or "Text",
		TextColor3 = self.Window.Theme.Text,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = row,
	})

	local box = make("TextBox", {
		Name = "Box",
		AnchorPoint = Vector2.new(1, 0.5),
		BackgroundColor3 = self.Window.Theme.White,
		BorderSizePixel = 0,
		ClearTextOnFocus = false,
		Font = Enum.Font.GothamBold,
		PlaceholderText = options.Placeholder or "Type...",
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.new(0.58, 0, 0, 32),
		Text = options.Default or "",
		TextColor3 = self.Window.Theme.Text,
		TextSize = 13,
		Parent = row,
	}, {
		corner(10),
		stroke(self.Window.Theme.Stroke, 1),
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
		BackgroundColor3 = Color3.fromRGB(255, 250, 239),
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBold,
		Size = UDim2.new(1, 0, 0, 46),
		Text = "",
		Parent = self.Frame,
	}, {
		corner(14),
		stroke(self.Window.Theme.Stroke, 2),
	})

	make("TextLabel", {
		Name = "Label",
		BackgroundTransparency = 1,
		Font = Enum.Font.FredokaOne,
		Position = UDim2.fromOffset(14, 0),
		Size = UDim2.new(1, -130, 1, 0),
		Text = options.Name or "Keybind",
		TextColor3 = self.Window.Theme.Text,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = row,
	})

	local keyButton = make("TextLabel", {
		Name = "Key",
		AnchorPoint = Vector2.new(1, 0.5),
		BackgroundColor3 = self.Window.Theme.Primary,
		BorderSizePixel = 0,
		Font = Enum.Font.FredokaOne,
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(92, 30),
		Text = currentKey.Name,
		TextColor3 = self.Window.Theme.White,
		TextSize = 14,
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

return CartoonHubUI
