-- GenDexBD JournalUI.lua
-- Rematch: hooksecurefunc Fill → 改写 Breed FontString + 注入右键菜单
-- 暴雪原生: OnMouseUp 右键菜单

local addonName, addonTable = ...

local CalculateBreedFromStats = addonTable.CalculateBreedFromStats
local GetBreedCode = addonTable.GetBreedCode
local GetBreedDisplayName = addonTable.GetBreedDisplayName
local time = time; local type = type; local pairs = pairs; local ipairs = ipairs
local next = next; local strlower = string.lower; local strfind = string.find
local function LOG(...) print("|cff00ccff[GenDexBD]|r "..string.format(...)) end

-- ============================================================================
-- 最优品种管理 API
-- ============================================================================
function addonTable.SetBestBreed(sid, bid, cat, note)
    if not sid or not bid then return end
    if not GeneDexDB then return end
    local bb = GeneDexDB.BestBreeds; if not bb or type(bb)~="table" then GeneDexDB.BestBreeds={} end
    if not GeneDexDB.BestBreeds[sid] then GeneDexDB.BestBreeds[sid]={} end
    GeneDexDB.BestBreeds[sid][bid]={category=cat or "custom",note=note or "",addedAt=time()}
end
function addonTable.RemoveBestBreed(sid, bid)
    if not sid or not bid then return end
    local bb=GeneDexDB and GeneDexDB.BestBreeds; if not bb or type(bb)~="table" then return end
    local sd=bb[sid]; if not sd or type(sd)~="table" then return end
    sd[bid]=nil; if not next(sd) then bb[sid]=nil end
end
function addonTable.IsBestBreed(sid,bid)
    if not sid or not bid then return false end
    local bb=GeneDexDB and GeneDexDB.BestBreeds; if not bb or type(bb)~="table" then return false end
    local sd=bb[sid]; if not sd or type(sd)~="table" then return false end
    return sd[bid]~=nil
end
function addonTable.GetBestBreedInfo(sid,bid)
    if not sid or not bid then return nil end
    local bb=GeneDexDB and GeneDexDB.BestBreeds; if not bb or type(bb)~="table" then return nil end
    local sd=bb[sid]; if not sd or type(sd)~="table" then return nil end
    local bd=sd[bid]; return (bd and type(bd)=="table") and bd or nil
end
function addonTable.GetAllBestBreeds(sid)
    if not sid then return {} end
    local bb=GeneDexDB and GeneDexDB.BestBreeds; if not bb or type(bb)~="table" then return {} end
    local sd=bb[sid]; return (sd and type(sd)=="table") and sd or {}
end

-- ============================================================================
-- 字段探测+品种推算
-- ============================================================================
local petInfoFields=nil
local function DetectFields()
    if petInfoFields then return petInfoFields[1],petInfoFields[2],petInfoFields[3] end
    local s=C_PetJournal.GetPetInfoBySpeciesID(39) or C_PetJournal.GetPetInfoBySpeciesID(1)
    if not s then return nil end
    local ks={}; for k in pairs(s) do ks[#ks+1]=k end
    local function f(ps) for _,k in ipairs(ks) do
        local l=strlower(k); for _,p in ipairs(ps) do if strfind(l,p,1,true) then return k end end
    end end
    local h=f({"health","hp"}); local p=f({"power","attack","atk"}); local sp=f({"speed","spd"})
    petInfoFields={h,p,sp}; LOG("字段: H=%s P=%s S=%s",tostring(h),tostring(p),tostring(sp))
    return h,p,sp
end
local function Extract(p) if not p then return end; local h,po,s=DetectFields()
    if not h then return end; return p[h],p[po],p[s] end
local function CalcBreed(sid,lv,q,hp,pw,sp)
    if not hp or not pw or not sp then return nil end
    local pi=C_PetJournal.GetPetInfoBySpeciesID(sid); if not pi then return nil end
    local bh,bp,bs=Extract(pi); if not bh then return nil end
    local q2=q or 4; if GeneDexDB and GeneDexDB.Options and GeneDexDB.Options.AssumeRareQuality then if not q or q2<4 then q2=4 end end
    return CalculateBreedFromStats(hp,pw,sp,bh,bp,bs,lv,q2)
end

-- ============================================================================
-- 品种标注文本生成
-- ============================================================================
local function BreedLabel(sid,lv,q,hp,pw,sp)
    if not hp then return nil end
    local bid=CalcBreed(sid,lv,q,hp,pw,sp); if not bid then return nil end
    local code=GetBreedCode(bid); local best=addonTable.IsBestBreed(sid,bid)
    return best and ("★"..code) or code, best
end

-- ============================================================================
-- Rematch Fill Hook — 在 Rematch 设置 Breed 后追加最优标记
-- ============================================================================
local rewrites=0
local function RewriteRematchBreed(button)
    if not button or not button.petID or not button.Breed then return end
    local _,sid,_,_,_,_,_,_,_,_,_,lv,q,hp,pw,sp=C_PetJournal.GetPetInfoByPetID(button.petID)
    if not sid then return end
    local text,best=BreedLabel(sid,lv,q,hp,pw,sp)
    if not text then return end
    button.Breed:SetText(text)
    button.Breed:SetTextColor(best and 1 or 0.6, best and 0.84 or 0.6, 0.6)
    rewrites=rewrites+1
end

local rematchHooksInstalled=false
local function InstallRematchHooks()
    if rematchHooksInstalled then return end
    if not RematchNormalPetListButtonTemplate then return end
    rematchHooksInstalled=true

    hooksecurefunc(RematchNormalPetListButtonTemplate,"Fill",function(self)
        RewriteRematchBreed(self)
    end)
    hooksecurefunc(RematchCompactPetListButtonTemplate,"Fill",function(self)
        RewriteRematchBreed(self)
    end)
    LOG("已 Hook Rematch Fill (Normal+Compact)")
end

-- ============================================================================
-- 暴雪原生按钮标注
-- ============================================================================
local function LabelBlizzardButton(button)
    if not button or not button.petID or button.Breed then return end
    local _,sid,_,_,_,_,_,_,_,_,_,lv,q,hp,pw,sp=C_PetJournal.GetPetInfoByPetID(button.petID)
    if not sid then return end
    local text,best=BreedLabel(sid,lv,q,hp,pw,sp)
    if not text then return end
    if not button._gLabel then
        local fs=button:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
        fs:SetPoint("RIGHT",-4,0); fs:SetJustifyH("RIGHT"); button._gLabel=fs
    end
    button._gLabel:SetText(text)
    button._gLabel:SetTextColor(best and 1 or 0.6,best and 0.84 or 0.6,0.6)
    button._gLabel:Show()
end

-- ============================================================================
-- 暴雪原生面板右键
-- ============================================================================
local menuFrame=nil
local function StartBlizzardMenu(btn,sid,bid)
    if not menuFrame then menuFrame=CreateFrame("Frame","GeneDexBDMenu",UIParent,"UIDropDownMenuTemplate") end
    local best=addonTable.IsBestBreed(sid,bid)
    local code=GetBreedCode(bid) or "?"; local name=GetBreedDisplayName(bid,code)
    UIDropDownMenu_Initialize(menuFrame,function(_,lv)
        local info=UIDropDownMenu_CreateInfo()
        if lv==1 then
            info.text=name; info.isTitle=true; info.notCheckable=true; UIDropDownMenu_AddButton(info,1)
            if best then
                local bi=addonTable.GetBestBreedInfo(sid,bid)
                if bi then info.isTitle=true; info.text="已标记: "..(bi.category or "custom"); UIDropDownMenu_AddButton(info,1) end
                info.isTitle=false; info.text="取消最优品种"; info.notCheckable=true
                info.func=function() addonTable.RemoveBestBreed(sid,bid) end; UIDropDownMenu_AddButton(info,1)
            else
                info.isTitle=false; info.text="设为最优品种"; info.notCheckable=true; info.hasArrow=true; info.menuList="GeneDexBD_Cats"
                UIDropDownMenu_AddButton(info,1)
            end
        elseif lv==2 then
            for _,cat in ipairs({"pvp","pve","collection","custom"}) do
                local cn=addonTable.GetBestBreedCategoryName and addonTable.GetBestBreedCategoryName(cat) or cat
                info.text=cn; info.notCheckable=true
                info.func=function() addonTable.SetBestBreed(sid,bid,cat,"") end; UIDropDownMenu_AddButton(info,2)
            end
        end
    end)
    ToggleDropDownMenu(1,nil,menuFrame,btn,0,0)
end

local function HookBlizzardRightClick(button)
    if button._gRight then return end; button._gRight=true
    button:SetScript("OnMouseUp",function(self,btnName)
        if btnName~="RightButton" then return end
        local _,sid,_,_,_,_,_,_,_,_,_,lv,q,hp,pw,sp=C_PetJournal.GetPetInfoByPetID(self.petID)
        if not sid then return end
        local bid=CalcBreed(sid,lv,q,hp,pw,sp); if not bid then return end
        StartBlizzardMenu(self,sid,bid)
    end)
end

-- ============================================================================
-- Rematch 右键菜单注入
-- ============================================================================
function RematchSetBest(petID,cat)
    local _,sid,_,_,_,_,_,_,_,_,_,lv,q,hp,pw,sp=C_PetJournal.GetPetInfoByPetID(petID)
    if not sid then return end
    local bid=CalcBreed(sid,lv,q,hp,pw,sp)
    if bid then addonTable.SetBestBreed(sid,bid,cat,"") end
end
function RematchRemoveBest(petID)
    local _,sid=C_PetJournal.GetPetInfoByPetID(petID)
    if not sid then return end
    for bid in pairs(addonTable.GetAllBestBreeds(sid)) do addonTable.RemoveBestBreed(sid,bid) end
end
function RematchHasBest(petID)
    local _,sid=C_PetJournal.GetPetInfoByPetID(petID)
    if not sid then return false end; return next(addonTable.GetAllBestBreeds(sid))
end

local rematchMenuInjected=false
function InjectRematchMenu()
    if rematchMenuInjected then return end
    if not rematch or not rematch.menus or not rematch.menus.AddToMenu then return end
    rematchMenuInjected=true

    rematch.menus:Register("GeneDexBD_BestCat",{
        {title="选择最优场景"},
        {text="PvP 对战",  func=function(_,p) RematchSetBest(p,"pvp") end},
        {text="PvE 任务",  func=function(_,p) RematchSetBest(p,"pve") end},
        {text="收藏",      func=function(_,p) RematchSetBest(p,"collection") end},
        {text="自定义",    func=function(_,p) RematchSetBest(p,"custom") end},
        {text=CANCEL},
    })
    rematch.menus:AddToMenu("PetMenu",{
        text="★ 设为最优品种", subMenu="GeneDexBD_BestCat",
        hidden=function(_,p) return not p or not RematchHasBest(p) and not C_PetJournal.GetPetInfoByPetID(p) end,
    },"Find Teams")
    rematch.menus:AddToMenu("PetMenu",{
        text="取消最优品种",
        hidden=function(_,p) return not p or not RematchHasBest(p) end,
        func=function(_,p) RematchRemoveBest(p) end,
    },"Find Teams")
    LOG("Rematch 菜单已注入")
end

-- ============================================================================
-- 初始化
-- ============================================================================

function addonTable.InitJournalUI()
    LOG("初始化 (双模式: FillHook + 菜单注入)")

    -- Rematch Fill Hook（等模板加载后）
    if RematchNormalPetListButtonTemplate then InstallRematchHooks() end
    local rhf=CreateFrame("Frame"); rhf:SetScript("OnUpdate",function(self,elapsed)
        self._t=(self._t or 0)+elapsed
        if self._t<0.3 then return end; self._t=0
        if RematchNormalPetListButtonTemplate and not rematchHooksInstalled then InstallRematchHooks() end
    end)

    -- Rematch 菜单注入
    if rematch and rematch.menus then InjectRematchMenu() end
    local rmf=CreateFrame("Frame"); rmf:RegisterEvent("ADDON_LOADED")
    rmf:SetScript("OnEvent",function(_,_,a)
        if a=="Rematch" then InjectRematchMenu(); rmf:UnregisterEvent("ADDON_LOADED") end
    end)

    -- 暴雪原生面板按钮标注 + 右键
    local jf=CreateFrame("Frame"); jf:RegisterEvent("PET_JOURNAL_LIST_UPDATE")
    jf:SetScript("OnEvent",function()
        if not PetJournal or not PetJournal:IsShown() then return end
        local function scan(p,d)
            if d>5 then return end
            for _,c in ipairs({p:GetChildren()}) do
                if c:IsVisible() and c.petID and not c.Breed then
                    LabelBlizzardButton(c); HookBlizzardRightClick(c)
                end; scan(c,d+1)
            end
        end
        scan(PetJournal,0)
    end)

    -- Blizzard_Collections 加载
    local bcf=CreateFrame("Frame"); bcf:RegisterEvent("ADDON_LOADED")
    bcf:SetScript("OnEvent",function(_,_,a)
        if a=="Blizzard_Collections" then
            if PetJournal and PetJournal:IsShown() then
                local jf2=CreateFrame("Frame"); jf2:SetScript("OnUpdate",function(self2,elapsed)
                    self2._t=(self2._t or 0)+elapsed
                    if self2._t<0.2 then return end; self2:SetScript("OnUpdate",nil)
                    local function scan(p,d)
                        if d>5 then return end
                        for _,c in ipairs({p:GetChildren()}) do
                            if c:IsVisible() and c.petID and not c.Breed then
                                LabelBlizzardButton(c); HookBlizzardRightClick(c)
                            end; scan(c,d+1)
                        end
                    end
                    scan(PetJournal,0)
                end)
            end
            bcf:UnregisterEvent("ADDON_LOADED")
        end
    end)

    LOG("初始化完成")
end
