-- GenDexBD JournalUI.lua — 双模式品种标注 + 最优管理
-- Rematch → 改 Breed FontString + 注入右键菜单
-- 原生面板 → 新建 FontString + OnMouseUp 右键菜单

local addonName, addonTable = ...

local CalculateBreedFromStats = addonTable.CalculateBreedFromStats
local GetBreedCode = addonTable.GetBreedCode
local GetBreedDisplayName = addonTable.GetBreedDisplayName

local time = time
local type = type
local pairs = pairs
local ipairs = ipairs
local next = next
local strlower = string.lower
local strfind = string.find

local function LOG(...) print("|cff00ccff[GenDexBD]|r " .. string.format(...)) end

-- ============================================================================
-- 最优品种管理 API
-- ============================================================================

function addonTable.SetBestBreed(speciesID, breedID, category, note)
    if not speciesID or not breedID then return end
    if not GeneDexDB then return end
    if not GeneDexDB.BestBreeds or type(GeneDexDB.BestBreeds) ~= "table" then GeneDexDB.BestBreeds = {} end
    if not GeneDexDB.BestBreeds[speciesID] then GeneDexDB.BestBreeds[speciesID] = {} end
    GeneDexDB.BestBreeds[speciesID][breedID] = { category = category or "custom", note = note or "", addedAt = time() }
    RefreshAll()
end

function addonTable.RemoveBestBreed(speciesID, breedID)
    if not speciesID or not breedID then return end
    local bb = GeneDexDB and GeneDexDB.BestBreeds; if not bb or type(bb) ~= "table" then return end
    local sd = bb[speciesID]; if not sd or type(sd) ~= "table" then return end
    sd[breedID] = nil; if not next(sd) then bb[speciesID] = nil end
    RefreshAll()
end

function addonTable.IsBestBreed(speciesID, breedID)
    if not speciesID or not breedID then return false end
    local bb = GeneDexDB and GeneDexDB.BestBreeds; if not bb or type(bb) ~= "table" then return false end
    local sd = bb[speciesID]; if not sd or type(sd) ~= "table" then return false end
    return sd[breedID] ~= nil
end

function addonTable.GetBestBreedInfo(speciesID, breedID)
    if not speciesID or not breedID then return nil end
    local bb = GeneDexDB and GeneDexDB.BestBreeds; if not bb or type(bb) ~= "table" then return nil end
    local sd = bb[speciesID]; if not sd or type(sd) ~= "table" then return nil end
    local bd = sd[breedID]; return (bd and type(bd) == "table") and bd or nil
end

function addonTable.GetAllBestBreeds(speciesID)
    if not speciesID then return {} end
    local bb = GeneDexDB and GeneDexDB.BestBreeds; if not bb or type(bb) ~= "table" then return {} end
    local sd = bb[speciesID]; return (sd and type(sd) == "table") and sd or {}
end

-- ============================================================================
-- API 字段探测 + 品种推算
-- ============================================================================

local petInfoFields = nil

local function DetectPetInfoFields()
    if petInfoFields then return petInfoFields[1], petInfoFields[2], petInfoFields[3] end
    local s = C_PetJournal.GetPetInfoBySpeciesID(39) or C_PetJournal.GetPetInfoBySpeciesID(1)
    if not s then return nil end
    local ks = {}; for k in pairs(s) do ks[#ks+1] = k end
    local function f(ps)
        for _, k in ipairs(ks) do
            local l = strlower(k)
            for _, p in ipairs(ps) do if strfind(l, p, 1, true) then return k end end
        end
    end
    local h, p, sp = f({"health","hp"}), f({"power","attack","atk"}), f({"speed","spd"})
    petInfoFields = {h, p, sp}
    if h then LOG("字段探测 OK: H=%s P=%s S=%s", h, p, sp) end
    return h, p, sp
end

local function ExtractBaseStats(petInfo)
    if not petInfo then return nil end
    local h, p, s = DetectPetInfoFields()
    if not h or not p or not s then return nil end
    return petInfo[h], petInfo[p], petInfo[s]
end

local function CalcBreed(speciesID, level, quality, health, power, speed)
    if not health or not power or not speed then return nil end
    local pi = C_PetJournal.GetPetInfoBySpeciesID(speciesID)
    if not pi then return nil end
    local bh, bp, bs = ExtractBaseStats(pi)
    if not bh or not bp or not bs then return nil end
    local q = quality or 4
    if GeneDexDB and GeneDexDB.Options and GeneDexDB.Options.AssumeRareQuality then
        if not quality or q < 4 then q = 4 end
    end
    return CalculateBreedFromStats(health, power, speed, bh, bp, bs, level, q)
end

-- ============================================================================
-- 按钮发现（双来源）
-- ============================================================================

--- 扫描 Frame 树，找有 Breed 子元素（Rematch按钮标志）的 Frame
local function ScanForButtons(root, maxDepth, label)
    local btns = {}
    local totalVisible = 0
    local withPetID = 0
    local withBreed = 0
    local function scan(p, d)
        if d > maxDepth then return end
        local children = { p:GetChildren() }
        for _, c in ipairs(children) do
            if c:IsVisible() then
                totalVisible = totalVisible + 1
                if c.petID then
                    withPetID = withPetID + 1
                    if c.Breed then withBreed = withBreed + 1 end
                    btns[#btns+1] = c
                end
            end
            scan(c, d+1)
        end
    end
    scan(root, 0)
    LOG("%s: 可见=%d 有petID=%d 有Breed=%d → 采用%d个",
        label, totalVisible, withPetID, withBreed, #btns)
    return btns
end

local function FindPetListButtons()
    -- Rematch
    if RematchFrame and RematchFrame:IsShown() then
        local b = ScanForButtons(RematchFrame, 5, "RematchFrame")
        if #b > 0 then return b, "Rematch" end
    elseif RematchFrame then
        -- 诊断：RematchFrame 存在但 IsShown false
        local _, _, _, _, _, _, _, level = RematchFrame:GetPoint()
        LOG("RematchFrame:IsShown=%s alpha=%s level=%s",
            tostring(RematchFrame:IsShown()), tostring(RematchFrame:GetAlpha()), tostring(level))
        -- 临时：即使 IsShown=false 也扫描一下，看按钮是否存在
        local b2 = ScanForButtons(RematchFrame, 5, "RematchFrame(隐藏)")
        LOG("隐藏状态扫描结果: %d 个按钮", #b2)
    end

    -- 暴雪原生
    if PetJournal and PetJournal:IsShown() then
        local b = ScanForButtons(PetJournal, 5, "PetJournal")
        if #b > 0 then return b, "PetJournal" end
    elseif PetJournal then
        LOG("PetJournal:IsShown=%s", tostring(PetJournal:IsShown()))
    end

    return {}, "none"
end

-- ============================================================================
-- 按钮标注
-- ============================================================================

local labelFailReasons = {}

local function LabelButton(button)
    if not button or not button.petID then return end
    if not GeneDexDB or not GeneDexDB.Options or not GeneDexDB.Options.ShowInJournal then return end

    local _, sid, _, _, _, _, _, _, _, _, _, lv, q, hp, pw, sp = C_PetJournal.GetPetInfoByPetID(button.petID)
    if not sid then return end

    if not hp or not pw or not sp then
        labelFailReasons["noStats"] = (labelFailReasons["noStats"] or 0) + 1
        return
    end

    local bid = CalcBreed(sid, lv, q, hp, pw, sp)
    if not bid then
        labelFailReasons["noBreed"] = (labelFailReasons["noBreed"] or 0) + 1
        return
    end

    local code = GetBreedCode(bid)
    local isBest = addonTable.IsBestBreed(sid, bid)
    local text = isBest and ("★"..code) or code
    local r, g, b = isBest and 1 or 0.6, isBest and 0.84 or 0.6, 0.6

    if button.Breed then
        -- Rematch 按钮：改写已有 Breed
        button.Breed:SetText(text)
        button.Breed:SetTextColor(r, g, b)
        button.Breed:Show()
    else
        -- 暴雪原生按钮：创建独立 FontString
        if not button._gLabel then
            local fs = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            fs:SetPoint("RIGHT", -4, 0)
            fs:SetJustifyH("RIGHT")
            button._gLabel = fs
        end
        button._gLabel:SetText(text)
        button._gLabel:SetTextColor(r, g, b)
        button._gLabel:Show()
    end
end

function RefreshAll()
    if not GeneDexDB or not GeneDexDB.Options or not GeneDexDB.Options.ShowInJournal then return end
    labelFailReasons = {}
    local btns, src = FindPetListButtons()
    local n, labeled = 0, 0
    for _, b in ipairs(btns) do
        local ok, err = pcall(LabelButton, b)
        if not ok then labelFailReasons["error"] = (labelFailReasons["error"] or 0) + 1 end
        n = n + 1
    end
    if n > 0 then
        LOG("标注尝试 %d 个按钮 (来源=%s) noStats=%d noBreed=%d error=%d",
            n, src,
            labelFailReasons["noStats"] or 0,
            labelFailReasons["noBreed"] or 0,
            labelFailReasons["error"] or 0)
    end
end

-- ============================================================================
-- 原生面板右键菜单（OnMouseUp 方式，不依赖 OnClick）
-- ============================================================================

local menuFrame = nil

local function BlizzardRightClick(self, button)
    if button ~= "RightButton" then return end
    local petID = self.petID
    if not petID then return end
    local _, sid, _, _, _, _, _, _, _, _, _, lv, q, hp, pw, sp = C_PetJournal.GetPetInfoByPetID(petID)
    if not sid then return end
    local bid = CalcBreed(sid, lv, q, hp, pw, sp)
    if not bid then return end

    if not menuFrame then
        menuFrame = CreateFrame("Frame", "GeneDexBDMenu", UIParent, "UIDropDownMenuTemplate")
    end

    local isBest = addonTable.IsBestBreed(sid, bid)
    local code = GetBreedCode(bid) or "?"
    local name = GetBreedDisplayName(bid, code)

    UIDropDownMenu_Initialize(menuFrame, function(_, level)
        local info = UIDropDownMenu_CreateInfo()

        if level == 1 then
            info.text = name; info.isTitle = true; info.notCheckable = true
            UIDropDownMenu_AddButton(info, 1)

            if isBest then
                local bi = addonTable.GetBestBreedInfo(sid, bid)
                if bi then
                    info.isTitle = true
                    info.text = "已标记: " .. (bi.category or "custom")
                    UIDropDownMenu_AddButton(info, 1)
                end
                info.isTitle = false; info.text = "取消最优品种"; info.notCheckable = true
                info.func = function() addonTable.RemoveBestBreed(sid, bid) end
                UIDropDownMenu_AddButton(info, 1)
            else
                info.isTitle = false; info.text = "设为最优品种"; info.notCheckable = true
                info.hasArrow = true; info.menuList = "GeneDexBD_BlizzCats"
                UIDropDownMenu_AddButton(info, 1)
            end
        elseif level == 2 then
            for _, cat in ipairs({"pvp","pve","collection","custom"}) do
                local cn = addonTable.GetBestBreedCategoryName and addonTable.GetBestBreedCategoryName(cat) or cat
                info.text = cn; info.notCheckable = true
                info.func = function() addonTable.SetBestBreed(sid, bid, cat, "") end
                UIDropDownMenu_AddButton(info, 2)
            end
        end
    end)

    ToggleDropDownMenu(1, nil, menuFrame, self, 0, 0)
end

-- ============================================================================
-- Rematch 菜单注入
-- ============================================================================

local function InjectRematchMenu()
    if not rematch or not rematch.menus or not rematch.menus.AddToMenu then return end
    if rematch._genedexInjected then return end
    rematch._genedexInjected = true

    -- 注册子菜单（选择分类）
    rematch.menus:Register("GeneDexBDBestMenu", {
        {title = "选择最优场景"},
        {text = "PvP 对战", func = function(_, petID) setBest(petID, "pvp") end},
        {text = "PvE 任务", func = function(_, petID) setBest(petID, "pve") end},
        {text = "收藏",     func = function(_, petID) setBest(petID, "collection") end},
        {text = "自定义",   func = function(_, petID) setBest(petID, "custom") end},
        {text = CANCEL},
    })

    -- 追加到宠物菜单，"Find Teams" 之后（CANCEL 之前）
    rematch.menus:AddToMenu("PetMenu", {
        text = "★ 最优品种",
        subMenu = "GeneDexBDBestMenu",
        hidden = function(_, petID) return not petID end,
    }, "Find Teams")

    rematch.menus:AddToMenu("PetMenu", {
        text = "取消最优品种",
        hidden = function(_, petID)
            local _, sid = C_PetJournal.GetPetInfoByPetID(petID)
            if not sid then return true end
            return not next(addonTable.GetAllBestBreeds(sid))
        end,
        func = function(_, petID)
            local _, sid = C_PetJournal.GetPetInfoByPetID(petID)
            if not sid then return end
            for bid in pairs(addonTable.GetAllBestBreeds(sid)) do
                addonTable.RemoveBestBreed(sid, bid)
            end
        end,
    }, "Find Teams")

    LOG("Rematch 菜单已注入")
end

-- setBest 辅助（供 Rematch 菜单回调）
function setBest(petID, category)
    local _, sid, _, _, _, _, _, _, _, _, _, lv, q, hp, pw, sp = C_PetJournal.GetPetInfoByPetID(petID)
    if not sid then return end
    local bid = CalcBreed(sid, lv, q, hp, pw, sp)
    if bid then addonTable.SetBestBreed(sid, bid, category, "") end
end

-- ============================================================================
-- 事件处理
-- ============================================================================

local function OnListUpdate()
    local btns, src = FindPetListButtons()
    if #btns > 0 then
        for _, b in ipairs(btns) do
            pcall(LabelButton, b)
            -- 只给原生按钮绑右键（Rematch 按钮由菜单系统处理）
            if not b.Breed and not b._genedexRightHooked then
                b._genedexRightHooked = true
                b:SetScript("OnMouseUp", function(self, button)
                    BlizzardRightClick(self, button)
                end)
            end
        end
    end
end

-- ============================================================================
-- 初始化
-- ============================================================================

function addonTable.InitJournalUI()
    LOG("初始化 (双模式)")

    -- PET_JOURNAL_LIST_UPDATE
    local ef = CreateFrame("Frame")
    ef:RegisterEvent("PET_JOURNAL_LIST_UPDATE")
    ef:SetScript("OnEvent", function() OnListUpdate() end)

    -- Blizzard_Collections 加载
    local bcf = CreateFrame("Frame")
    bcf:RegisterEvent("ADDON_LOADED")
    bcf:SetScript("OnEvent", function(_, _, a)
        if a == "Blizzard_Collections" then OnListUpdate(); bcf:UnregisterEvent("ADDON_LOADED") end
    end)

    -- RematchFrame 轮询（节流 0.5s）
    local rmf = CreateFrame("Frame"); rmf._s = false
    rmf:SetScript("OnUpdate", function(self, elapsed)
        self._t = (self._t or 0) + elapsed
        if self._t < 0.5 then return end; self._t = 0
        if RematchFrame and RematchFrame:IsShown() then
            if not self._s then self._s = true; LOG("RematchFrame 可见"); OnListUpdate() end
            -- 首次可见时同时注入菜单
            InjectRematchMenu()
        else
            self._s = false
        end
    end)

    -- 如果 Rematch 已加载
    if rematch and rematch.menus then
        InjectRematchMenu()
    else
        -- 等 Rematch 加载
        local rf = CreateFrame("Frame")
        rf:RegisterEvent("ADDON_LOADED")
        rf:SetScript("OnEvent", function(_, _, a)
            if a == "Rematch" then InjectRematchMenu(); rf:UnregisterEvent("ADDON_LOADED") end
        end)
    end
end
