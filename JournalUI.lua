-- GenDexBD JournalUI.lua
-- 策略：OnUpdate 节流扫描 RematchFrame 按钮，改写 Breed 文本
-- Fill Hook 对 Rematch 无效（scrollBox 缓存了旧函数引用）

local addonName, addonTable = ...
local time=time;local next=next;local pairs=pairs
local function LOG(...) print("|cff00ccff[GenDexBD]|r "..string.format(...)) end

-- API
function addonTable.SetBestBreed(s,b,c,n)
    if not s or not b then return end;if not GeneDexDB then return end
    local bb=GeneDexDB.BestBreeds;if not bb or type(bb)~="table" then GeneDexDB.BestBreeds={} end
    if not GeneDexDB.BestBreeds[s] then GeneDexDB.BestBreeds[s]={} end
    GeneDexDB.BestBreeds[s][b]={category=c or "custom",note=n or "",addedAt=time()}
end
function addonTable.RemoveBestBreed(s,b)
    if not s or not b then return end
    local bb=GeneDexDB and GeneDexDB.BestBreeds;if not bb or type(bb)~="table" then return end
    local sd=bb[s];if not sd or type(sd)~="table" then return end;sd[b]=nil;if not next(sd) then bb[s]=nil end
end
function addonTable.IsBestBreed(s,b)
    if not s or not b then return false end
    local bb=GeneDexDB and GeneDexDB.BestBreeds;if not bb or type(bb)~="table" then return false end
    local sd=bb[s];if not sd or type(sd)~="table" then return false end;return sd[b]~=nil
end
function addonTable.GetAllBestBreeds(s)
    if not s then return {} end
    local bb=GeneDexDB and GeneDexDB.BestBreeds;if not bb or type(bb)~="table" then return {} end
    local sd=bb[s];return (sd and type(sd)=="table") and sd or {}
end

-- 按钮标注（改写 Breed FontString 文本）
local function label(b)
    if not b or not b.Breed or not b.petID then return end
    if not Rematch or not Rematch.petInfo then return end
    local i=Rematch.petInfo:Fetch(b.petID)
    if not i or not i.hasBreed or not i.breedID or i.breedID==0 then return end
    local best=addonTable.IsBestBreed(i.speciesID,i.breedID)
    b.Breed:SetText(best and ("★"..i.breedName) or i.breedName)
    b.Breed:SetTextColor(best and 1 or 0.6,best and 0.84 or 0.6,0.6)
end

-- 扫描所有可见按钮
local function scanAll()
    if not RematchFrame or not RematchFrame:IsShown() then return end
    local function s(p,d)
        if d>6 then return end
        for _,c in ipairs({p:GetChildren()}) do
            if c.petID and c:IsVisible() then label(c) end;s(c,d+1)
        end
    end
    s(RematchFrame,0)
end

-- 右键菜单
function RematchSetBest(petID)
    if not Rematch or not Rematch.petInfo then return end
    local i=Rematch.petInfo:Fetch(petID);if not i or not i.hasBreed then return end
    addonTable.SetBestBreed(i.speciesID,i.breedID,"custom","")
    LOG("已保存: speciesID=%d breedID=%d (%s)",i.speciesID,i.breedID,i.breedName or "?")
    Rematch.petsPanel:Update()
end
function RematchRemoveBest(petID)
    if not Rematch or not Rematch.petInfo then return end
    local i=Rematch.petInfo:Fetch(petID);if not i or not i.hasBreed then return end
    addonTable.RemoveBestBreed(i.speciesID,i.breedID)
    LOG("已移除: speciesID=%d breedID=%d",i.speciesID,i.breedID)
    Rematch.petsPanel:Update()
end
function RematchHasBest(petID)
    if not Rematch or not Rematch.petInfo then return false end
    local i=Rematch.petInfo:Fetch(petID)
    return i and i.hasBreed and addonTable.IsBestBreed(i.speciesID,i.breedID)
end

-- 初始化
function addonTable.InitJournalUI()
    LOG("初始化")

    -- OnUpdate 扫描（0.3s 节流，不依赖 Fill Hook）
    local sf=CreateFrame("Frame");sf._t=0
    sf:SetScript("OnUpdate",function(self,elapsed)
        self._t=self._t+elapsed;if self._t<0.3 then return end;self._t=0
        scanAll()
    end)

    -- 菜单注入（延迟重试）
    local menuTries=0
    local function tryMenu()
        menuTries=menuTries+1
        if Rematch and Rematch.menus and Rematch.menus.AddToMenu then
            Rematch.menus:AddToMenu("PetMenu",{
                text=function(_,p) return RematchHasBest(p) and "取消最优品种" or "设为最优品种" end,
                hidden=function(_,p) return not p end,
                func=function(_,p) if RematchHasBest(p) then RematchRemoveBest(p) else RematchSetBest(p) end end
            },"Find Teams")
            LOG("Rematch 菜单已注入 (第%d次)",menuTries)
        elseif menuTries<30 then
            C_Timer.After(1,tryMenu)
        end
    end
    C_Timer.After(1,tryMenu)

    -- 保存/取消后立即刷新
    Rematch._genedexRefresh = function()
        if Rematch.petsPanel then Rematch.petsPanel:Update() end
        C_Timer.After(0.3,scanAll)
    end
end
