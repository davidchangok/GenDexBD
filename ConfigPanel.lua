-- GenDexBD ConfigPanel.lua
-- 配置面板：参考 PetTracker，使用 Blizzard 现代 Settings API
-- 加载顺序：第7个（最后加载，依赖 Core/DB、Locales）
--
-- /genedex 或 /gd 直接打开系统设置并定位到 GenDexBD 分类

local addonName, addonTable = ...

-- ============================================================================
-- 文件作用域 local 化
-- ============================================================================

local GetLocaleString = addonTable.GetLocaleString

local pairs = pairs

-- ============================================================================
-- 选项定义
-- ============================================================================

-- { optionKey, localeKey }
local OPTIONS = {
    { "ShowInTooltip",      "OPTION_SHOW_TOOLTIP"  },
    { "ShowInJournal",      "OPTION_SHOW_JOURNAL"  },
    { "AlertInBattle",      "OPTION_ALERT_BATTLE"  },
    { "AssumeRareQuality",  "OPTION_ASSUME_RARE"   },
    { "ShowBestBreedNote",  "OPTION_SHOW_NOTE"     },
}

-- ============================================================================
-- 面板创建
-- ============================================================================

-- 面板单例
local category = nil  -- Settings API 返回的 category 对象
local checkboxes = {} -- 复选框引用，用于 OnRefresh 刷新状态

--- 创建一个设置项复选框（跟在同列的上一项下方）
--- @param parent table 父 Frame
--- @param optionKey string 选项键
--- @param label string 显示文本
--- @param index number 序号
--- @return table 复选框
local function CreateCheckbox(parent, optionKey, label, index)
    local cb = CreateFrame("CheckButton", nil, parent, "InterfaceOptionsCheckButtonTemplate")

    if index == 1 then
        cb:SetPoint("TOPLEFT", parent, "TOPLEFT", 4, -12)
    else
        -- 锚定到上一个复选框下方
        cb:SetPoint("TOPLEFT", checkboxes[OPTIONS[index - 1][1]], "BOTTOMLEFT", 0, -2)
    end

    cb.Text:SetText(label)

    -- 从当前配置读取状态
    if GeneDexDB and GeneDexDB.Options then
        cb:SetChecked(GeneDexDB.Options[optionKey] == true)
    end

    -- 点击时立即写入 SavedVariables
    cb:SetScript("OnClick", function(self)
        if GeneDexDB and GeneDexDB.Options then
            GeneDexDB.Options[optionKey] = self:GetChecked() or false
        end
    end)

    checkboxes[optionKey] = cb
    return cb
end

--- 创建配置面板（参考 PetTracker：Settings.RegisterCanvasLayoutCategory）
local function CreateOptionsPanel()
    -- 创建停靠容器（parent = SettingsPanel，与 PetTracker 一致）
    local dock = CreateFrame("Frame", nil, SettingsPanel)
    dock:SetSize(400, 200)

    -- === 生命周期回调（Settings 系统自动调用）===

    -- OnRefresh：面板显示时同步复选框状态
    dock.OnRefresh = function()
        for optKey, cb in pairs(checkboxes) do
            if cb and cb.SetChecked then
                cb:SetChecked(GeneDexDB and GeneDexDB.Options and GeneDexDB.Options[optKey] == true)
            end
        end
    end

    -- OnDefault：恢复默认值
    dock.OnDefault = function()
        local defaults = {
            ShowInTooltip = true,
            ShowInJournal = true,
            AlertInBattle = true,
            AssumeRareQuality = true,
            ShowBestBreedNote = true,
        }
        if GeneDexDB and GeneDexDB.Options then
            for k, v in pairs(defaults) do
                GeneDexDB.Options[k] = v
            end
        end
        -- 刷新控件状态
        if dock.OnRefresh then dock.OnRefresh() end
    end

    -- OnCommit：确认（即时写入模式下无需额外操作，OnClick 已写入）
    dock.OnCommit = function()
        -- 已通过 OnClick 即时写入，无需额外处理
    end

    -- OnCancel：取消（即时写入模式下无需回退）
    dock.OnCancel = function()
        -- 已通过 OnClick 即时写入，无需额外处理
    end

    -- === 创建标题和复选框 ===

    -- 标题（参考 PetTracker 的 Header 样式）
    local title = dock:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", dock, "TOPLEFT", 0, 0)
    title:SetText(GetLocaleString("CONFIG_TITLE"))

    -- 逐个创建复选框
    for i, opt in ipairs(OPTIONS) do
        CreateCheckbox(dock, opt[1], GetLocaleString(opt[2]), i)
    end

    -- 注册到 Settings 面板（现代 API，与 PetTracker 完全一致）
    category = Settings.RegisterCanvasLayoutCategory(dock, "GenDexBD")

    return dock
end

local dockFrame = nil

-- ============================================================================
-- 斜杠命令：打开系统设置并定位到 GenDexBD
-- ============================================================================

function addonTable.ToggleConfigPanel()
    -- 确保已创建
    if not dockFrame then
        dockFrame = CreateOptionsPanel()
        print("|cff00ff00[GenDexBD]|r 配置已注册到系统设置 → GenDexBD")
    end

    -- 参考 PetTracker 的 Open() 方法：
    -- SettingsPanel:SelectCategory(category) 定位到我们的面板
    if SettingsPanel and category then
        SettingsPanel:Show()
        SettingsPanel:SelectCategory(category)
        if category.expanded ~= nil then
            category.expanded = true
        end
        if SettingsPanel.CategoryList and SettingsPanel.CategoryList.CreateCategories then
            SettingsPanel.CategoryList:CreateCategories()
        end
    end
end
