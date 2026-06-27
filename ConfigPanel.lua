-- GenDexBD ConfigPanel.lua
-- 配置面板：Settings.RegisterCanvasLayoutCategory + Settings.RegisterAddOnCategory
-- 参考 Talon / LorisID 的实现方式，完全对齐 12.0 标准
-- 加载顺序：第7个

local addonName, addonTable = ...

local GetLocaleString = addonTable.GetLocaleString
local ipairs = ipairs

-- 选项定义
local OPTIONS = {
    { "ShowInTooltip",      "OPTION_SHOW_TOOLTIP"  },
    { "ShowInJournal",      "OPTION_SHOW_JOURNAL"  },
    { "AlertInBattle",      "OPTION_ALERT_BATTLE"  },
    { "AssumeRareQuality",  "OPTION_ASSUME_RARE"   },
    { "ShowBestBreedNote",  "OPTION_SHOW_NOTE"     },
}

-- 面板引用 & category ID（供斜杠命令打开）
local panel = nil
local categoryID = nil

function addonTable.InitConfig()
    if panel then return end

    -- 创建面板（parent = UIParent，与 Talon/LorisID 一致）
    panel = CreateFrame("Frame", nil, UIParent)
    panel.name = "GenDexBD"

    -- 标题
    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText(GetLocaleString("CONFIG_TITLE"))

    -- 复选框（InterfaceOptionsCheckButtonTemplate）
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

        cb:SetChecked(GeneDexDB and GeneDexDB.Options and GeneDexDB.Options[opt[1]] == true)

        cb:SetScript("OnClick", function(self)
            GeneDexDB.Options[opt[1]] = self:GetChecked() or false
        end)
    end

    -- 注册到 Settings（与 Talon/LorisID 完全一致的调用顺序）
    local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
    categoryID = category:GetID()
    Settings.RegisterAddOnCategory(category)

    print("|cff00ff00[GenDexBD]|r 配置已注册，categoryID=" .. tostring(categoryID))
end

function addonTable.ToggleConfigPanel()
    if not categoryID then
        print("|cffff0000[GenDexBD]|r 配置面板未注册，请输入 /reload")
        return
    end

    Settings.OpenToCategory(categoryID)
end
