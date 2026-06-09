-- AutoPet.lua
-- Automatically summons a companion pet on login, reload, dismount, rez, and zone.
-- Type /autopet to open settings.

-- =========================================
--   C_Timer_After polyfill for 3.3.5
-- =========================================
if not C_Timer_After then
    C_Timer_After = function(delay, func)
        local t = CreateFrame("Frame")
        local elapsed = 0
        t:SetScript("OnUpdate", function(self, diff)
            elapsed = elapsed + diff
            if elapsed >= delay then
                self:SetScript("OnUpdate", nil)
                func()
            end
        end)
    end
end

-- =========================================
--   SAVED VARIABLES & DEFAULTS
-- =========================================
AutoPetDB = AutoPetDB or {}

local function DB(key, default)
    if AutoPetDB[key] == nil then AutoPetDB[key] = default end
    return AutoPetDB[key]
end

-- Defaults on first load
DB("petName",    "Orange Tabby Cat")
DB("randomMode", false)
DB("enabled",    true)

-- =========================================
--   CORE SUMMON LOGIC
-- =========================================

local function GetAllPets()
    local pets = {}
    local numPets = GetNumCompanions("CRITTER")
    for i = 1, numPets do
        local _, name, _, _, active = GetCompanionInfo("CRITTER", i)
        table.insert(pets, { index = i, name = name, active = active })
    end
    return pets
end

local function HasActivePet(pets)
    for _, p in ipairs(pets) do
        if p.active then return true end
    end
    return false
end

local function SummonPet()
    if not AutoPetDB.enabled then return end
    if InCombatLockdown() then return end

    local pets = GetAllPets()
    if #pets == 0 then return end
    if HasActivePet(pets) then return end

    if AutoPetDB.randomMode then
        -- Pick a random pet from the collection
        local pick = pets[math.random(#pets)]
        CallCompanion("CRITTER", pick.index)
    else
        -- Find the named pet
        local petName = AutoPetDB.petName
        for _, p in ipairs(pets) do
            if p.name == petName then
                CallCompanion("CRITTER", p.index)
                return
            end
        end
        print("|cffff9900AutoPet:|r Could not find pet: |cffffffff" .. petName .. "|r")
        print("|cffff9900AutoPet:|r Use |cffffffff/autopet|r to change the pet name.")
    end
end

-- =========================================
--   EVENT HANDLING
-- =========================================

local wasInInstance = false
local wasMounted    = false
local pollElapsed   = 0
local POLL_INTERVAL = 0.5

local mainFrame = CreateFrame("Frame")
mainFrame:RegisterEvent("PLAYER_LOGIN")
mainFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
mainFrame:RegisterEvent("PLAYER_ALIVE")   -- after rezzing

mainFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        C_Timer_After(3, SummonPet)

    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Detect leaving an instance (dungeon/raid -> open world)
        local inInstance, instanceType = IsInInstance()
        local justLeftInstance = wasInInstance and not inInstance
        wasInInstance = inInstance

        if justLeftInstance then
            -- Came out of a dungeon/raid, resummon after a short delay
            C_Timer_After(3, SummonPet)
        else
            -- Normal login / reload
            C_Timer_After(3, SummonPet)
        end

    elseif event == "PLAYER_ALIVE" then
        -- Rezzing: only summon if we're not still in a graveyard / ghost state
        C_Timer_After(2, function()
            if not UnitIsGhost("player") then
                SummonPet()
            end
        end)
    end
end)

-- Mount polling
mainFrame:SetScript("OnUpdate", function(self, diff)
    pollElapsed = pollElapsed + diff
    if pollElapsed < POLL_INTERVAL then return end
    pollElapsed = 0

    local isMounted = IsMounted()
    if wasMounted and not isMounted then
        C_Timer_After(0.5, SummonPet)
    end
    wasMounted = isMounted
end)

-- =========================================
--   SETTINGS UI
-- =========================================

local WINDOW_W  = 340
local WINDOW_H  = 310
local LIST_ROWS = 7
local ROW_H     = 20

-- Main window
local ui = CreateFrame("Frame", "AutoPetFrame", UIParent)
ui:SetSize(WINDOW_W, WINDOW_H)
ui:SetPoint("CENTER")
ui:SetMovable(true)
ui:EnableMouse(true)
ui:RegisterForDrag("LeftButton")
ui:SetScript("OnDragStart", ui.StartMoving)
ui:SetScript("OnDragStop", ui.StopMovingOrSizing)
ui:SetFrameStrata("DIALOG")
ui:Hide()

ui:SetBackdrop({
    bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
})

-- Title
local titleTex = ui:CreateTexture(nil, "ARTWORK")
titleTex:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
titleTex:SetSize(256, 32)
titleTex:SetPoint("TOP", ui, "TOP", 0, 4)

local titleText = ui:CreateFontString(nil, "OVERLAY", "GameFontNormal")
titleText:SetPoint("TOP", ui, "TOP", 0, -8)
titleText:SetText("AutoPet Settings")

-- ---- Enable checkbox ----
local enableChk = CreateFrame("CheckButton", "AutoPetEnableChk", ui, "UICheckButtonTemplate")
enableChk:SetSize(24, 24)
enableChk:SetPoint("TOPLEFT", ui, "TOPLEFT", 16, -36)
enableChk.text = ui:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
enableChk.text:SetPoint("LEFT", enableChk, "RIGHT", 2, 0)
enableChk.text:SetText("Enable AutoPet")
enableChk:SetScript("OnClick", function(self)
    AutoPetDB.enabled = self:GetChecked() and true or false
end)

-- ---- Random mode checkbox ----
local randomChk = CreateFrame("CheckButton", "AutoPetRandomChk", ui, "UICheckButtonTemplate")
randomChk:SetSize(24, 24)
randomChk:SetPoint("TOPLEFT", enableChk, "BOTTOMLEFT", 0, -2)
randomChk.text = ui:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
randomChk.text:SetPoint("LEFT", randomChk, "RIGHT", 2, 0)
randomChk.text:SetText("Random pet mode")

-- ---- Pet list label ----
local listLabel = ui:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
listLabel:SetPoint("TOPLEFT", randomChk, "BOTTOMLEFT", 2, -10)
listLabel:SetText("Choose a pet (click to select):")

-- ---- Scrollable pet list ----
local listFrame = CreateFrame("Frame", nil, ui)
listFrame:SetSize(WINDOW_W - 40, LIST_ROWS * ROW_H)
listFrame:SetPoint("TOPLEFT", listLabel, "BOTTOMLEFT", 0, -4)
listFrame:SetBackdrop({
    bgFile  = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
})
listFrame:SetBackdropColor(0, 0, 0, 0.6)

-- Row buttons inside the list
local rows = {}
for i = 1, LIST_ROWS do
    local row = CreateFrame("Button", nil, listFrame)
    row:SetSize(WINDOW_W - 46, ROW_H)
    row:SetPoint("TOPLEFT", listFrame, "TOPLEFT", 3, -3 - (i - 1) * ROW_H)

    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    hl:SetBlendMode("ADD")

    local sel = row:CreateTexture(nil, "BACKGROUND")
    sel:SetAllPoints()
    sel:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    sel:SetBlendMode("ADD")
    sel:Hide()
    row.selTex = sel

    local txt = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    txt:SetPoint("LEFT", row, "LEFT", 4, 0)
    txt:SetJustifyH("LEFT")
    row.txt = txt

    row.petName = nil
    rows[i] = row
end

-- Scroll state
local scrollOffset = 0
local petList      = {}    -- full list of pet names
local selectedName = nil

local function RefreshList()
    for i, row in ipairs(rows) do
        local idx = i + scrollOffset
        local pet = petList[idx]
        if pet then
            row.txt:SetText(pet)
            row.petName = pet
            row:Show()
            -- Highlight selected row
            if pet == selectedName then
                row.selTex:Show()
            else
                row.selTex:Hide()
            end
        else
            row.txt:SetText("")
            row.petName = nil
            row:Hide()
            row.selTex:Hide()
        end
    end
end

for _, row in ipairs(rows) do
    row:SetScript("OnClick", function(self)
        if self.petName then
            selectedName = self.petName
            AutoPetDB.petName = self.petName
            RefreshList()
        end
    end)
end

-- Scroll buttons
local scrollUp = CreateFrame("Button", nil, ui, "UIPanelScrollUpButtonTemplate")
scrollUp:SetPoint("TOPRIGHT", listFrame, "TOPRIGHT", 18, 0)
scrollUp:SetScript("OnClick", function()
    if scrollOffset > 0 then
        scrollOffset = scrollOffset - 1
        RefreshList()
    end
end)

local scrollDown = CreateFrame("Button", nil, ui, "UIPanelScrollDownButtonTemplate")
scrollDown:SetPoint("BOTTOMRIGHT", listFrame, "BOTTOMRIGHT", 18, 0)
scrollDown:SetScript("OnClick", function()
    if scrollOffset + LIST_ROWS < #petList then
        scrollOffset = scrollOffset + 1
        RefreshList()
    end
end)

-- Mouse wheel scrolling
listFrame:EnableMouseWheel(true)
listFrame:SetScript("OnMouseWheel", function(self, delta)
    if delta > 0 and scrollOffset > 0 then
        scrollOffset = scrollOffset - 1
        RefreshList()
    elseif delta < 0 and scrollOffset + LIST_ROWS < #petList then
        scrollOffset = scrollOffset + 1
        RefreshList()
    end
end)

-- Grey out the list when random mode is on
local function UpdateRandomMode(isRandom)
    AutoPetDB.randomMode = isRandom
    if isRandom then
        listLabel:SetTextColor(0.5, 0.5, 0.5)
        listFrame:SetBackdropColor(0, 0, 0, 0.3)
        for _, row in ipairs(rows) do
            row.txt:SetTextColor(0.5, 0.5, 0.5)
            row:Disable()
        end
    else
        listLabel:SetTextColor(1, 0.82, 0)
        listFrame:SetBackdropColor(0, 0, 0, 0.6)
        for _, row in ipairs(rows) do
            row.txt:SetTextColor(1, 1, 1)
            row:Enable()
        end
    end
end

randomChk:SetScript("OnClick", function(self)
    UpdateRandomMode(self:GetChecked() and true or false)
end)

-- ---- Close button ----
local closeBtn = CreateFrame("Button", nil, ui, "GameMenuButtonTemplate")
closeBtn:SetSize(80, 26)
closeBtn:SetPoint("BOTTOM", ui, "BOTTOM", 0, 14)
closeBtn:SetText("Close")
closeBtn:SetScript("OnClick", function() ui:Hide() end)

-- ---- Populate UI when shown ----
ui:SetScript("OnShow", function()
    -- Sync checkboxes
    enableChk:SetChecked(AutoPetDB.enabled)
    randomChk:SetChecked(AutoPetDB.randomMode)

    -- Build pet name list sorted alphabetically
    petList = {}
    local numPets = GetNumCompanions("CRITTER")
    for i = 1, numPets do
        local _, name = GetCompanionInfo("CRITTER", i)
        table.insert(petList, name)
    end
    table.sort(petList)

    selectedName  = AutoPetDB.petName
    scrollOffset  = 0

    -- Scroll to the selected pet
    for i, name in ipairs(petList) do
        if name == selectedName then
            scrollOffset = math.max(0, i - math.floor(LIST_ROWS / 2))
            break
        end
    end

    RefreshList()
    UpdateRandomMode(AutoPetDB.randomMode)
end)

-- =========================================
--   SLASH COMMAND  /autopet
-- =========================================

SLASH_AUTOPET1 = "/autopet"
SlashCmdList["AUTOPET"] = function()
    if ui:IsShown() then
        ui:Hide()
    else
        ui:Show()
    end
end
