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
    [438]  = "H",    -- 王蛇
    [406]  = "H",    -- 甲虫
    [374]  = "H/P",  -- 黑羔羊
    [478]  = "H/S",  -- 森林蛾
    [1749] = "S",    -- Death Adder
    [548]  = "P",    -- 蛮锤狮鹫
}

-- ============================================================================
-- 简易帧定时器（避免 C_Timer 斜杠命令安全限制）
-- ============================================================================

local timerFrame = CreateFrame("Frame")
timerFrame:Hide()
timerFrame._elapsed = 0
timerFrame._delay = 0
timerFrame._callback = nil
timerFrame:SetScript("OnUpdate", function(self, elapsed)
    self._elapsed = self._elapsed + elapsed
    if self._elapsed >= self._delay then
        self._elapsed = 0
        self:Hide()
        if self._callback then
            local cb = self._callback
            self._callback = nil
            cb()
        end
    end
end)

local function DelayCall(callback, delay)
    timerFrame._callback = callback
    timerFrame._delay = delay or 0.05
    timerFrame._elapsed = 0
    timerFrame:Show()
end

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

local function DummyLocale(key)
    return addonTable.GetLocaleString and addonTable.GetLocaleString(key) or key
end

-- ============================================================================
-- 主报告生成函数
-- ============================================================================

local reportState = nil  -- 报告状态机
local BATCH_SIZE = 50

local function ProcessBatch()
    if not reportState then return end

    local st = reportState
    local batchEnd = st.currentIdx + BATCH_SIZE
    if batchEnd > st.total then batchEnd = st.total end

    for i = st.currentIdx + 1, batchEnd do
        local sid = st.speciesIDs[i]
        local ok = pcall(ProcessOneSpecies, sid, st)
        if not ok then
            st.stats.errors = st.stats.errors + 1
        end
        st.currentIdx = i
    end

    local pct = mfloor(st.currentIdx / st.total * 100)
    print(sformat("|cff888888[GenDexBD]|r %s",
        sformat(DummyLocale("REPORT_PROGRESS") or "Progress: %d/%d (%d%%)",
            st.currentIdx, st.total, pct)))

    if st.currentIdx >= st.total then
        DelayCall(FinishReport, 0.1)
    else
        DelayCall(ProcessBatch, 0.01)
    end
end

local function StartReport()
    if not Rematch or not Rematch.roster or not Rematch.petInfo then
        print("|cffff0000[GenDexBD]|r " .. (DummyLocale("REPORT_NO_REMATCH") or "Rematch not available"))
        return
    end

    if reportState then
        print("|cffffd700[GenDexBD]|r " .. (DummyLocale("REPORT_ALREADY_RUNNING") or "Report already running..."))
        return
    end

    -- 收集所有物种ID
    local allSpeciesIDs = {}
    for speciesID in Rematch.roster:AllSpecies() do
        allSpeciesIDs[#allSpeciesIDs + 1] = speciesID
    end
    tsort(allSpeciesIDs)

    local total = #allSpeciesIDs
    if total == 0 then
        print("|cffff0000[GenDexBD]|r " .. (DummyLocale("REPORT_NO_SPECIES") or "No species found"))
        return
    end

    reportState = {
        speciesIDs = allSpeciesIDs,
        total = total,
        currentIdx = 0,
        results = {},
        conflicts = {},
        noTagsList = {},
        forceList = {},
        stats = {
            singleBreed = 0,
            multiBreed = 0,
            skipped = 0,
            errors = 0,
            withCommunity = 0,
            communityMatch = 0,
            communityConflict = 0,
            zeroTags = 0,
            forceTags = 0,
        },
    }

    print(sformat("|cff00ff00[GenDexBD]|r %s", sformat(
        DummyLocale("REPORT_START") or "Report generation started: %d species", total)))
    print(sformat("|cff888888[GenDexBD]|r %s",
        sformat(DummyLocale("REPORT_PROGRESS") or "Progress: %d/%d (%d%%)", 0, total, 0)))

    -- 异步启动（帧定时器，绕过斜杠命令 C_Timer 限制）
    DelayCall(ProcessBatch, 0.1)
end

local function ProcessOneSpecies(speciesID, st)
    -- 检查是否可对战
    local vals = { C_PetJournal.GetPetInfoBySpeciesID(speciesID) }
    local speciesName = type(vals[1]) == "string" and vals[1] or "?"
    local petType = type(vals[3]) == "number" and vals[3] and vals[3] >= 1 and vals[3] <= 10 and vals[3]
    local canBattle = vals[8]

    if canBattle == false then
        st.stats.skipped = st.stats.skipped + 1
        return
    end
    if not petType then
        st.stats.skipped = st.stats.skipped + 1
        return
    end

    -- 获取品种信息
    local ok, info = pcall(Rematch.petInfo.Fetch, Rematch.petInfo, speciesID)
    if not ok or not info then
        st.stats.errors = st.stats.errors + 1
        return
    end

    local possibleBreedIDs = info.possibleBreedIDs
    local numBreeds = info.numPossibleBreeds or 0

    local rec = {
        id = speciesID, n = speciesName,
        t = petType, tn = GetPetTypeName(petType),
        nb = numBreeds, sb = false,
    }

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

local function FinishReport()
    if not reportState then return end

    local st = reportState

    local summary = {
        total = st.total,
        singleBreed = st.stats.singleBreed,
        multiBreed = st.stats.multiBreed,
        skipped = st.stats.skipped,
        errors = st.stats.errors,
        withCommunity = st.stats.withCommunity,
        communityMatch = st.stats.communityMatch,
        communityConflict = st.stats.communityConflict,
        zeroTags = st.stats.zeroTags,
        forceTags = st.stats.forceTags,
        conflicts = st.conflicts,
        noTagsList = st.noTagsList,
        forceList = st.forceList,
    }

    if not GeneDexDB then GeneDexDB = {} end
    GeneDexDB.SpeciesReport = { r = st.results, sm = summary, v = 1 }

    local s = st.stats
    print("|cff00ff00=== [GenDexBD] " .. (DummyLocale("REPORT_DONE") or "Report Complete") .. " ===|r")
    print(sformat("|cff00ffff  %s:|r %d",
        DummyLocale("REPORT_TOTAL_SPECIES") or "Total species", st.total))
    print(sformat("  %s: %d  |  %s: %d  |  %s: %d",
        DummyLocale("REPORT_SINGLE_BREED") or "Single", s.singleBreed,
        DummyLocale("REPORT_MULTI_BREED") or "Multi", s.multiBreed,
        DummyLocale("REPORT_SKIPPED") or "Skipped", s.skipped))
    print(sformat("  %s: %d  |  %s: %d  |  %s: %d",
        DummyLocale("REPORT_WITH_COMMUNITY") or "HasCommunity", s.withCommunity,
        DummyLocale("REPORT_COMMUNITY_MATCH") or "Match", s.communityMatch,
        DummyLocale("REPORT_COMMUNITY_CONFLICT") or "Conflict", s.communityConflict))
    print(sformat("  %s: %d  |  %s: %d  |  %s: %d",
        DummyLocale("REPORT_ZERO_TAGS") or "ZeroTags", s.zeroTags,
        DummyLocale("REPORT_FORCE_TAGS") or "FORCE", s.forceTags,
        DummyLocale("REPORT_ERRORS") or "Errors", s.errors))

    if s.communityConflict > 0 then
        print("|cffffd700  --- " .. (DummyLocale("REPORT_CONFLICTS_HEADER") or "CONFLICTS") .. " ---|r")
        for _, c in ipairs(st.conflicts) do
            print(sformat("  |cffff0000%s(%d)|r: community=%s  algo=%s(%d)  #2=%s(%d)",
                c.n, c.id, c.cb, c.algo, c.sc, c.algo2, c.sc2))
        end
    end

    if s.zeroTags > 0 and s.zeroTags <= 30 then
        print("|cffffd700  --- " .. (DummyLocale("REPORT_ZERO_TAGS_HEADER") or "ZERO-TAG") .. " ---|r")
        for _, z in ipairs(st.noTagsList) do
            print(sformat("  %s(%d)  top=%s/%d  breeds=%d", z.n, z.id, z.top, z.sc, z.nb))
        end
    end

    print("|cff00ff00  " .. (DummyLocale("REPORT_SAVED") or "Saved to GeneDexDB.SpeciesReport") .. "|r")
    print("|cff888888  " .. (DummyLocale("REPORT_INSTRUCTIONS") or "Exit→WTF/.../GenDexBD.lua→SpeciesReport") .. "|r")

    reportState = nil
end

-- ============================================================================
-- 公开 API
-- ============================================================================

addonTable.GenerateReport = StartReport
