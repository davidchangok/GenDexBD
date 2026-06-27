-- GenDexBD ConfigPanel.lua
-- 配置面板：注册到系统选项（界面→插件→GenDexBD）
-- Blizzard_InterfaceOptions / Blizzard_InterfaceOptionsFrame 是按需加载模块

local addonName, addonTable = ...

local GetLocaleString = addonTable.GetLocaleString

-- 选项定义
local OPTIONS = {
    { "ShowInTooltip",      "OPTION_SHOW_TOOLTIP"  },
    { "ShowInJournal",      "OPTION_SHOW_JOURNAL"  },
    { "AlertInBattle",      "OPTION_ALERT_BATTLE"  },
    { "AssumeRareQuality",  "OPTION_ASSUME_RARE"   },
    { "ShowBestBreedNote",  "OPTION_SHOW_NOTE"     },
}

-- ============================================================================
-- 面板
-- ============================================================================

local panel = nil

--- 确保 Blizzard 系统选项模块已加载
local function LoadSystemModules()
    if not InterfaceOptions_AddCategory then
        C_AddOns.LoadAddOn("Blizzard_InterfaceOptions")
    end
    if not InterfaceOptionsFrame_OpenToCategory then
        C_AddOns.LoadAddOn("Blizzard_InterfaceOptionsFrame")
    end
end

function addonTable.InitConfig()
    if panel then return end

    -- 先加载系统模块
    LoadSystemModules()

    if not InterfaceOptions_AddCategory then
        print("|cffff0000[GenDexBD]|r InterfaceOptions_AddCategory 不可用")
        return
    end

    -- 创建面板
    panel = CreateFrame("Frame", nil, UIParent)
    panel.name = "GenDexBD"
    panel:SetSize(340, 200)

    -- 标题
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText(GetLocaleString("CONFIG_TITLE"))

    -- 复选框
    local prevCB = nil
    for i, opt in ipairs(OPTIONS) do
        local cb = CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate")
        cb.Text:SetText(GetLocaleString(opt[2]))

        if i == 1 then
            cb:SetPoint("TOPLEFT", title, "BOTTOMLEFT", -2, -8)
        else
            cb:SetPoint("TOPLEFT", prevCB, "BOTTOMLEFT", 0, -2)
        end
        prevCB = cb

        -- 初始状态
        cb:SetChecked(GeneDexDB and GeneDexDB.Options and GeneDexDB.Options[opt[1]] == true)

        -- 即时写入
        cb:SetScript("OnClick", function(self)
            GeneDexDB.Options[opt[1]] = self:GetChecked() or false
        end)
    end

    -- 注册到系统选项（界面→插件 列表中）
    InterfaceOptions_AddCategory(panel)
    print("|cff00ff00[GenDexBD]|r 配置已注册到 界面→插件→GenDexBD")
end

-- ============================================================================
-- 斜杠命令
-- ============================================================================

function addonTable.ToggleConfigPanel()
    -- 确保模块已加载（用户可能在 PLAYER_LOGIN 之前输入命令）
    if not panel then
        addonTable.InitConfig()
    end

    if not panel then
        print("|cffff0000[GenDexBD]|r 配置面板不可用，请输入 /reload")
        return
    end

    -- 确保 OpenToCategory 所在模块已加载
    if not InterfaceOptionsFrame_OpenToCategory then
        C_AddOns.LoadAddOn("Blizzard_InterfaceOptionsFrame")
    end

    if InterfaceOptionsFrame_OpenToCategory then
        InterfaceOptionsFrame_OpenToCategory(panel)
    else
        print("|cffff0000[GenDexBD]|r 无法打开系统选项（InterfaceOptionsFrame_OpenToCategory 不可用）")
        print("|cffff0000[GenDexBD]|r 请手动打开 ESC→界面→插件→GenDexBD")
    end
end
