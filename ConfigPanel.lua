-- GenDexBD ConfigPanel.lua
-- 配置面板：/genedex 或 /gd 斜杠命令打开的选项设置界面
-- 加载顺序：第7个（最后加载，依赖 Core/DB、Locales）
--
-- 使用 BasicFrameTemplateWithInset + InterfaceOptionsCheckButtonTemplate
-- 5 个复选框即时写入 GeneDexDB.Options，SavedVariables 自动持久化

local addonName, addonTable = ...

-- ============================================================================
-- 文件作用域 local 化
-- ============================================================================

local GetLocaleString = addonTable.GetLocaleString

local pairs = pairs
local type = type

-- ============================================================================
-- 配置面板创建
-- ============================================================================

-- 单例引用
local configFrame = nil

-- 复选框控件及其对应的选项键
local checkboxes = {}

-- 面板宽度和基础高度
local PANEL_WIDTH = 340
local PANEL_HEIGHT = 230
local CHECKBOX_SPACING = 32
local CHECKBOX_TOP_OFFSET = 45

--- 创建单个复选框
--- @param parent table 父 Frame
--- @param optionKey string GeneDexDB.Options 中的键名
--- @param label string 显示文本
--- @param index number 复选框序号（用于计算位置）
--- @return table 复选框 Frame
local function CreateCheckbox(parent, optionKey, label, index)
    local cb = CreateFrame("CheckButton", nil, parent, "InterfaceOptionsCheckButtonTemplate")

    -- 计算位置：第一个最高，依次向下
    local yOffset = -CHECKBOX_TOP_OFFSET - (index - 1) * CHECKBOX_SPACING
    cb:SetPoint("TOPLEFT", parent, "TOPLEFT", 24, yOffset)

    -- 设置显示文本
    if cb.Text then
        cb.Text:SetText(label)
    end

    -- 设置初始状态
    if GeneDexDB and GeneDexDB.Options then
        cb:SetChecked(GeneDexDB.Options[optionKey] == true)
    end

    -- 点击时立即写入 SavedVariables
    cb:SetScript("OnClick", function(self)
        if GeneDexDB and GeneDexDB.Options then
            GeneDexDB.Options[optionKey] = self:GetChecked() or false
        end
    end)

    -- 保存引用
    checkboxes[optionKey] = cb

    return cb
end

--- 刷新所有复选框状态（从 GeneDexDB.Options 同步到控件）
local function RefreshCheckboxStates()
    if not GeneDexDB or not GeneDexDB.Options then
        return
    end

    for optionKey, cb in pairs(checkboxes) do
        if cb and cb.SetChecked then
            cb:SetChecked(GeneDexDB.Options[optionKey] == true)
        end
    end
end

--- 创建配置面板（仅首次调用时执行）
local function CreateConfigPanel()
    if configFrame then
        return
    end

    -- 用 pcall 包裹模板创建，12.0 中模板名可能已变化
    local ok, err = pcall(function()
        configFrame = CreateFrame("Frame", "GeneDexBDConfigFrame", UIParent, "BasicFrameTemplateWithInset")
    end)

    -- 如果模板创建失败，回退到普通 Frame + 手动面板样式
    if not ok or not configFrame then
        configFrame = CreateFrame("Frame", "GeneDexBDConfigFrame", UIParent)
        configFrame:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 32,
            insets = { left = 8, right = 8, top = 8, bottom = 8 },
        })
        configFrame:SetBackdropColor(0.09, 0.09, 0.09, 1)
    end
    configFrame:SetSize(PANEL_WIDTH, PANEL_HEIGHT)
    configFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)

    -- 可拖拽
    configFrame:SetMovable(true)
    configFrame:SetClampedToScreen(true)

    -- 拖拽处理
    configFrame:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then
            self:StartMoving()
        end
    end)
    configFrame:SetScript("OnMouseUp", function(self)
        self:StopMovingOrSizing()
    end)

    -- 标题背景高度调整
    if configFrame.TitleBg then
        configFrame.TitleBg:SetHeight(30)
    end

    -- 标题文字
    local title = configFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", configFrame, "TOP", 0, -10)
    title:SetText(GetLocaleString("CONFIG_TITLE"))

    -- 让标题响应拖拽（因为 BasicFrameTemplateWithInset 的标题区域可能不在 OnMouseDown 范围内）
    title:SetScript("OnMouseDown", function()
        configFrame:StartMoving()
    end)
    title:SetScript("OnMouseUp", function()
        configFrame:StopMovingOrSizing()
    end)

    -- 关闭按钮（模板自带 UIPanelCloseButton）
    local closeButton = CreateFrame("Button", nil, configFrame, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", configFrame, "TOPRIGHT", -5, -5)
    closeButton:SetScript("OnClick", function()
        configFrame:Hide()
    end)

    -- 5 个配置项复选框
    CreateCheckbox(configFrame, "ShowInTooltip",    GetLocaleString("OPTION_SHOW_TOOLTIP"), 1)
    CreateCheckbox(configFrame, "ShowInJournal",    GetLocaleString("OPTION_SHOW_JOURNAL"), 2)
    CreateCheckbox(configFrame, "AlertInBattle",    GetLocaleString("OPTION_ALERT_BATTLE"), 3)
    CreateCheckbox(configFrame, "AssumeRareQuality", GetLocaleString("OPTION_ASSUME_RARE"), 4)
    CreateCheckbox(configFrame, "ShowBestBreedNote", GetLocaleString("OPTION_SHOW_NOTE"),   5)

    -- 初始隐藏
    configFrame:Hide()
    print("|cff00ff00[GenDexBD]|r 配置面板已创建。输入 /gd 打开设置")
end

--- 打开/关闭配置面板（Toggle）
function addonTable.ToggleConfigPanel()
    -- 确保面板已创建
    if not configFrame then
        CreateConfigPanel()
    end

    if configFrame:IsShown() then
        configFrame:Hide()
    else
        -- 同步复选框状态
        RefreshCheckboxStates()
        configFrame:Show()
        -- 将面板提到最前
        configFrame:Raise()
    end
end
