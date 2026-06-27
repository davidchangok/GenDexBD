-- GenDexBD JournalUI.lua
-- Rematch: hooksecurefunc Rematch.petsPanel.FillNormal/FillCompact → 改写 Breed
-- 暴雪原生: PET_JOURNAL_LIST_UPDATE → 扫描 PetJournal 子元素

local addonName, addonTable = ...
local GetBreedCode=addonTable.GetBreedCode;local time=time;local type=type
local pairs=pairs;local ipairs=ipairs;local next=next;local strlower=string.lower;local strfind=string.find
local function LOG(...) print("|cff00ccff[GenDexBD]|r "..string.format(...)) end

-- ========== API ==========
function addonTable.SetBestBreed(sid,bid,cat,note)
    if not sid or not bid then return end; if not GeneDexDB then return end
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
    LOG("字段: H=%s P=%s S=%s",tostring(h),tostring(p),tostring(sp));fields={h,p,sp};return h,p,sp
end
local function Extract(pi) if not pi then return end;local h,p,s=Detect();if not h then return end;return pi[h],pi[p],pi[s] end
local function CalcBreed(sid,lv,q,hp,pw,sp)
    if not hp or not pw or not sp then return nil end
    local pi=C_PetJournal.GetPetInfoBySpeciesID(sid);if not pi then return nil end
    local bh,bp,bs=Extract(pi);if not bh then return nil end
    local q2=q or 4;if GeneDexDB and GeneDexDB.Options and GeneDexDB.Options.AssumeRareQuality and (not q or q<4) then q2=4 end
    return addonTable.CalculateBreedFromStats(hp,pw,sp,bh,bp,bs,lv,q2)
end

-- ========== 改写单个按钮的 Breed ==========
local function Decorate(button)
    if not button or not button.petID or not button.Breed then return end
    local _,sid,_,_,_,_,_,_,_,_,_,lv,q = C_PetJournal.GetPetInfoByPetID(button.petID)
    if not sid then return end
    -- Rematch 也推荐用 GetPetStats 拿属性
    local hp,pw,sp = C_PetJournal.GetPetStats(button.petID)
    if not hp or hp<=0 then return end
    local bid=CalcBreed(sid,lv,q,hp,pw,sp);if not bid then return end
    local code=GetBreedCode(bid);local best=addonTable.IsBestBreed(sid,bid)
    button.Breed:SetText(best and ("★"..code) or code)
    button.Breed:SetTextColor(best and 1 or 0.6,best and 0.84 or 0.6,0.6)
    button.Breed:Show()
end

-- ========== Rematch Fill Hook（参照 tdBattlePetScript hook FillTeamButton 的方式）==========
local rematchHooked=false
local function TryHookRematch()
    if rematchHooked then return end
    -- Rematch.petsPanel.FillNormal(button, petID) — panel 级回调
    -- 签名来自 autoScrollBox: self.normalFill(button,data)
    -- 函数体中 self:Fill(petID) 即 button:Fill(data)
    if not Rematch or not Rematch.petsPanel then return end
    if not Rematch.petsPanel.FillNormal then return end

    rematchHooked=true
    hooksecurefunc(Rematch.petsPanel,"FillNormal",function(_,button)
        Decorate(button)
    end)
    hooksecurefunc(Rematch.petsPanel,"FillCompact",function(_,button)
        Decorate(button)
    end)
    LOG("已 Hook Rematch.petsPanel FillNormal+FillCompact")
end

-- ========== Rematch 菜单注入 ==========
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

-- ========== 暴雪原生面板：PET_JOURNAL_LIST_UPDATE 扫描 ==========
local function ScanBlizzard()
    if not PetJournal or not PetJournal:IsShown() then return end

    local total, hasPetID, noStats, labeled = 0, 0, 0, 0
    local function scan(p,d)
        if d>5 then return end
        for _,c in ipairs({p:GetChildren()}) do
            total=total+1
            if c.petID and c:IsVisible() and not c.Breed then
                hasPetID=hasPetID+1
                local _,sid,_,_,_,_,_,_,_,_,_,lv,q = C_PetJournal.GetPetInfoByPetID(c.petID)
                -- 原生面板需要用 GetPetStats（不是 GetPetInfoByPetID）拿属性
                local hp,pw,sp = C_PetJournal.GetPetStats(c.petID)
                if sid and hp and hp>0 then
                    local bid=CalcBreed(sid,lv,q,hp,pw,sp)
                    if bid then
                        local code=GetBreedCode(bid);local best=addonTable.IsBestBreed(sid,bid)
                        if not c._gLabel then
                            local fs=c:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
                            fs:SetPoint("RIGHT",-4,0);fs:SetJustifyH("RIGHT");c._gLabel=fs
                        end
                        c._gLabel:SetText(best and ("★"..code) or code)
                        c._gLabel:SetTextColor(best and 1 or 0.6,best and 0.84 or 0.6,0.6)
                        c._gLabel:Show()
                        labeled=labeled+1
                    end
                else
                    noStats=noStats+1
                end
            end
            scan(c,d+1)
        end
    end
    scan(PetJournal,0)
    if total>0 then LOG("Blizz: 扫描%d 有petID=%d noStats=%d 标注=%d",total,hasPetID,noStats,labeled) end
end

-- ========== 初始化 ==========
function addonTable.InitJournalUI()
    LOG("初始化")

    -- 先检查 Rematch 是否已加载（Rematch 可能在 GenDexBD 之前加载）
    if C_AddOns.IsAddOnLoaded("Rematch") then
        LOG("Rematch 已加载，1秒后 Hook...")
        C_Timer.After(1, function()
            TryHookRematch();TryInjectMenu()
            if not rematchHooked then LOG("⚠ Hook 失败") end
            if not menuInjected then LOG("⚠ 菜单注入失败") end
        end)
    end

    -- 若未加载，等 ADDON_LOADED 事件
    local rf=CreateFrame("Frame");rf:RegisterEvent("ADDON_LOADED")
    rf:SetScript("OnEvent",function(_,_,a)
        if a=="Rematch" then
            LOG("Rematch ADDON_LOADED，1秒后 Hook...")
            C_Timer.After(1, function()
                TryHookRematch();TryInjectMenu()
                if not rematchHooked then LOG("⚠ Hook 失败") end
                if not menuInjected then LOG("⚠ 菜单注入失败") end
            end)
            rf:UnregisterEvent("ADDON_LOADED")
        end
    end)

    -- 暴雪原生面板
    local jf=CreateFrame("Frame");jf:RegisterEvent("PET_JOURNAL_LIST_UPDATE")
    jf:SetScript("OnEvent",function() ScanBlizzard() end)

    -- Blizzard_Collections 加载
    local bcf=CreateFrame("Frame");bcf:RegisterEvent("ADDON_LOADED")
    bcf:SetScript("OnEvent",function(_,_,a)
        if a=="Blizzard_Collections" then ScanBlizzard();bcf:UnregisterEvent("ADDON_LOADED") end
    end)
end
