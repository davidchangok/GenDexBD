-- GenDexBD Report.lua
-- 全物种品种评估报告：批量遍历所有物种→运行算法→输出结构化数据
-- 加载顺序：第7个（依赖 BreedRecommend，在 ConfigPanel 之前）
-- 命令: /gbbd report

local addonName, addonTable = ...

local ipairs, pairs, type = ipairs, pairs, type
local mfloor, tsort = math.floor, table.sort
local sformat = string.format

-- ============================================================================
-- 品种代码缓存（BreedData 已加载，直接引用）
-- ============================================================================

local BREEDS = addonTable.BREEDS

-- ============================================================================
-- 家族名称映射
-- ============================================================================

local PET_TYPE_NAMES = {
    [1]  = "人型",     [2]  = "龙类",     [3]  = "飞行",
    [4]  = "亡灵",     [5]  = "小动物",   [6]  = "魔法",
    [7]  = "元素",     [8]  = "野兽",     [9]  = "水栖",
    [10] = "机械",
}

-- ============================================================================
-- 社区共识表（从 BreedRecommend.lua 同步，用于报告对比）
-- ============================================================================

local COMMUNITY_BREED_BONUS = {
    [438]  = "H",    [406]  = "H",    [374]  = "H/P",
    [478]  = "H/S",  [1749] = "S",    [548]  = "P",
    [519]  = "H",    [429]  = "P",    [626]  = "P",
    [493]  = "H/P",  [507]  = "B",    [420]  = "H/P",
    [388]  = "H",    [509]  = "H/S",  [627]  = "H/P",
}

-- ============================================================================
-- 内部函数
-- ============================================================================

local function GetPetTypeName(pt)
    return PET_TYPE_NAMES[pt] or "?"
end

local function TagsToString(tc)
    if not tc then return "" end
    local parts = {}
    for tag, count in pairs(tc) do
        parts[#parts + 1] = tag .. "\195\151" .. tostring(count)
    end
    tsort(parts)
    return table.concat(parts, ", ")
end

-- ============================================================================
-- 诊断日志（聊天框输出，不受弹窗可见性影响）
-- ============================================================================

local function DBG(fmt, ...)
    print(sformat("|cff888888[GenDexDBG-R]|r " .. fmt, ...))
end

-- ============================================================================
-- 主报告生成函数
-- ============================================================================

local reportState = nil
local BATCH_SIZE = 50
local runningFrame = nil

-- 前向声明（WoW Lua 5.1: `function X()` 创建全局, 必须用 `X = function()` 模式）
local ProcessOneSpecies, ProcessBatch, ScheduleNext, FinishReport, FireOnProgress

FireOnProgress = function()
    if not reportState then return end
    local st = reportState
    if not st.onProgress then return end
    local ok, err = pcall(st.onProgress, st.currentIdx, st.total, st._lastName, st.stats)
    if not ok then
        DBG("onProgress 回调异常: %s", tostring(err))
    end
end

ProcessBatch = function()
    if not reportState then
        DBG("ProcessBatch: reportState=nil, 中止")
        return
    end

    local st = reportState
    local batchStart = st.currentIdx + 1
    local batchEnd = batchStart + BATCH_SIZE - 1
    if batchEnd > st.total then batchEnd = st.total end

    for i = batchStart, batchEnd do
        local sid = st.speciesIDs[i]
        local ok = pcall(ProcessOneSpecies, sid, st)
        if not ok then
            st.stats.errors = st.stats.errors + 1
        end
        st.currentIdx = i
    end

    local pct = mfloor(st.currentIdx / st.total * 100)
    DBG("批次: %d-%d/%d (%d%%)  单:%d 多:%d 共识:%d 冲突:%d 零标签:%d",
        batchStart, batchEnd, st.total, pct,
        st.stats.singleBreed, st.stats.multiBreed,
        st.stats.withCommunity, st.stats.communityConflict, st.stats.zeroTags)

    FireOnProgress()

    if st.currentIdx >= st.total then
        DBG("处理完毕，写入数据...")
        FinishReport()
    else
        ScheduleNext()
    end
end

-- 使用 CreateFrame OnUpdate 驱动分批
ScheduleNext = function()
    if not runningFrame then
        runningFrame = CreateFrame("Frame")
    end
    -- 如果帧未显示则显示
    runningFrame:Show()
    runningFrame._fired = false
    runningFrame:SetScript("OnUpdate", function(self)
        if not self._fired then
            self._fired = true
            self:Hide()
            ProcessBatch()
        end
    end)
end

local function _StartReport(onProgress, onComplete)
    if not Rematch or not Rematch.roster or not Rematch.petInfo then
        local msg = "Rematch 未加载"
        DBG("启动失败: %s", msg)
        if onComplete then onComplete(nil, msg) end
        return
    end

    if reportState then
        local msg = "报告已在运行中"
        DBG("启动失败: %s", msg)
        if onComplete then onComplete(nil, msg) end
        return
    end

    DBG("=== 开始收集物种列表 ===")
    local allSpeciesIDs = {}
    for speciesID in Rematch.roster:AllSpecies() do
        allSpeciesIDs[#allSpeciesIDs + 1] = speciesID
    end
    tsort(allSpeciesIDs)

    local total = #allSpeciesIDs
    DBG("物种列表收集完成: %d 个物种 (ID范围: %d ~ %d)", total, allSpeciesIDs[1] or 0, allSpeciesIDs[total] or 0)

    if total == 0 then
        local msg = "未找到任何物种"
        DBG("启动失败: %s", msg)
        if onComplete then onComplete(nil, msg) end
        return
    end

    reportState = {
        speciesIDs = allSpeciesIDs,
        total = total,
        currentIdx = 0,
        _lastName = nil,
        onProgress = onProgress,
        onComplete = onComplete,
        results = {},
        conflicts = {},
        noTagsList = {},
        forceList = {},
        stats = {
            singleBreed = 0, multiBreed = 0, skipped = 0, errors = 0,
            withCommunity = 0, communityMatch = 0, communityConflict = 0,
            zeroTags = 0, forceTags = 0,
        },
    }

    DBG("状态机就绪: %d 物种, 预计 %d 批次, 开始处理...",
        total, math.ceil(total / BATCH_SIZE))

    -- 通过 OnUpdate 帧驱动启动（C_Timer 在斜杠命令中不可用）
    ScheduleNext()
end

ProcessOneSpecies = function(speciesID, st)
    local vals = { C_PetJournal.GetPetInfoBySpeciesID(speciesID) }
    local speciesName = type(vals[1]) == "string" and vals[1] or "?"
    local petType = type(vals[3]) == "number" and vals[3] and vals[3] >= 1 and vals[3] <= 10 and vals[3]
    local canBattle = vals[8]

    if canBattle == false then
        st.stats.skipped = st.stats.skipped + 1
        st._lastName = speciesName
        return
    end
    if not petType then
        st.stats.skipped = st.stats.skipped + 1
        st._lastName = speciesName
        return
    end

    local ok, info = pcall(Rematch.petInfo.Fetch, Rematch.petInfo, speciesID)
    if not ok or not info then
        st.stats.errors = st.stats.errors + 1
        st._lastName = speciesName
        return
    end

    local possibleBreedIDs = info.possibleBreedIDs
    local numBreeds = info.numPossibleBreeds or 0

    local rec = {
        id = speciesID, n = speciesName,
        t = petType, tn = GetPetTypeName(petType),
        nb = numBreeds, sb = false,
    }
    st._lastName = speciesName

    if numBreeds <= 1 then
        st.stats.singleBreed = st.stats.singleBreed + 1
        rec.sb = true
        local onlyBreedID = (possibleBreedIDs and #possibleBreedIDs > 0) and possibleBreedIDs[1]
        if onlyBreedID then
            local br = BREEDS[onlyBreedID]
            local code = addonTable.GetBreedCode and addonTable.GetBreedCode(onlyBreedID) or "?"
            if br then
                rec.bd = { { bc = code, bid = onlyBreedID, h = br[1], p = br[2], s = br[3] } }
            end
        end
    else
        st.stats.multiBreed = st.stats.multiBreed + 1

        local tc = {}
        if addonTable.CollectSkillTags then
            local okTag, result = pcall(addonTable.CollectSkillTags, speciesID)
            if okTag and result then tc = result end
        end

        local hasTags = false
        for _ in pairs(tc) do hasTags = true; break end
        if not hasTags then
            st.stats.zeroTags = st.stats.zeroTags + 1
            rec.zt = true
        end

        local hasForce = (tc["FORCE_PP"] or 0) > 0 or (tc["FORCE_SS"] or 0) > 0 or (tc["FORCE_HH"] or 0) > 0
        if hasForce then
            st.stats.forceTags = st.stats.forceTags + 1
            rec.ft = true
        end

        if addonTable.CalculateBreedScores then
            local okScore, scores = pcall(addonTable.CalculateBreedScores, speciesID, petType, nil, 99)
            if okScore and scores and #scores > 0 then
                local breeds = {}
                for _, sr in ipairs(scores) do
                    local tagsStr = (sr.tagCounts and next(sr.tagCounts))
                        and TagsToString(sr.tagCounts) or ""
                    breeds[#breeds + 1] = {
                        bc = sr.breedCode, bid = sr.breedID, sc = sr.score,
                        tg = tagsStr ~= "" and tagsStr or nil,
                    }
                end
                rec.bd = breeds

                local commStat = COMMUNITY_BREED_BONUS[speciesID]
                if commStat then
                    st.stats.withCommunity = st.stats.withCommunity + 1
                    rec.hc = true
                    rec.cb = commStat

                    local topCode = breeds[1].bc
                    local targetCode
                    if #commStat == 1 then
                        targetCode = commStat == "H" and "H/H"
                            or commStat == "P" and "P/P"
                            or commStat == "S" and "S/S"
                    else
                        targetCode = commStat
                    end
                    rec.cm = (topCode == targetCode)

                    if rec.cm then
                        st.stats.communityMatch = st.stats.communityMatch + 1
                    else
                        st.stats.communityConflict = st.stats.communityConflict + 1
                        rec.cf = true
                        st.conflicts[#st.conflicts + 1] = {
                            id = speciesID, n = speciesName, cb = commStat,
                            algo = topCode, sc = breeds[1].sc,
                            algo2 = breeds[2] and breeds[2].bc or "?",
                            sc2 = breeds[2] and breeds[2].sc or 0,
                        }
                        DBG("冲突! %s(%d): 社区=%s 算法=%s(%d) 亚军=%s(%d)",
                            speciesName, speciesID, commStat, topCode,
                            breeds[1].sc, breeds[2] and breeds[2].bc or "?",
                            breeds[2] and breeds[2].sc or 0)
                    end
                end

                if rec.zt then
                    st.noTagsList[#st.noTagsList + 1] = {
                        id = speciesID, n = speciesName, nb = numBreeds,
                        top = breeds[1].bc, sc = breeds[1].sc,
                    }
                end
                if rec.ft then
                    st.forceList[#st.forceList + 1] = {
                        id = speciesID, n = speciesName,
                        tg = TagsToString(tc),
                        top = breeds[1].bc, sc = breeds[1].sc,
                    }
                end
            else
                st.stats.errors = st.stats.errors + 1
            end
        end
    end

    st.results[#st.results + 1] = rec
end

FinishReport = function()
    if not reportState then
        DBG("FinishReport: reportState 为 nil，跳过")
        return
    end

    local st = reportState
    local s = st.stats

    local summary = {
        total = st.total,
        singleBreed = s.singleBreed,
        multiBreed = s.multiBreed,
        skipped = s.skipped,
        errors = s.errors,
        withCommunity = s.withCommunity,
        communityMatch = s.communityMatch,
        communityConflict = s.communityConflict,
        zeroTags = s.zeroTags,
        forceTags = s.forceTags,
        conflicts = st.conflicts,
        noTagsList = st.noTagsList,
        forceList = st.forceList,
    }

    if not GeneDexDB then GeneDexDB = {} end
    GeneDexDB.SpeciesReport = { r = st.results, sm = summary, v = 1 }
    DBG("写入完成: %d 条记录", #st.results)

    -- 打印聊天框摘要
    print(sformat("|cff00ff00=== [GenDexBD] 报告完成 ===|r"))
    print(sformat("|cff00ffff  总物种:|r %d  |  单品种: %d  |  多品种: %d  |  跳过: %d",
        st.total, s.singleBreed, s.multiBreed, s.skipped))
    print(sformat("  共识: %d  |  匹配: %d  |  冲突: %d  |  零标签: %d  |  异常: %d",
        s.withCommunity, s.communityMatch, s.communityConflict, s.zeroTags, s.errors))

    if s.communityConflict > 0 then
        print("|cffffd700  --- 冲突 (algo != community) ---|r")
        for _, c in ipairs(st.conflicts) do
            print(sformat("  |cffff0000%s(%d)|r: 社区=%s  算法=%s(%d)  #2=%s(%d)",
                c.n, c.id, c.cb, c.algo, c.sc, c.algo2, c.sc2))
        end
    end

    if s.zeroTags > 0 and s.zeroTags <= 30 then
        print("|cffffd700  --- 零标签多品种 ---|r")
        for _, z in ipairs(st.noTagsList) do
            print(sformat("  %s(%d)  top=%s/%d", z.n, z.id, z.top, z.sc))
        end
    end

    print("|cff00ff00  数据已保存|r")
    print("|cff888888  退出游戏 → GenDexBD.lua → 搜索 SpeciesReport 复制该字段值|r")

    -- 回调（UI 弹窗）
    if st.onComplete then
        DBG("触发 onComplete 回调")
        local ok, err = pcall(st.onComplete, summary)
        if not ok then
            DBG("onComplete 回调异常: %s", tostring(err))
        end
    end

    reportState = nil
    DBG("=== 报告结束 ===")
end

-- ============================================================================
-- 公开 API
-- ============================================================================

addonTable.GenerateReport = _StartReport
