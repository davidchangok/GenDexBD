-- GenDexBD ConfigPanel.lua
-- 配置面板：InterfaceOptions_AddCategory → 界面→插件→GenDexBD
-- 加载顺序：第7个（最后加载）

local addonName, addonTable = ...

local GetLocaleString = addonTable.GetLocaleString
local pairs = pairs
local ipairs = ipairs

-- ============================================================================
-- 选项定义
-- ============================================================================

local OPTIONS = {
    { "ShowInTooltip",      "OPTION_SHOW_TOOLTIP"  },
    { "ShowInJournal",      "OPTION_SHOW_JOURNAL"  },
    { "AlertInBattle",      "OPTION_ALERT_BATTLE"  },
    { "AssumeRareQuality",  "OPTION_ASSUME_RARE"   },
    { "ShowBestBreedNote",  "OPTION_SHOW_NOTE"     },
}

-- ============================================================================
-- 面板引用
-- ============================================================================

local panel = nil
local checkboxes = {}

-- ============================================================================
-- 初始化（由 Core.lua 在 PLAYER_LOGIN 时调用，此时所有 API 已就绪）
-- ============================================================================

function addonTable.InitConfig()
    if panel then
        return  -- 已初始化
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

        checkboxes[opt[1]] = cb
    end

    -- Show 时刷新复选框（因为可能通过其他方式改了选项）
    panel:SetScript("OnShow", function()
        for optKey, cb in pairs(checkboxes) do
            cb:SetChecked(GeneDexDB.Options[optKey] == true)
        end
    end)

    -- 注册到系统选项。
    -- Blizzard_InterfaceOptions 是按需加载的模块，PLAYER_LOGIN 时可能尚未加载。
    -- 如果 InterfaceOptions_AddCategory 为 nil，先加载。
    if not InterfaceOptions_AddCategory then
        C_AddOns.LoadAddOn("Blizzard_InterfaceOptions")
    end

    if InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
        print("|cff00ff00[GenDexBD]|r 配置面板已注册到 界面→插件→GenDexBD")
    else
        print("|cffff0000[GenDexBD]|r 无法注册配置面板：InterfaceOptions_AddCategory 不可用")
    end
end

-- ============================================================================
-- 斜杠命令回调
-- ============================================================================

function addonTable.ToggleConfigPanel()
    -- 确保面板已注册（如果之前注册失败，重试）
    if not panel then
        addonTable.InitConfig()
        if not panel then
            print("|cffff0000[GenDexBD]|r 配置面板不可用，请输入 /reload")
            return
        end
    end

    -- InterfaceOptionsFrame_OpenToCategory 也会按需加载 Blizzard_InterfaceOptions
    InterfaceOptionsFrame_OpenToCategory(panel)
end
