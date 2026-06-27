-- GenDexBD JournalUI.lua
-- 双模式品种标注：Rematch (Hook Fill) + 暴雪原生 (Hook PetJournal_InitPetButton)

local addonName, addonTable = ...
local GetBreedCode=addonTable.GetBreedCode;local time=time
local pairs=pairs;local next=next;local strlower=string.lower;local strfind=string.find
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
local fields=nil
local function Detect()
    if fields then return fields[1],fields[2],fields[3] end
    local s=C_PetJournal.GetPetInfoBySpeciesID(39) or C_PetJournal.GetPetInfoBySpeciesID(1);if not s then return end
    local ks={};for k in pairs(s) do ks[#ks+1]=k end
    local function f(ps) for _,k in ipairs(ks) do local l=strlower(k);for _,p in ipairs(ps) do if strfind(l,p,1,true) then return k end end end end
    local h=f({"health","hp"});local p=f({"power","attack","atk"});local sp=f({"speed","spd"})
    fields={h,p,sp};LOG("字段: H=%s P=%s S=%s",tostring(h),tostring(p),tostring(sp));return h,p,sp
end
local function Extract(pi) if not pi then return end;local h,p,s=Detect();if not h then return end;return pi[h],pi[p],pi[s] end
local function CalcBreed(sid,lv,q,hp,pw,sp)
    if not hp or not pw or not sp then return nil end
    local pi=C_PetJournal.GetPetInfoBySpeciesID(sid);if not pi then return nil end
    local bh,bp,bs=Extract(pi);if not bh then return nil end
    local q2=q or 4;if GeneDexDB and GeneDexDB.Options and GeneDexDB.Options.AssumeRareQuality and (not q or q<4) then q2=4 end
    return addonTable.CalculateBreedFromStats(hp,pw,sp,bh,bp,bs,lv,q2)
end

-- ========== Rematch：Hook Fill + 菜单 ==========
local function RematchDecorate(button)
    if not button or not button.petID or not button.Breed then return end
    local _,sid,_,_,_,_,_,_,_,_,_,lv,q = C_PetJournal.GetPetInfoByPetID(button.petID)
    if not sid then return end
    local hp,pw,sp = C_PetJournal.GetPetStats(button.petID)
    if not hp or hp<=0 then return end
    local bid=CalcBreed(sid,lv,q,hp,pw,sp);if not bid then return end
    local code=GetBreedCode(bid);local best=addonTable.IsBestBreed(sid,bid)
    button.Breed:SetText(best and ("★"..code) or code)
    button.Breed:SetTextColor(best and 1 or 0.6,best and 0.84 or 0.6,0.6)
    button.Breed:Show()
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
    local _,sid,_,_,_,_,_,_,_,_,_,lv,q,hp,pw,sp=C_PetJournal.GetPetInfoByPetID(petID);if not sid then return end
    local bid=CalcBreed(sid,lv,q,hp,pw,sp);if bid then addonTable.SetBestBreed(sid,bid,cat,"") end
end
function RematchRemoveBest(petID)
    local _,sid=C_PetJournal.GetPetInfoByPetID(petID);if not sid then return end
    for bid in pairs(addonTable.GetAllBestBreeds(sid)) do addonTable.RemoveBestBreed(sid,bid) end
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
    Rematch.menus:Register("GeneDexBD_BestCat",{
        {title="选择最优场景"},
        {text="PvP 对战", func=function(_,p) RematchSetBest(p,"pvp") end},
        {text="PvE 任务", func=function(_,p) RematchSetBest(p,"pve") end},
        {text="收藏",     func=function(_,p) RematchSetBest(p,"collection") end},
        {text="自定义",   func=function(_,p) RematchSetBest(p,"custom") end},
        {text=CANCEL},
    })
    Rematch.menus:AddToMenu("PetMenu",{
        text="★ 设为最优品种",subMenu="GeneDexBD_BestCat",
        hidden=function(_,p) return not p or not C_PetJournal.GetPetInfoByPetID(p) end
    },"Find Teams")
    Rematch.menus:AddToMenu("PetMenu",{
        text="取消最优品种",
        hidden=function(_,p) return not p or not RematchHasBest(p) end,
        func=function(_,p) RematchRemoveBest(p) end
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
