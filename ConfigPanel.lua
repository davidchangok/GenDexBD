-- GenDexBD ConfigPanel.lua
-- 配置面板：集成到暴雪系统选项界面 (Interface Options → AddOns → GenDexBD)
-- 加载顺序：第7个（最后加载，依赖 Core/DB、Locales）
--
-- /genedex 或 /gd 直接打开系统选项并定位到 GenDexBD 分类

local addonName, addonTable = ...

-- ============================================================================
-- 文件作用域 local 化
-- ============================================================================

local GetLocaleString = addonTable.GetLocaleString

local pairs = pairs

-- ============================================================================
-- 选项配置列表
-- ============================================================================

-- { optionKey, localeKey, tooltipLocaleKey }
local OPTIONS = {
    { "ShowInTooltip",      "OPTION_SHOW_TOOLTIP" },
    { "ShowInJournal",      "OPTION_SHOW_JOURNAL" },
    { "AlertInBattle",      "OPTION_ALERT_BATTLE" },
    { "AssumeRareQuality",  "OPTION_ASSUME_RARE"  },
    { "ShowBestBreedNote",  "OPTION_SHOW_NOTE"    },
}

-- ============================================================================
-- 创建系统选项面板
-- ============================================================================

--- 创建集成到系统选项 (Interface Options) 的配置面板
local function CreateOptionsPanel()
    -- 主面板：挂载到 Interface Options 框架下
    local panel = CreateFrame("Frame", nil, UIParent)
    panel.name = "GenDexBD"
    -- 使用 InterfaceOptions_AddCategory 时必须设置 category 为 ADDONS
    panel.category = "ADDONS"

    -- 标题
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -16)
    title:SetText(GetLocaleString("CONFIG_TITLE"))

    -- 动态创建复选框（用 InterfaceOptionsCheckButtonTemplate 自动匹配系统样式）
    local firstCB = nil
    for i, opt in ipairs(OPTIONS) do
        local cb = CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate")
        cb.Text:SetText(GetLocaleString(opt[2]))

        if i == 1 then
            cb:SetPoint("TOPLEFT", title, "BOTTOMLEFT", -2, -12)
            firstCB = cb
        else
            cb:SetPoint("TOPLEFT", firstCB, "BOTTOMLEFT", 0, -4)
            firstCB = cb
        end

        -- 读取当前值
        cb:SetChecked(GeneDexDB and GeneDexDB.Options and GeneDexDB.Options[opt[1]] == true)

        -- 点击时即时写入
        cb:SetScript("OnClick", function(self)
            if GeneDexDB and GeneDexDB.Options then
                GeneDexDB.Options[opt[1]] = self:GetChecked() or false
            end
        end)
    end

    -- 注册到系统选项
    InterfaceOptions_AddCategory(panel)

    return panel
end

-- 面板单例
local optionsPanel = nil

-- ============================================================================
-- 斜杠命令处理
-- ============================================================================

--- 打开系统选项并定位到 GenDexBD 面板
function addonTable.ToggleConfigPanel()
    -- 确保面板已创建
    if not optionsPanel then
        optionsPanel = CreateOptionsPanel()
        print("|cff00ff00[GenDexBD]|r 配置已注册到系统选项 → 界面 → 插件 → GenDexBD")
    end

    -- 打开系统选项界面并定位到我们的面板
    InterfaceOptionsFrame_OpenToCategory(optionsPanel)
end
