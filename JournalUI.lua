-- GenDexBD JournalUI.lua
-- Rematch: hook FillNormal/FillCompact 改写 Breed + 菜单注入
-- 暴雪原生: 不集成（Rematch 已接管宠物面板）

local addonName, addonTable = ...
local GetBreedCode=addonTable.GetBreedCode;local time=time
local pairs=pairs;local next=next;local strlower=string.lower;local strfind=string.find
local function LOG(...) print("|cff00ccff[GenDexBD]|r "..string.format(...)) end

-- ========== API ==========
function addonTable.SetBestBreed(sid,bid,cat,note)
    if not sid or not bid then return end;if not GeneDexDB then return end
    local bb=GeneDexDB.BestBreeds;if not bb or type(bb)~="table" then GeneDexDB.BestBreeds={} end
    if not GeneDexDB.BestBreeds[sid] then GeneDexDB.BestBreeds[sid]={} end
    GeneDexDB.BestBreeds[sid][bid]={category=cat or "custom",note=note or "",addedAt=time()}
end
function addonTable.RemoveBestBreed(sid,bid)
    if not sid or not bid then return end
    local bb=GeneDexDB and GeneDexDB.BestBreeds;if not bb or type(bb)~="table" then return end
    local sd=bb[sid];if not sd or type(sd)~="table" then return end
    sd[bid]=nil;if not next(sd) then bb[sid]=nil end
end
function addonTable.IsBestBreed(sid,bid)
    if not sid or not bid then return false end
    local bb=GeneDexDB and GeneDexDB.BestBreeds;if not bb or type(bb)~="table" then return false end
    local sd=bb[sid];if not sd or type(sd)~="table" then return false end;return sd[bid]~=nil
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

-- ========== Rematch Breed 改写 ==========
local function Decorate(button)
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

-- ========== Rematch Hook ==========
local rematchHooked=false
local function TryHookRematch()
    if rematchHooked then return end
    if not Rematch or not Rematch.petsPanel then return end
    if not Rematch.petsPanel.FillNormal then return end
    rematchHooked=true
    hooksecurefunc(Rematch.petsPanel,"FillNormal",function(_,button) Decorate(button) end)
    hooksecurefunc(Rematch.petsPanel,"FillCompact",function(_,button) Decorate(button) end)
    LOG("已 Hook Rematch.petsPanel FillNormal+FillCompact")
end

-- ========== Rematch 菜单 ==========
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
function addonTable.GetAllBestBreeds(sid)
    if not sid then return {} end
    local bb=GeneDexDB and GeneDexDB.BestBreeds;if not bb or type(bb)~="table" then return {} end
    local sd=bb[sid];return (sd and type(sd)=="table") and sd or {}
end

local menuInjected=false
local function TryInjectMenu()
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

-- ========== 初始化 ==========
function addonTable.InitJournalUI()
    LOG("初始化")

    local function initRematch()
        C_Timer.After(0.5, function()
            TryHookRematch();TryInjectMenu()
            if not rematchHooked then LOG("⚠ Hook 失败") end
            if not menuInjected then LOG("⚠ 菜单注入失败") end
        end)
    end

    if C_AddOns.IsAddOnLoaded("Rematch") then
        LOG("Rematch 已加载")
        initRematch()
    end

    local rf=CreateFrame("Frame");rf:RegisterEvent("ADDON_LOADED")
    rf:SetScript("OnEvent",function(_,_,a)
        if a=="Rematch" then initRematch();rf:UnregisterEvent("ADDON_LOADED") end
    end)
end
