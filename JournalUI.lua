-- GenDexBD JournalUI.lua
-- 双模式品种标注：Rematch (Hook Fill) + 暴雪原生 (Hook PetJournal_InitPetButton)

local addonName, addonTable = ...
local GetBreedCode=addonTable.GetBreedCode;local time=time
local pairs=pairs;local next=next
local function LOG(...) print("|cff00ccff[GenDexBD]|r "..string.format(...)) end

-- ========== 最优品种管理 API ==========
function addonTable.SetBestBreed(sid,bid,cat,note)
    if not sid or not bid then return end;if not GeneDexDB then return end
    local bb=GeneDexDB.BestBreeds;if not bb or type(bb)~="table" then GeneDexDB.BestBreeds={} end
    if not GeneDexDB.BestBreeds[sid] then GeneDexDB.BestBreeds[sid]={} end
    GeneDexDB.BestBreeds[sid][bid]={category=cat or "custom",note=note or "",addedAt=time()}
end
function addonTable.RemoveBestBreed(sid,bid)
    if not sid or not bid then return end
    local bb=GeneDexDB and GeneDexDB.BestBreeds;if not bb or type(bb)~="table" then return end
    local sd=bb[sid];if not sd or type(sd)~="table" then return end;sd[bid]=nil;if not next(sd) then bb[sid]=nil end
end
function addonTable.IsBestBreed(sid,bid)
    if not sid or not bid then return false end
    local bb=GeneDexDB and GeneDexDB.BestBreeds;if not bb or type(bb)~="table" then return false end
    local sd=bb[sid];if not sd or type(sd)~="table" then return false end;return sd[bid]~=nil
end
function addonTable.GetBestBreedInfo(sid,bid)
    if not sid or not bid then return nil end
    local bb=GeneDexDB and GeneDexDB.BestBreeds;if not bb or type(bb)~="table" then return nil end
    local sd=bb[sid];if not sd or type(sd)~="table" then return nil end
    local bd=sd[bid];return (bd and type(bd)=="table") and bd or nil
end
function addonTable.GetAllBestBreeds(sid)
    if not sid then return {} end
    local bb=GeneDexDB and GeneDexDB.BestBreeds;if not bb or type(bb)~="table" then return {} end
    local sd=bb[sid];return (sd and type(sd)=="table") and sd or {}
end

-- ========== 品种推算 ==========
-- 12.0 API：GetPetInfoBySpeciesID 返回多值元组（speciesID, creatureID, icon, ...），非表
-- 用 {C_PetJournal.GetPetInfoBySpeciesID(sid)} 转为数组，字段按位置取
-- 基准属性在返回值的固定位置：health=位置9, power=位置10, speed=位置11（实测为准）
local function GetBaseStats(sid)
    if not sid then return nil,nil,nil end
    -- 用 pcall 包裹，API 可能返回类型不一致
    local ok, result = pcall(function()
        return {C_PetJournal.GetPetInfoBySpeciesID(sid)}
    end)
    if not ok or type(result)~="table" or #result < 3 then
        -- pcall 已经吞了错误，回退到 BreedData 表
        return nil,nil,nil
    end

    -- 遍历所有返回字段按名字匹配（最可靠的方式）
    for i, v in ipairs(result) do
        if type(v) == "table" then
            -- 有些版本返回嵌套表包含全部数据
            local bh = v.health or v.baseHealth or v.baseHp
            local bp = v.power or v.basePower or v.baseAttack or v.baseAtk
            local bs = v.speed or v.baseSpeed or v.baseSpd
            if bh then return bh, bp, bs end
        end
    end

    -- 直接按数量位置尝试：基准属性通常在末尾几个数值
    -- 格式: speciesID, creatureID, icon, name, description, source, _, _, health, power, speed
    if #result >= 11 then
        local bh = tonumber(result[9]) or tonumber(result[10])
        local bp = tonumber(result[10]) or tonumber(result[11])
        local bs = tonumber(result[11]) or tonumber(result[12])
        if bh then return bh, bp, bs end
    end

    -- 遍历所有字段找数值
    local nums = {}
    for _, v in ipairs(result) do
        if type(v) == "number" and v > 0 then nums[#nums+1] = v end
    end
    -- 后三个数值通常是基准属性
    if #nums >= 3 then
        return nums[#nums-2], nums[#nums-1], nums[#nums]
    end

    return nil,nil,nil
end
local function CalcBreed(sid,lv,q,hp,pw,sp)
    if not hp or not pw or not sp then return nil end
    local pi=C_PetJournal.GetPetInfoBySpeciesID(sid);if not pi then return nil end
    local bh,bp,bs=GetBaseStats(pi);if not bh then return nil end
    local q2=q or 4;if GeneDexDB and GeneDexDB.Options and GeneDexDB.Options.AssumeRareQuality and (not q or q<4) then q2=4 end
    return addonTable.CalculateBreedFromStats(hp,pw,sp,bh,bp,bs,lv,q2)
end

-- ========== Rematch：Hook Fill + 菜单 ==========
local function RematchDecorate(button)
    if not button or not button.petID or not button.Icon then return end
    local _,sid,_,_,_,_,_,_,_,_,_,lv,q = C_PetJournal.GetPetInfoByPetID(button.petID)
    if not sid then return end
    local hp,pw,sp = C_PetJournal.GetPetStats(button.petID)

    -- 金色五星：检查**当前宠物的具体品种**是否被标记为最优
    local isBest = false
    if hp and hp>0 then
        local bid=CalcBreed(sid,lv,q,hp,pw,sp)
        if bid then
            isBest = addonTable.IsBestBreed(sid, bid)  -- 精确匹配 breedID
            if button.Breed then
                local code=GetBreedCode(bid)
                button.Breed:SetText(isBest and ("★"..code) or code)
                button.Breed:SetTextColor(isBest and 1 or 0.6, isBest and 0.84 or 0.6, 0.6)
                button.Breed:Show()
            end
        end
    end
    if isBest then
        if not button._gStar then
            local star = button:CreateTexture(nil, "OVERLAY")
            -- 用暴雪内置的金色五星 atlAs（和 Favorite 一样）
            star:SetAtlas("PetJournal-FavoritesIcon")
            star:SetSize(16, 16)
            star:SetPoint("TOPRIGHT", button.Icon, "TOPRIGHT", 4, 4)
            button._gStar = star
        end
        button._gStar:Show()
    else
        if button._gStar then button._gStar:Hide() end
    end
end

local rematchHooked=false
local function TryHookRematch()
    if rematchHooked then return end
    if not Rematch or not Rematch.petsPanel or not Rematch.petsPanel.FillNormal then return end
    rematchHooked=true
    hooksecurefunc(Rematch.petsPanel,"FillNormal",function(_,button) RematchDecorate(button) end)
    hooksecurefunc(Rematch.petsPanel,"FillCompact",function(_,button) RematchDecorate(button) end)
    LOG("已 Hook Rematch Fill")
end

function RematchSetBest(petID,cat)
    -- speciesID 是第1个返回值，level 是第3个
    local speciesID,_,level= C_PetJournal.GetPetInfoByPetID(petID)
    if not speciesID then return end
    local hp,pw,sp = C_PetJournal.GetPetStats(petID)
    local bid=CalcBreed(speciesID,level,4,hp,pw,sp)
    if bid then
        local code=GetBreedCode(bid)
        addonTable.SetBestBreed(speciesID,bid,cat or "custom","")
        LOG("已保存: speciesID=%d breedID=%d (%s)", speciesID, bid, code)
        if Rematch and Rematch.petsPanel and Rematch.petsPanel.Update then
            Rematch.petsPanel:Update()
        end
    else
        LOG("⚠ 推算失败: speciesID=%d hp=%s", speciesID, tostring(hp))
    end
end
function RematchRemoveBest(petID)
    local speciesID = C_PetJournal.GetPetInfoByPetID(petID)
    if not speciesID then return end
    for bid in pairs(addonTable.GetAllBestBreeds(speciesID)) do addonTable.RemoveBestBreed(speciesID,bid) end
    LOG("已移除: speciesID=%d", speciesID)
    if Rematch and Rematch.petsPanel and Rematch.petsPanel.Update then
        Rematch.petsPanel:Update()
    end
end
function RematchHasBest(petID)
    local _,sid=C_PetJournal.GetPetInfoByPetID(petID);if not sid then return false end
    return next(addonTable.GetAllBestBreeds(sid))
end

local menuInjected=false
local function TryInjectRematchMenu()
    if menuInjected then return end
    if not Rematch or not Rematch.menus or not Rematch.menus.AddToMenu then return end
    menuInjected=true
    -- 单个切换项：非最优→"设为最优品种"，已最优→"取消最优品种"
    Rematch.menus:AddToMenu("PetMenu",{
        text=function(_,p) return RematchHasBest(p) and "取消最优品种" or "设为最优品种" end,
        hidden=function(_,p) return not p end,
        func=function(_,p)
            if RematchHasBest(p) then RematchRemoveBest(p) else RematchSetBest(p,"custom") end
        end
    },"Find Teams")
    LOG("Rematch 菜单已注入")
end

-- ========== 暴雪原生：Hook PetJournal_InitPetButton + 右键菜单 ==========
local blizzMenuFrame=nil
local function BlizzRightClick(button,petID)
    local _,sid,_,_,_,_,_,_,_,_,_,lv,q,hp,pw,sp=C_PetJournal.GetPetInfoByPetID(petID);if not sid then return end
    local bid=CalcBreed(sid,lv,q,hp,pw,sp);if not bid then return end
    if not blizzMenuFrame then blizzMenuFrame=CreateFrame("Frame","GeneDexBDMenu",UIParent,"UIDropDownMenuTemplate") end
    local isBest=addonTable.IsBestBreed(sid,bid)
    local code=GetBreedCode(bid) or "?";local name=addonTable.GetBreedDisplayName and addonTable.GetBreedDisplayName(bid,code) or (code.." 品种")

    UIDropDownMenu_Initialize(blizzMenuFrame,function(_,lv)
        local info=UIDropDownMenu_CreateInfo()
        if lv==1 then
            info.text=name;info.isTitle=true;info.notCheckable=true;UIDropDownMenu_AddButton(info,1)
            if isBest then
                info.isTitle=false;info.text="取消最优品种";info.notCheckable=true
                info.func=function() addonTable.RemoveBestBreed(sid,bid) end;UIDropDownMenu_AddButton(info,1)
            else
                info.isTitle=false;info.text="设为最优品种";info.notCheckable=true;info.hasArrow=true;info.menuList="GeneDexBD_BlizzCats"
                UIDropDownMenu_AddButton(info,1)
            end
        elseif lv==2 then
            for _,cat in ipairs({"pvp","pve","collection","custom"}) do
                info.text=cat;info.notCheckable=true
                info.func=function() addonTable.SetBestBreed(sid,bid,cat,"") end;UIDropDownMenu_AddButton(info,2)
            end
        end
    end)
    ToggleDropDownMenu(1,nil,blizzMenuFrame,button,0,0)
end

local blizzHooked=false
local function TryHookBlizzard()
    if blizzHooked then return end
    if not PetJournal_InitPetButton then return end
    blizzHooked=true

    hooksecurefunc("PetJournal_InitPetButton",function(button,elementData)
        if not button or not elementData or not elementData.index then return end
        if not GeneDexDB or not GeneDexDB.Options or not GeneDexDB.Options.ShowInJournal then return end

        local petID = C_PetJournal.GetPetInfoByIndex(elementData.index)
        if not petID then return end
        local _,maxHP,power,speed,rarity = C_PetJournal.GetPetStats(petID)
        if not rarity then return end
        local _,speciesID,_,_,_,_,_,_,_,_,_,level = C_PetJournal.GetPetInfoByPetID(petID)
        if not speciesID then return end

        local q=(GeneDexDB.Options.AssumeRareQuality and rarity<4) and 4 or rarity
        local bid=CalcBreed(speciesID,level,q,maxHP,power,speed);if not bid then return end
        local code=GetBreedCode(bid);local best=addonTable.IsBestBreed(speciesID,bid)
        local text=best and ("★"..code) or code

        if button.name then
            local cur=button.name:GetText() or ""
            if not cur:find(code,1,true) then button.name:SetText(cur.."  "..text) end
            if best then button.name:SetTextColor(1,0.84,0) end
        end

        -- 右键菜单
        if not button._genedexRight then
            button._genedexRight=true
            button:SetScript("OnMouseUp",function(self,btnName)
                if btnName=="RightButton" then BlizzRightClick(self,petID) end
            end)
        end
    end)

    LOG("已 Hook PetJournal_InitPetButton")

    -- 强制刷新当前显示的原生面板（pcall 保护，12.0 函数可能不存在）
    if PetJournal and PetJournal:IsShown() then
        pcall(function()
            if PetJournal_ListUpdate then PetJournal_ListUpdate() end
        end)
        -- 备用刷新方式：通过搜索 API 触发列表重绘
        pcall(function()
            C_PetJournal.ClearSearchFilter()
            C_PetJournal.SetSearchFilter("")
        end)
    end
end

-- ========== 初始化 ==========
function addonTable.InitJournalUI()
    LOG("初始化")

    -- Rematch 初始化
    local function initR()
        C_Timer.After(0.3,function() TryHookRematch();TryInjectRematchMenu() end)
    end
    if C_AddOns.IsAddOnLoaded("Rematch") then initR() end
    local rf=CreateFrame("Frame");rf:RegisterEvent("ADDON_LOADED")
    rf:SetScript("OnEvent",function(_,_,a) if a=="Rematch" then initR();rf:UnregisterEvent("ADDON_LOADED") end end)

    -- 暴雪原生初始化
    local function initB()
        TryHookBlizzard()
    end
    local bcf=CreateFrame("Frame");bcf:RegisterEvent("ADDON_LOADED")
    bcf:SetScript("OnEvent",function(_,_,a)
        if a=="Blizzard_Collections" then initB();bcf:UnregisterEvent("ADDON_LOADED") end
    end)
    local pjf=CreateFrame("Frame");pjf:RegisterEvent("PET_JOURNAL_LIST_UPDATE")
    pjf:SetScript("OnEvent",function() TryHookBlizzard() end)

    -- 面板切换时强制刷新原生
    local prevMode="";local sw=CreateFrame("Frame");sw._t=0
    sw:SetScript("OnUpdate",function(self,elapsed)
        self._t=self._t+elapsed;if self._t<1 then return end;self._t=0
        local mode
        if RematchFrame and RematchFrame:IsShown() then mode="R"
        elseif PetJournal and PetJournal:IsShown() then mode="B"
        else mode="" end
        if mode~=prevMode then
            prevMode=mode
            if mode=="B" then
                C_Timer.After(0.3,function()
                    TryHookBlizzard()
                    -- 安全刷新：用搜索 API 触发列表重绘
                    pcall(function() C_PetJournal.ClearSearchFilter(); C_PetJournal.SetSearchFilter("") end)
                end)
            end
            LOG("面板切换: %s",mode=="R" and "Rematch" or mode=="B" and "暴雪原生" or "关闭")
        end
    end)
end
