-- GenDexBD JournalUI.lua - Mixin Fill Hook + 右键菜单（已拥有+未拥有）

local addonName, addonTable = ...
local time=time;local next=next
local GetLocaleString = addonTable.GetLocaleString
local function LOG(...) print("|cff00ccff[GenDexBD]|r "..string.format(...)) end

function addonTable.SetBestBreed(s,b,c,n)
    if not s or not b then return end;if not GeneDexDB then return end
    local bb=GeneDexDB.BestBreeds;if not bb or type(bb)~="table" then GeneDexDB.BestBreeds={} end
    GeneDexDB.BestBreeds[s]={};GeneDexDB.BestBreeds[s][b]={category=c or "custom",note=n or "",addedAt=time()}
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

-- 品种列表（与 BreedData.lua 同步维护）
local ALL_BREEDS = {{3,"B/B"},{4,"P/P"},{5,"S/S"},{6,"H/H"},{7,"H/P"},{8,"P/S"},{9,"H/S"},{10,"P/B"},{11,"S/B"},{12,"H/B"},{13,"P/H"},{14,"H/S"}}

local function label(b)
    if not b or not b.Breed or not b.petID then return end
    if not Rematch or not Rematch.petInfo then return end
    local i=Rematch.petInfo:Fetch(b.petID)
    if not i or not i.hasBreed or not i.breedID or i.breedID==0 then return end
    local best=addonTable.IsBestBreed(i.speciesID,i.breedID)
    b.Breed:SetText(best and ("★"..i.breedName) or i.breedName)
    b.Breed:SetTextColor(best and 1 or 0.6,best and 0.84 or 0.6,0.6)
end

function RematchSetBest(petID)
    if not Rematch or not Rematch.petInfo then return end
    local i=Rematch.petInfo:Fetch(petID);if not i or not i.hasBreed then return end
    addonTable.SetBestBreed(i.speciesID,i.breedID,"custom","")
    LOG("已保存: speciesID=%d breedID=%d (%s)",i.speciesID,i.breedID,i.breedName or "?")
    if Rematch.petsPanel then Rematch.petsPanel:Update() end
end
function RematchRemoveBest(petID)
    if not Rematch or not Rematch.petInfo then return end
    local i=Rematch.petInfo:Fetch(petID);if not i or not i.hasBreed then return end
    addonTable.RemoveBestBreed(i.speciesID,i.breedID)
    LOG("已移除: speciesID=%d breedID=%d",i.speciesID,i.breedID)
    if Rematch.petsPanel then Rematch.petsPanel:Update() end
end
function RematchHasBest(petID)
    if not Rematch or not Rematch.petInfo then return false end
    local i=Rematch.petInfo:Fetch(petID)
    return i and i.hasBreed and addonTable.IsBestBreed(i.speciesID,i.breedID)
end

-- 未拥有宠物：根据 speciesID 和 breedID 保存
function RematchSetBestNoPet(speciesID,breedID)
    addonTable.SetBestBreed(speciesID,breedID,"custom","")
    LOG("已保存(未拥有): speciesID=%d breedID=%d",speciesID,breedID)
    if Rematch.petsPanel then Rematch.petsPanel:Update() end
end

-- ========== 菜单注入 ==========
local menuRetryCount = 0
local MAX_MENU_RETRY = 5

local function injectRematchMenus()
    if not Rematch or not Rematch.menus or not Rematch.menus.AddToMenu then
        LOG("菜单注入跳过: Rematch.menus 不可用")
        return
    end

    -- 已拥有宠物菜单（切换项）
    local ok1,err1 = pcall(function()
        Rematch.menus:AddToMenu("PetMenu",{
            text=function(_,p) return RematchHasBest(p) and GetLocaleString("REMOVE_BEST_BREED") or GetLocaleString("SET_BEST_BREED") end,
            hidden=function(_,p) return not p or not Rematch.petInfo or not Rematch.petInfo:Fetch(p).hasBreed end,
            func=function(_,p) if RematchHasBest(p) then RematchRemoveBest(p) else RematchSetBest(p) end end
        },"Find Teams")
    end)
    if not ok1 then
        LOG("已拥有菜单注册失败: %s", tostring(err1))
    end

    -- 未拥有宠物菜单（12品种子菜单）
    local ok2,err3
    ok2,err3 = pcall(function()
        local sub={}
        for _,br in ipairs(ALL_BREEDS) do
            sub[#sub+1]={text=br[2],func=function(_,p)
                local info = Rematch.petInfo:Fetch(p)
                if info and info.speciesID then
                    RematchSetBestNoPet(info.speciesID, br[1])
                end
            end}
        end
        sub[#sub+1]={text=CANCEL}
        LOG("子菜单构建完成: %d 项", #sub)
        Rematch.menus:AddToMenu("PetMenu",{
            text=GetLocaleString("SET_BEST_BREED"),subMenu=sub,
            hidden=function(_,p)
                if not p then LOG("hidden:p=nil");return true end
                if not Rematch or not Rematch.petInfo then LOG("hidden:no Rematch");return true end
                local info = Rematch.petInfo:Fetch(p)
                if not info then LOG("hidden:p=%s info=nil",tostring(p));return true end
                LOG("hidden:p=%s hasBreed=%s speciesID=%s",tostring(p),tostring(info.hasBreed),tostring(info.speciesID))
                if info.hasBreed then return true end
                return false
            end,
        },"Find Teams")
    end)
    if ok2 then
        LOG("Rematch 菜单已全部注入成功")
    else
        menuRetryCount = menuRetryCount + 1
        LOG("未拥有菜单注册失败(第%d次): %s", menuRetryCount, tostring(err3))
        if menuRetryCount < MAX_MENU_RETRY then
            C_Timer.After(1, injectRematchMenus)
        else
            LOG("菜单重试已达上限(%d次)，放弃", MAX_MENU_RETRY)
        end
    end
end

function addonTable.InitJournalUI()
    LOG("初始化: ALL_BREEDS=%d项", #ALL_BREEDS)

    local function hookFill()
        if RematchNormalPetListButtonMixin and not RematchNormalPetListButtonMixin._gHooked then
            RematchNormalPetListButtonMixin._gHooked=true
            hooksecurefunc(RematchNormalPetListButtonMixin,"Fill",function(b) label(b) end)
            LOG("已 Hook Normal Mixin Fill")
        end
        if RematchCompactPetListButtonMixin and not RematchCompactPetListButtonMixin._gHooked then
            RematchCompactPetListButtonMixin._gHooked=true
            hooksecurefunc(RematchCompactPetListButtonMixin,"Fill",function(b) label(b) end)
            LOG("已 Hook Compact Mixin Fill")
        end
        -- Rematch 已加载，立即注入菜单
        injectRematchMenus()
    end

    if C_AddOns.IsAddOnLoaded("Rematch") then hookFill()
    else
        local f=CreateFrame("Frame");f:RegisterEvent("ADDON_LOADED")
        f:SetScript("OnEvent",function(_,_,a) if a=="Rematch" then hookFill();f:UnregisterEvent("ADDON_LOADED") end end)
    end
end
