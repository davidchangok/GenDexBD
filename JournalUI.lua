-- GenDexBD JournalUI.lua
-- Rematch: OnUpdate 轮询 RematchFrame 子元素 → 改写 Breed
-- 暴雪原生: PET_JOURNAL_LIST_UPDATE → 扫描 PetJournal 子元素

local addonName, addonTable = ...
local CalcBreedFromStats=addonTable.CalculateBreedFromStats;local GetBreedCode=addonTable.GetBreedCode
local GetBreedDisplayName=addonTable.GetBreedDisplayName;local time=time;local type=type
local pairs=pairs;local ipairs=ipairs;local next=next;local strlower=string.lower;local strfind=string.find
local function LOG(...) print("|cff00ccff[GenDexBD]|r "..string.format(...)) end
local function ERR(...) print("|cffff0000[GenDexBD]|r "..string.format(...)) end

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
local function DetectFields()
    if fields then return fields[1],fields[2],fields[3] end
    local s=C_PetJournal.GetPetInfoBySpeciesID(39) or C_PetJournal.GetPetInfoBySpeciesID(1);if not s then ERR("No sample");return end
    local ks={};for k in pairs(s) do ks[#ks+1]=k end
    local function f(ps) for _,k in ipairs(ks) do local l=strlower(k);for _,p in ipairs(ps) do if strfind(l,p,1,true) then return k end end end end
    local h=f({"health","hp"});local p=f({"power","attack","atk"});local sp=f({"speed","spd"})
    LOG("字段: H=%s P=%s S=%s",tostring(h),tostring(p),tostring(sp));fields={h,p,sp};return h,p,sp
end
local function Extract(pi) if not pi then return end;local h,p,s=DetectFields();if not h then return end;return pi[h],pi[p],pi[s] end
local function CalcBreed(sid,lv,q,hp,pw,sp)
    if not hp or not pw or not sp then return nil end
    local pi=C_PetJournal.GetPetInfoBySpeciesID(sid);if not pi then return nil end
    local bh,bp,bs=Extract(pi);if not bh then return nil end
    local q2=q or 4;if GeneDexDB and GeneDexDB.Options and GeneDexDB.Options.AssumeRareQuality and (not q or q<4) then q2=4 end
    return CalcBreedFromStats(hp,pw,sp,bh,bp,bs,lv,q2)
end
local function BreedLabel(sid,lv,q,hp,pw,sp)
    if not hp then return nil end;local bid=CalcBreed(sid,lv,q,hp,pw,sp);if not bid then return nil end
    local code=GetBreedCode(bid);local best=addonTable.IsBestBreed(sid,bid)
    return best and ("★"..code) or code,best,bid
end

-- ========== 按钮扫描 + 标注 ==========
local scanned, labeled = 0, 0

local function ScanAndLabel(root, maxDepth, source)
    local function scan(p,d)
        if d>maxDepth then return end
        for _,c in ipairs({p:GetChildren()}) do
            scanned=scanned+1
            if c.petID and c:IsVisible() then
                -- 有 Breed → Rematch 按钮 → 直接改写
                if c.Breed then
                    local _,sid,_,_,_,_,_,_,_,_,_,lv,q,hp,pw,sp=C_PetJournal.GetPetInfoByPetID(c.petID)
                    if sid and hp then
                        local text,best,bid=BreedLabel(sid,lv,q,hp,pw,sp)
                        if text then
                            c.Breed:SetText(text)
                            c.Breed:SetTextColor(best and 1 or 0.6,best and 0.84 or 0.6,0.6)
                            c.Breed:Show()
                            labeled=labeled+1
                        end
                    end
                else
                    -- 无 Breed → 暴雪原生按钮
                    local _,sid,_,_,_,_,_,_,_,_,_,lv,q,hp,pw,sp=C_PetJournal.GetPetInfoByPetID(c.petID)
                    if sid and hp then
                        local text,best,bid=BreedLabel(sid,lv,q,hp,pw,sp)
                        if text then
                            if not c._gLabel then
                                local fs=c:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
                                fs:SetPoint("RIGHT",-4,0);fs:SetJustifyH("RIGHT");c._gLabel=fs
                            end
                            c._gLabel:SetText(text)
                            c._gLabel:SetTextColor(best and 1 or 0.6,best and 0.84 or 0.6,0.6)
                            c._gLabel:Show()
                            labeled=labeled+1
                        end
                    end
                end
            end
            scan(c,d+1)
        end
    end
    scan(root,0)
end

-- ========== Rematch 菜单（全局函数，供 Rematch 调用） ==========
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
    return next(addonTable.GetAllBestBreeds(sid))~=nil
end

local menuInjected=false,menuRetries=0
local function TryInjectMenu()
    if menuInjected then return end; menuRetries=menuRetries+1
    if not rematch or not rematch.menus or not rematch.menus.AddToMenu then
        if menuRetries<=5 then LOG("菜单注入延迟 #%d: rematch=%s menus=%s",
            menuRetries,tostring(rematch~=nil),tostring(rematch and rematch.menus~=nil)) end
        return
    end
    menuInjected=true
    rematch.menus:Register("GeneDexBD_BestCat",{
        {title="选择最优场景"},
        {text="PvP 对战", func=function(_,p) RematchSetBest(p,"pvp") end},
        {text="PvE 任务", func=function(_,p) RematchSetBest(p,"pve") end},
        {text="收藏",     func=function(_,p) RematchSetBest(p,"collection") end},
        {text="自定义",   func=function(_,p) RematchSetBest(p,"custom") end},
        {text=CANCEL},
    })
    rematch.menus:AddToMenu("PetMenu",{
        text="★ 设为最优品种",subMenu="GeneDexBD_BestCat",
        hidden=function(_,p) return not p or not C_PetJournal.GetPetInfoByPetID(p) end
    },"Find Teams")
    rematch.menus:AddToMenu("PetMenu",{
        text="取消最优品种",
        hidden=function(_,p) return not p or not RematchHasBest(p) end,
        func=function(_,p) RematchRemoveBest(p) end
    },"Find Teams")
    LOG("Rematch 菜单已注入 (第%d次尝试)",menuRetries)
end

-- ========== 轮询引擎 ==========
local tick,lastLog=0,0
local pf=CreateFrame("Frame")
pf:SetScript("OnUpdate",function(self,elapsed)
    tick=tick+elapsed

    -- 菜单注入尝试（每秒一次，直到成功）
    if not menuInjected and tick-lastLog>1 then lastLog=tick;TryInjectMenu() end

    -- 按钮刷新（每秒0.5次）
    if tick-lastLog>0.5 then
        lastLog=tick;scanned=0;labeled=0
        -- Rematch
        if RematchFrame and RematchFrame:IsShown() then
            ScanAndLabel(RematchFrame,5,"Rematch")
            if scanned>0 then LOG("Rematch: 扫描%d 标注%d",scanned,labeled) end
        end
        -- 暴雪原生
        if PetJournal and PetJournal:IsShown() then
            ScanAndLabel(PetJournal,4,"Blizz")
            if scanned>0 then LOG("PetJournal: 扫描%d 标注%d",scanned,labeled) end
        end
    end
end)

-- ========== 初始化 ==========
function addonTable.InitJournalUI()
    LOG("初始化 (OnUpdate 轮询模式)")
    -- 启动时立刻尝试一次
    TryInjectMenu()
end
