-- GenDexBD JournalUI.lua
-- 双模式：Rematch (Hook Fill + 品种标注 + 五星 + 右键菜单)
--         暴雪原生 (Hook PetJournal_InitPetButton + 右键菜单)
-- 品种数据来源：直接用 Rematch petInfo（已有 BattlePetBreedID 算好的 breedID/breedName）

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
function addonTable.GetAllBestBreeds(sid)
    if not sid then return {} end
    local bb=GeneDexDB and GeneDexDB.BestBreeds;if not bb or type(bb)~="table" then return {} end
    local sd=bb[sid];return (sd and type(sd)=="table") and sd or {}
end

-- ========== Rematch 品种标注 + 五星 ==========
local function Decorate(button)
    if not button or not button.petID or not button.Icon then return end
    if not Rematch or not Rematch.petInfo then return end
    local info=Rematch.petInfo:Fetch(button.petID)
    if not info or not info.hasBreed or not info.breedID or info.breedID==0 then return end

    local breedID=info.breedID;local breedName=info.breedName;local speciesID=info.speciesID
    local isBest=addonTable.IsBestBreed(speciesID,breedID)

    if button.Breed then
        button.Breed:SetText(isBest and ("★"..breedName) or breedName)
        button.Breed:SetTextColor(isBest and 1 or 0.6,isBest and 0.84 or 0.6,0.6)
        button.Breed:Show()
    end

    if isBest then
        if not button._gStar then
            local star=button:CreateTexture(nil,"OVERLAY")
            star:SetAtlas("PetJournal-FavoritesIcon");star:SetSize(16,16)
            star:SetPoint("TOPRIGHT",button.Icon,"TOPRIGHT",4,4);button._gStar=star
        end;button._gStar:Show()
    else
        if button._gStar then button._gStar:Hide() end
    end
end

local rematchHooked=false
local function TryHookRematch()
    if rematchHooked then return end
    if not Rematch or not Rematch.petsPanel or not Rematch.petsPanel.FillNormal then return end
    rematchHooked=true
    hooksecurefunc(Rematch.petsPanel,"FillNormal",function(_,b) Decorate(b) end)
    hooksecurefunc(Rematch.petsPanel,"FillCompact",function(_,b) Decorate(b) end)
    LOG("已 Hook Rematch Fill");Rematch.petsPanel:Update()
end

-- ========== Rematch 右键菜单 ==========
function RematchSetBest(petID,cat)
    if not Rematch or not Rematch.petInfo then return end
    local info=Rematch.petInfo:Fetch(petID)
    if not info or not info.hasBreed then LOG("⚠ 品种未确定");return end
    addonTable.SetBestBreed(info.speciesID,info.breedID,cat or "custom","")
    LOG("已保存: speciesID=%d breedID=%d (%s)",info.speciesID,info.breedID,info.breedName or "?")
    Rematch.petsPanel:Update()
end
function RematchRemoveBest(petID)
    if not Rematch or not Rematch.petInfo then return end
    local info=Rematch.petInfo:Fetch(petID)
    if not info or not info.speciesID then return end
    for bid in pairs(addonTable.GetAllBestBreeds(info.speciesID)) do addonTable.RemoveBestBreed(info.speciesID,bid) end
    LOG("已移除: speciesID=%d",info.speciesID);Rematch.petsPanel:Update()
end
function RematchHasBest(petID)
    if not Rematch or not Rematch.petInfo then return false end
    local info=Rematch.petInfo:Fetch(petID)
    return info and info.speciesID and next(addonTable.GetAllBestBreeds(info.speciesID))
end

local menuInjected=false
local function TryInjectRematchMenu()
    if menuInjected then return end
    if not Rematch or not Rematch.menus or not Rematch.menus.AddToMenu then return end;menuInjected=true
    Rematch.menus:AddToMenu("PetMenu",{
        text=function(_,p) return RematchHasBest(p) and "取消最优品种" or "设为最优品种" end,
        hidden=function(_,p) return not p end,
        func=function(_,p) if RematchHasBest(p) then RematchRemoveBest(p) else RematchSetBest(p,"custom") end end
    },"Find Teams")
    LOG("Rematch 菜单已注入")
end

-- ========== 暴雪原生面板 ==========
local blizzHooked=false
local function TryHookBlizzard()
    if blizzHooked then return end
    if not PetJournal_InitPetButton then return end;blizzHooked=true
    hooksecurefunc("PetJournal_InitPetButton",function(button,elementData)
        if not button or not elementData or not elementData.index then return end
        if not GeneDexDB or not GeneDexDB.Options or not GeneDexDB.Options.ShowInJournal then return end
        local petID=C_PetJournal.GetPetInfoByIndex(elementData.index);if not petID then return end
        local _,maxHP,power,speed,rarity=C_PetJournal.GetPetStats(petID);if not rarity then return end
        local _,speciesID,_,_,_,_,_,_,_,_,_,level=C_PetJournal.GetPetInfoByPetID(petID);if not speciesID then return end
        -- 用 BreedMath 直接推算（暴雪原生面板没有 Rematch petInfo）
        local q=(GeneDexDB.Options.AssumeRareQuality and rarity<4) and 4 or rarity
        local bid=addonTable.CalculateBreedFromStats(maxHP,power,speed,1,1,1,level,q)
        -- 简化：无法获取 baseStats，跳过（后续可补 BPBID_Arrays 回退）
        if not bid then return end
        local code=GetBreedCode(bid);local best=addonTable.IsBestBreed(speciesID,bid)
        local text=best and ("★"..code) or code
        if button.name then
            local cur=button.name:GetText() or ""
            if not cur:find(code,1,true) then button.name:SetText(cur.."  "..text) end
            if best then button.name:SetTextColor(1,0.84,0) end
        end
        if not button._genedexRight then
            button._genedexRight=true
            button:SetScript("OnMouseUp",function(self,btnName)
                if btnName=="RightButton" then BlizzRightClick(button,petID) end
            end)
        end
    end)
    LOG("已 Hook PetJournal_InitPetButton")
    if PetJournal and PetJournal:IsShown() then pcall(C_PetJournal.ClearSearchFilter);pcall(function() C_PetJournal.SetSearchFilter("") end) end
end

local blizzMenuFrame=nil
function BlizzRightClick(button,petID)
    local _,speciesID,_,_,_,_,_,_,_,_,_,level=C_PetJournal.GetPetInfoByPetID(petID);if not speciesID then return end
    if not blizzMenuFrame then blizzMenuFrame=CreateFrame("Frame","GeneDexBDMenu",UIParent,"UIDropDownMenuTemplate") end
    local info=addonTable.GetAllBestBreeds(speciesID);local hasAny=next(info)
    UIDropDownMenu_Initialize(blizzMenuFrame,function(_,lv)
        local inf=UIDropDownMenu_CreateInfo()
        if lv==1 then
            inf.text=hasAny and "取消最优品种" or "设为最优品种";inf.notCheckable=true
            inf.func=function()
                if hasAny then for bid in pairs(info) do addonTable.RemoveBestBreed(speciesID,bid) end
                else
                    -- 原生面板品种推算较难，提示去 Rematch 操作
                end
                UIDropDownMenu_AddButton(inf,1)
            end
        end
    end)
    ToggleDropDownMenu(1,nil,blizzMenuFrame,button,0,0)
end

-- ========== 初始化 ==========
function addonTable.InitJournalUI()
    LOG("初始化")
    local function initR()
        C_Timer.After(0.3,function() TryHookRematch();TryInjectRematchMenu() end)
    end
    if C_AddOns.IsAddOnLoaded("Rematch") then initR() end
    local rf=CreateFrame("Frame");rf:RegisterEvent("ADDON_LOADED")
    rf:SetScript("OnEvent",function(_,_,a) if a=="Rematch" then initR();rf:UnregisterEvent("ADDON_LOADED") end end)

    local bcf=CreateFrame("Frame");bcf:RegisterEvent("ADDON_LOADED")
    bcf:SetScript("OnEvent",function(_,_,a) if a=="Blizzard_Collections" then TryHookBlizzard();bcf:UnregisterEvent("ADDON_LOADED") end end)
    local pjf=CreateFrame("Frame");pjf:RegisterEvent("PET_JOURNAL_LIST_UPDATE")
    pjf:SetScript("OnEvent",function() TryHookBlizzard() end)

    local prevMode="";local sw=CreateFrame("Frame");sw._t=0
    sw:SetScript("OnUpdate",function(self,elapsed)
        self._t=self._t+elapsed;if self._t<1 then return end;self._t=0
        local mode
        if RematchFrame and RematchFrame:IsShown() then mode="R"
        elseif PetJournal and PetJournal:IsShown() then mode="B" else mode="" end
        if mode~=prevMode then
            prevMode=mode
            if mode=="B" then C_Timer.After(0.3,function()
                TryHookBlizzard()
                pcall(function() C_PetJournal.ClearSearchFilter();C_PetJournal.SetSearchFilter("") end)
            end) end
            LOG("面板切换: %s",mode=="R" and "Rematch" or mode=="B" and "暴雪原生" or "关闭")
        end
    end)
end
