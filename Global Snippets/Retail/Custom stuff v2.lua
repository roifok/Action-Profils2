---------------------------------------------------
-------------- CUSTOM STUFF FUNCTIONS -------------
---------------------------------------------------
local TMW                                   = TMW
local _G, type, error, time     			= _G, type, error, time
local A                         			= _G.Action
local TeamCache								= A.TeamCache
local EnemyTeam								= A.EnemyTeam
local FriendlyTeam							= A.FriendlyTeam
local LoC									= A.LossOfControl
local Player								= A.Player 
local MultiUnits							= A.MultiUnits
local UnitCooldown							= A.UnitCooldown
local ActiveUnitPlates						= MultiUnits:GetActiveUnitPlates()
local toStr                     			= A.toStr
local toNum                     			= A.toNum
local LibToast                              = LibStub("LibToast-1.0")
local next, pairs, type, print              = next, pairs, type, print
local IsActionInRange, GetActionInfo, PetHasActionBar, GetPetActionsUsable, GetSpellInfo = IsActionInRange, GetActionInfo, PetHasActionBar, GetPetActionsUsable, GetSpellInfo
local UnitLevel, UnitPower, UnitPowerMax, UnitStagger, UnitAttackSpeed, UnitRangedDamage, UnitDamage, UnitAura = UnitLevel, UnitPower, UnitPowerMax, UnitStagger, UnitAttackSpeed, UnitRangedDamage, UnitDamage, UnitAura
local UnitIsPlayer, UnitExists, UnitGUID    = UnitIsPlayer, UnitExists, UnitGUID
--local Pet                                 = LibStub("PetLibrary") Don't work. Too fast loading snippets ?
local Unit                                  = A.Unit 
local huge                                  = math.huge
local UnitBuff                              = _G.UnitBuff
local EventFrame                            = CreateFrame("Frame", "Taste_EventFrame", UIParent)
local UnitIsUnit                            = UnitIsUnit
local StdUi                                 = A.StdUi -- Custom StdUI with Action shared settings
-- Lua methods
local error                                 = error
local setmetatable 						    = setmetatable
local stringformat 						    = string.format
local stringfind                            = string.find
local stringsub                             = string.sub
local tableinsert 						    = table.insert
local tableremove							= table.remove 
-- Local Tables
local Events = {} -- All Events
local CombatEvents = {} -- Combat Log Unfiltered
local SelfCombatEvents = {} -- Combat Log Unfiltered with SourceGUID == PlayerGUID filter
local PetCombatEvents = {} -- Combat Log Unfiltered with SourceGUID == PetGUID filter
local PrefixCombatEvents = {}
local SuffixCombatEvents = {}
local CombatLogPrefixes = {
  "ENVIRONMENTAL",
  "RANGE",
  "SPELL_BUILDING",
  "SPELL_PERIODIC",
  "SPELL",
  "SWING"
}
local CombatLogPrefixesCount = #CombatLogPrefixes
local restoreDB = {}
local overrideDB = {}
-- Global TasteRotation Table
A.TasteRotation = {}
local TR                                    = A.TasteRotation
-- Global Tables
TR.Enum = {}
TR.Lists = {}
TR.storedTables = {}


------------------------------------
-- UI Toggles
------------------------------------
-- AoE Status on Main Icon
function A.AoEToggleMode()
    A.UseAoE = A.GetToggle(2, "AoE")    
    if A.UseAoE == false then 
        A.UseAoE = true
    else
        A.UseAoE = false
    end
    A.SetToggle({2, "AoE"})        
    A.Print(A.UseAoE and "Mode AoE: On" or not A.UseAoE and "Mode AoE: Off")
    TMW:Fire("TMW_ACTION_AOE_MODE_CHANGED")
end 

------------------------------------
--- Area Time To Die
------------------------------------
--@return current average AoE time to die 
function Player:AreaTTD(range)
    local ttdtotal = 0
    local totalunits = 0
	local r = range
	
	for _, unitID in pairs(ActiveUnitPlates) do 
	    if Unit(unitID):GetRange() <= r then 
            local ttd = Unit(unitID):TimeToDie()
            totalunits = totalunits + 1
            ttdtotal = ttd + ttdtotal
		end
    end
	
    if totalunits == 0 then
        return 0
    end

    return ttdtotal / totalunits
end

-----------------------------------
-- Trinkets
-----------------------------------
-- List all BlackListed Trinkets we dont want to use on cooldown but with some specific APLs.
local BlackListedTrinkets = {

    [1] = 168905, -- Shiver Venom Relic
	[2] = 169314, -- Azsharas Font of Power
    [3] = 169311, -- AshvanesRazorCoral
	[4] = 174044, -- Humming Black Dragonscale
	[5] = 158367, -- MerekthasFang

}

function TR:TrinketIsAllowed()
    local Trinket1IsAllowed = true
	local Trinket2IsAllowed = true
     
   	    for i = 1, #BlackListedTrinkets do
            if A.Trinket1.ID == BlackListedTrinkets[i] then
                Trinket1IsAllowed = false				
			end
            if A.Trinket2.ID == BlackListedTrinkets[i] then
                Trinket2IsAllowed = false					
            end
        end
	return Trinket1IsAllowed, Trinket2IsAllowed
end
    
-- Trinkets checker
function TR:TrinketON()
  return ( (A.GetToggle(1, "Trinkets")[1]) or (A.GetToggle(1, "Trinkets")[2]) )
end

------------------------------------
--- RegisterDamage simc reference
------------------------------------
-- Register the spell damage formula.
function A:RegisterDamage(Function)
    self.DamageFormula = Function
end

-- Get the spell damage formula if it exists.
function A:Damage()
    return self.DamageFormula and self.DamageFormula() or 0
end

-- attack_power
function A.Player:AttackPower()
    return UnitAttackPower("player")
end

-- AttackPowerDamageMod
function A.Player:AttackPowerDamageMod(offHand)
    local useOH = offHand or false
    local wdpsCoeff = 6
    local ap = Player:AttackPower()
    local minDamage, maxDamage, minOffHandDamage, maxOffHandDamage, physicalBonusPos, physicalBonusNeg, percent = UnitDamage(self.UnitID)
    local speed, offhandSpeed = UnitAttackSpeed(self.UnitID)
    if useOH and offhandSpeed then
        local wSpeed = offhandSpeed * (1 + Player:HastePct() / 100)
        local wdps = (minOffHandDamage + maxOffHandDamage) / wSpeed / percent - ap / wdpsCoeff
            return (ap + wdps * wdpsCoeff) * 0.5
    else
        local wSpeed = speed * (1 + Player:HastePct() / 100)
        local wdps = (minDamage + maxDamage) / 2 / wSpeed / percent - ap / wdpsCoeff
        return ap + wdps * wdpsCoeff
    end
end

------------------------------------
--- HasHeroism simc reference
------------------------------------
local HeroismBuff = { 
    [2825] =  true, -- Bloodlust Horde 
    [32182] =  true, -- Heroism Ally  		
    [90355] =  true, -- Ancient Hysteria
    [160452] =  true, -- Netherwinds
    [80353] =  true, -- Time Warp
    [178207] =  true, -- Drums of Fury
    [35475] =  true, -- Drums of War
    [230935] =  true, -- Drums of Montain
    [256740] =  true, -- Drums of Maelstrom
    --[974] =  true, -- Test Earth Shield
}

function Unit:HasHeroism()
    local unitID = self.UnitID
    -- @return boolean 
    local spellId 
    for i = 1, huge do 
        name,_,_,_,_,_,_,_,_,spellId = UnitBuff(unitID, i, "HELPFUL")
        if not spellId  then 
            break 
        elseif HeroismBuff[spellId] then 
            return true 
        end 
    end 
	return false
end 

------------------------------------
--- Corruption API patch 8.3
------------------------------------
-- Return current Corruption amount (Total - Resistance)
function Player:GetCurrentCorruption()
    local TotalCorruption = GetCorruption()
    local CorruptionResistance = GetCorruptionResistance()
    return TotalCorruption - CorruptionResistance
end

------------------------------------
--- HasDeBuffsDown simc reference
------------------------------------
function Unit:HasDeBuffsDown(spell, byID)
	local unitID = self.UnitID
	
    return self(unitID):HasDeBuffs(spell, byID) == 0
end

------------------------------------
--- HasBuffsDown simc reference
------------------------------------
function Unit:HasBuffsDown(spell, byID)
    local unitID = self.UnitID
	
    return self(unitID):HasBuffs(spell, byID) == 0
end

------------------------------------
--- HasDeBuffsRefreshable simc reference
------------------------------------
function Unit:HasDeBuffsRefreshable(spell, byID)
    local unitID = self.UnitID
	
    return self(unitID):HasDeBuffs(spell, byID) < 5
end

-------------------------------------------------------------------------------
-- Multiunits
-------------------------------------------------------------------------------
function A.MultiUnits.GetByRangeDoTsToRefresh(self, range, count, deBuffs, refreshTime, upTTD)
	-- @return number
	-- @usage A.MultiUnits:GetByRangeDoTsToRefresh(@number, @number, @table or @number, @number, @number)
	-- deBuffs is required, refreshTime too, rest options are optimal
	local total = 0
	local nameplates = self:GetActiveUnitPlates()
	
	if nameplates then 
		for unitID in pairs(nameplates) do 
			if Unit(unitID):CombatTime() > 0 and (not range or Unit(unitID):CanInterract(range)) and (not upTTD or Unit(unitID):TimeToDie() >= upTTD) and Unit(unitID):HasDeBuffs(deBuffs, true) <= refreshTime then 
				total = total + 1
			end 
			
			if count and total >= count then 
				break 
			end 
		end 
	end 
	
	return total 
end 
A.MultiUnits.GetByRangeDoTsToRefresh = A.MakeFunctionCachedDynamic(A.MultiUnits.GetByRangeDoTsToRefresh)

-------------------------------------------------------------------------------
-- Event register
-------------------------------------------------------------------------------
-- Register a handler for an event.
-- @param Handler The handler function.
-- @param Events The events name.
function A:RegisterForEvent(Handler, ...)
    local EventsTable = { ... }
    for i = 1, #EventsTable do
        local Event = EventsTable[i]
        if not Events[Event] then
            Events[Event] = { Handler }
            EventFrame:RegisterEvent(Event)
        else
            tableinsert(Events[Event], Handler)
        end
    end
end

-- Register a handler for a combat event.
-- @param Handler The handler function.
-- @param Events The events name.
function A:RegisterForCombatEvent(Handler, ...)
    local EventsTable = { ... }
    for i = 1, #EventsTable do
        local Event = EventsTable[i]
        if not CombatEvents[Event] then
            CombatEvents[Event] = { Handler }
        else
            tableinsert(CombatEvents[Event], Handler)
        end
    end
end

-- Register a handler for a self combat event.
-- @param Handler The handler function.
-- @param Events The events name.
function A:RegisterForSelfCombatEvent(Handler, ...)
    local EventsTable = { ... }
    for i = 1, #EventsTable do
        local Event = EventsTable[i]
        if not SelfCombatEvents[Event] then
            SelfCombatEvents[Event] = { Handler }
        else
            tableinsert(SelfCombatEvents[Event], Handler)
        end
    end
end

-- Register a handler for a pet combat event.
-- @param Handler The handler function.
-- @param Events The events name.
function A:RegisterForPetCombatEvent(Handler, ...)
    local EventsTable = { ... }
    for i = 1, #EventsTable do
        local Event = EventsTable[i]
        if not PetCombatEvents[Event] then
            PetCombatEvents[Event] = { Handler }
        else
            tableinsert(PetCombatEvents[Event], Handler)
        end
    end
end

-- OnEvent Frame Listener
EventFrame:SetScript("OnEvent",
    function(self, Event, ...)
        for _, Handler in pairs(Events[Event]) do
            Handler(Event, ...)
        end
end)

-- Combat Log Event Unfiltered Listener
local function ListenerCombatLogEventUnfiltered(Event, TimeStamp, SubEvent, ...)
    if CombatEvents[SubEvent] then
        -- Unfiltered Combat Log
        for _, Handler in pairs(CombatEvents[SubEvent]) do
            Handler(TimeStamp, SubEvent, ...)
        end
    end
    if SelfCombatEvents[SubEvent] then
        -- Unfiltered Combat Log with SourceGUID == PlayerGUID filter
        if select(2, ...) == UnitGUID("player") then
            for _, Handler in pairs(SelfCombatEvents[SubEvent]) do
                Handler(TimeStamp, SubEvent, ...)
            end
        end
    end
    if PetCombatEvents[SubEvent] then
        -- Unfiltered Combat Log with SourceGUID == PetGUID filter
        if select(2, ...) == UnitGUID("pet") then
            for _, Handler in pairs(SelfCombatEvents[SubEvent]) do
                Handler(TimeStamp, SubEvent, ...)
            end
        end
    end
    for i = 1, CombatLogPrefixesCount do
        -- TODO : Optimize the str find
        if SubEvent then
            local Start, End = stringfind(SubEvent, CombatLogPrefixes[i])
                if Start and End then
                    -- TODO: Optimize the double str sub
                    local Prefix, Suffix = stringsub(SubEvent, Start, End), stringsub(SubEvent, End + 1)
                    if PrefixCombatEvents[Prefix] then
                    -- Unfiltered Combat Log with Prefix only
                    for _, Handler in pairs(PrefixCombatEvents[Prefix]) do
                        Handler(TimeStamp, SubEvent, ...)
                    end
                end
                if SuffixCombatEvents[Suffix] then
                    -- Unfiltered Combat Log with Suffix only
                    for _, Handler in pairs(SuffixCombatEvents[Suffix]) do
                        Handler(TimeStamp, SubEvent, ...)
                    end
                end
            end
        end
    end
end

A:RegisterForEvent(function(Event)
  ListenerCombatLogEventUnfiltered(Event, CombatLogGetCurrentEventInfo())
end, "COMBAT_LOG_EVENT_UNFILTERED")

local function removeLastChar(text)
	return text:sub(1, -2)
end

--[[*
  * @mixin HL.OffsetRemains
  * @desc Apply an offset to an expiration time.
  *
  * @param {number} ExpirationTime - The expiration time to apply the offset on.
  * @param {string|number} Offset - The offset to apply, can be a string for a known method or directly the offset value in seconds.
  *
  * @returns {number}
  *]]
function A.OffsetRemains(ExpirationTime, Offset)
    if type(Offset) == "number" then
        ExpirationTime = ExpirationTime - Offset
    elseif type(Offset) == "string" then
        local CastRemains = Player:CastRemains()
        local GCDRemains = Player:GCDRemains()
        if Offset == "GCDRemains" then
            ExpirationTime = ExpirationTime - GCDRemains
        elseif Offset == "CastRemains" then
            ExpirationTime = ExpirationTime - CastRemains
        elseif Offset == "Auto" then
            ExpirationTime = ExpirationTime - math.max(GCDRemains, CastRemains)
        end
    else
        error("Invalid Offset.")
    end
    return ExpirationTime
end

--------------------------------------
--------- Action Status Frame --------
--------------------------------------
--- Draw a dynamic list based on current Blocked spells
--- Future will add Queued frame and maybe other options depending on users feedbacks

TR.BlockedListAssoc				= {}
TR.BlockedListArray 			= {}
TR.BlockedListIcon   			= {}

local pairs, next, type, wipe	= pairs, next, type, wipe
local hooksecurefunc 			= hooksecurefunc
local isHooked					-- nil 

local L 						= {
	enUS 						= "No blocked actions :)",
	frFR 						= "Aucune action bloquée :)",
	ruRU						= "Нет заблокированных действий :)",
}

local function GetActionSpellStatus(this)
  if A.IsInitialized then 
    if not this then 
        wipe(TR.BlockedListAssoc)
        
        if Action[A.PlayerSpec] then 
            for k, v in pairs(Action[A.PlayerSpec]) do 
                if type(v) == "table" and v.Type and v:IsBlocked() then     
                    TR.BlockedListAssoc[k] = v
                end 
            end 
        end 
    else 
        local k = this:GetKeyName()
        if k then 
            if this:IsBlocked() then 
                TR.BlockedListAssoc[k] = this 
            else 
                TR.BlockedListAssoc[k] = nil 
            end 
        end 
    end 
  end 

    wipe(TR.BlockedListArray)
    wipe(TR.BlockedListIcon)
    for k, v in pairs(TR.BlockedListAssoc) do 
        TR.BlockedListArray[#TR.BlockedListArray + 1] = k --.. " " .. (v.Desc or "") .. " " .. (v.Color or "")
        TR.BlockedListIcon[#TR.BlockedListIcon + 1] = v:Icon()
    end 
    
    TMW:Fire("TMW_ACTION_STATUS_BLOCKED_CHANGED")
end

local function OnCallback()
	GetActionSpellStatus()
end 

-- Finally, callbackEvent on init
TMW:RegisterCallback("TMW_ACTION_IS_INITIALIZED", function(callbackEvent) 
	if A.CurrentProfile:match("Taste") then 
		GetActionSpellStatus()
		if not isHooked then 
			TMW:RegisterCallback("TMW_ACTION_PLAYER_SPECIALIZATION_CHANGED", OnCallback, "TASTE_BLOCKED_TRACKER")
			isHooked = true 
		end 
	else
		if isHooked then 
			wipe(TR.BlockedListAssoc)
			wipe(TR.BlockedListArray)
			wipe(TR.BlockedListIcon)
			TMW:UnregisterCallback("TMW_ACTION_PLAYER_SPECIALIZATION_CHANGED", OnCallback, "TASTE_BLOCKED_TRACKER")
			TMW:Fire("TMW_ACTION_STATUS_BLOCKED_CHANGED")			
			isHooked = nil
		end 
	end 
end)

--------------------------------------
--------- StdUI Status Frame ---------
--------------------------------------
A.StatusFrame = StdUi:Window(UIParent, 120, 150, "-- Blocked Spells --");
A.StatusFrame.titlePanel.label:SetFontSize(14)
A.StatusFrame.default_w = A.StatusFrame:GetWidth()
A.StatusFrame.default_h = A.StatusFrame:GetHeight() 
A.StatusFrame.titlePanel:SetPoint("TOP", 0, -10)
A.StatusFrame:SetFrameStrata("HIGH")
A.StatusFrame:SetPoint("CENTER")
A.StatusFrame:SetShown(false) 

-- Test refresh button
--local btn = StdUi:Button(StatusFrame, 100, 24, 'Refresh Data');
--StdUi:GlueTop(btn, StatusFrame, 0, -40);

local data = {};
local columns = {
	{
		name         = 'Name',
		width        = 70,
		defaultwidth = 70,
		align        = 'LEFT',
		index        = 'name',
		format       = 'string',
	},
    {
		name         = '',
		width        = 20,
		defaultwidth = 20,
		align        = 'RIGHT',
		index        = 'icon',
		format       = 'icon',
	},
}

local customHeight = 5

local StatusFrameScrollTable = StdUi:ScrollTable(A.StatusFrame, columns, customHeight, 15);
StatusFrameScrollTable:EnableSelection(true);
StatusFrameScrollTable:SetResizable(true)
StdUi:GlueTop(StatusFrameScrollTable, A.StatusFrame, 0, -50);
StatusFrameScrollTable.defaultrows = { numberOfRows = StatusFrameScrollTable.numberOfRows, rowHeight = StatusFrameScrollTable.rowHeight }

function A.StatusFrame.UpdateResize()
    --StatusFrameScrollTable:SetWidth(A.StatusFrame:GetWidth() - 50 )
    --StatusFrameScrollTable:SetHeight(A.StatusFrame:GetHeight() ) 
	-- ScrollTable
	if StatusFrameScrollTable.columns then 
		for i = 1, #StatusFrameScrollTable.columns do 										
			if StatusFrameScrollTable.columns[i].index == "name" then
				-- Column by Name resize
				StatusFrameScrollTable.columns[i].width = round(StatusFrameScrollTable.columns[i].defaultwidth + (A.StatusFrame:GetWidth() - A.StatusFrame.default_w - 1), 0)
				StatusFrameScrollTable:SetColumns(StatusFrameScrollTable.columns)	
				-- Row resize
				StatusFrameScrollTable.numberOfRows = StatusFrameScrollTable.defaultrows.numberOfRows + round((A.StatusFrame:GetHeight() - A.StatusFrame.default_h + 10) / StatusFrameScrollTable.defaultrows.rowHeight, 0)
				StatusFrameScrollTable:SetDisplayRows(StatusFrameScrollTable.numberOfRows, StatusFrameScrollTable.defaultrows.rowHeight)
				break 
			end 
		end
	end 
end

A.StatusFrame:HookScript("OnSizeChanged", A.StatusFrame.UpdateResize)

local function UpdateTableData()
	data = {};

	for i = 1, #TR.BlockedListArray do
		local r = {name = TR.BlockedListArray[i] or (L[A.GetCL()] or L.enUS), icon = TR.BlockedListIcon[i] or 841383}
		-- index
		r.i = i;
		tableinsert(data, r);
	end

	-- update scroll table data
	StatusFrameScrollTable:SetData(data);
end

--btn:SetScript('OnClick', UpdateTableData)

hooksecurefunc(Action, "SetBlocker", function(this)
	if isHooked then 
		GetActionSpellStatus(this)
		UpdateTableData()
		
	end 
end)

function TR.ToggleStatusFrame()
	if not A.PlayerSpec or (not A.MainUI and not A.IsInitialized) then 
		return 
	end 
	
	if A.StatusFrame:IsShown() then 
	    UpdateTableData()
		customHeight = #TR.BlockedListArray or 5
		A.StatusFrame:SetShown(not A.StatusFrame:IsShown())
		A.StatusFrame.resizer = A.StdUi.CreateResizer(A.StatusFrame)
		return
	else 
	    UpdateTableData()
		customHeight = #TR.BlockedListArray or 5
		A.StatusFrame:SetShown(not A.StatusFrame:IsShown())
        A.StatusFrame.resizer = A.StdUi.CreateResizer(A.StatusFrame)		
	end 
	
end

--------------------------------------------------------
----------- DOGTAG CALL FOR STATUS FRAME ---------------
--------------------------------------------------------
-- Replaced by StdUI code as of 24/03/2020 but still working if someone wants to use it through TMW DogTags
local DogTag = LibStub("LibDogTag-3.0", true)
TMW:RegisterCallback("TMW_ACTION_STATUS_BLOCKED_CHANGED",  	DogTag.FireEvent, DogTag)
if DogTag then 
	-- Status Frame Blocked Spells
	DogTag:AddTag("TMW", "ActionStatusBlockedSpell", {
		code = function()
			if #TR.BlockedListArray > 0 then
			    for i = 1, #TR.BlockedListArray do
				    return TR.BlockedListArray[i]
				end
			else
				return L[A.GetCL()] or L.enUS
			end
		end,
		ret = "string",
		doc = "Displays Blocked Spells Icon",
		example = '[ActionStatusFrame] => "TR.BlockedListArray.icon"',
		events = "TMW_ACTION_STATUS_BLOCKED_CHANGED",
		category = "Action",
	})	
	-- Status Frame Blocked Spells Icon
	DogTag:AddTag("TMW", "ActionStatusBlockedIcon", {
		code = function()
			if #TR.BlockedListIcon > 0 then
			    for i = 1, #TR.BlockedListIcon do
				    return TR.BlockedListIcon[i]
				end
			else
				return L[A.GetCL()] or L.enUS
			end
		end,
		ret = "string",
		doc = "Displays Blocked Spells",
		example = '[ActionStatusFrame] => "TR.BlockedListArray.spellname"',
		events = "TMW_ACTION_STATUS_BLOCKED_CHANGED",
		category = "Action",
	})
end 

------------------------------------
------- NOTIFICATIONS API v2 -------
------------------------------------
-- Return a tost notification directly in game with status information from rotation. Useful for custom events announcer    
-- @Parameters : Message and Spell are mandatory settings. 
-- @optional Parameters : Delay and incombat can be nil 
-- Usage : /run A.SendNotification("test", 22812, 2, false) 

-- NEW Using LibToast v1.0
-- Embed LibToast directly inside Action calls
if LibToast then

    LibToast:Embed(Action)

    -- NEW Creates a template called "UrgencyToast" which sets the text to whatever
    -- Callback on Ok button
    local function CloseToast()
    end
	
    -- Toast settings
    Action:RegisterToast("UrgencyToast", function(toast, message, icon)
        local icontexture = GetSpellTexture(icon)
        --toast:SetTitle(" ") -- Do we really need title ? Lets see later
        toast:SetText(message)
        toast:SetIconTexture(icontexture)
    	toast:SetUrgencyLevel("emergency") 
	    --toast:SetTextFont("Fonts\\ARIALN.ttf", 25)
    	--toast:SetFormattedText("FriendsFont_Large", message)
        --toast:MakePersistent()
        --toast:SetPrimaryCallback(_G.OKAY, CloseToast)
    end)
-- /run A:SpawnToast("UrgencyToast", "Urgency!!!", 22812)
end

-- Core function   
function A.SendNotification(message, spell, delay, incombat)
    local DelaySetting = A.GetToggle(2, "AnnouncerDelay")
    local InCombatSetting = A.GetToggle(2, "AnnouncerInCombatOnly")
    local Enabled = A.GetToggle(2, "UseAnnouncer")
    
    if not message then
        A.Print("You didn't set any message for Notification.")
    end
    
    if not delay then
        if DelaySetting then 
            delay = DelaySetting
        else
            delay = 2
        end
    end
    
    if not incombat then
        if InCombatSetting then 
            incombat = InCombatSetting
        else        
            incombat = false
        end
    else
        incombat = true
    end
    
    -- Variables
    local timer = TMW.time
    local endtimer = timer + delay    
    A.NotificationMessage = ""
    A.NotificationIsValid = false
    A.NotificationIsValidUntil = endtimer
    A.CurrentNotificationIcon = GetSpellTexture(spell)
    -- Check if enabled
    if Enabled then
        -- Option 1 : Combat only        
        if message and spell and incombat then 
            if (TMW.time <= endtimer) and Unit("player"):CombatTime() > 1 then 
                A.NotificationIsValid = true
                A.NotificationMessage = message                 
            else
                A.NotificationIsValid = false
            end
            -- Option 2 : Everytime
        elseif message and spell and not incombat then     
            if TMW.time <= endtimer then 
                A.NotificationIsValid = true
                A.NotificationMessage = message            
            else
                A.NotificationIsValid = false
            end
        end
    end
	-- Return result to both TMW System and LibToast
	if not LibToast then
        TMW:Fire("TMW_ACTION_NOTIFICATION")    
        return A.NotificationMessage, A.CurrentNotificationIcon, A.NotificationIsValid, A.NotificationIsValidUntil
    else
	    Action:SpawnToast("UrgencyToast", A.NotificationMessage, A.CurrentNotificationIcon)
	end
end  			

------------------------------------
-- DogTags
------------------------------------
-- Taste's 
TMW:RegisterCallback("TMW_ACTION_NOTIFICATION", DogTag.FireEvent, DogTag)

if DogTag then
	-- Custom Icon
	DogTag:AddTag("TMW", "ActionNotificationIcon", {
        code = function()
			if A.CurrentNotificationIcon and A.NotificationIsValid then
				return A.CurrentNotificationIcon
			else 
				return ""
			end 
        end,
        ret = "string",
        doc = "Displays Notification Icon",
		example = '[ActionNotification] => "A.SendNotification(message, spell, delay)"',
        events = "TMW_ACTION_NOTIFICATION",
        category = "Action",
    })

	-- Custom Notifications
	DogTag:AddTag("TMW", "ActionNotificationMessage", {
        code = function()
			if A.NotificationMessage and A.NotificationIsValid then				
				return A.NotificationMessage
			else 
				return ""
			end 
        end,
        ret = "string",
        doc = "Displays Notification Message",
		example = '[ActionNotification] => "A.SendNotification(message, spell, delay)"',
        events = "TMW_ACTION_NOTIFICATION",
        category = "Action",
    })			
	
	-- The biggest problem of TellMeWhen what he using :setup on frames which use DogTag and it's bring an error
	TMW:RegisterCallback("TMW_ACTION_IS_INITIALIZED", function()
		TMW:Fire("TMW_ACTION_NOTIFICATION")
	end)
end



------------------------------------
--- Version checker by Ayni
------------------------------------
local function GetUnixTimeStamp(dateString)
    if type(dateString) ~= "string" then 
        error(toStr[dateString or "nil"] .. " is not a string for func GetUnixTimeStamp")
        return
    end
    
    local dateTable = {}
    for v in dateString:gmatch("%d+") do
        v = toNum[v]
        
        if not dateTable.day then 
            dateTable.day = v
        elseif not dateTable.month then
            dateTable.month = v
        else
            dateTable.year = v
        end
    end
    
    return time(dateTable)
end

-- Version Popup
-- TODO : Localized text and button
StaticPopupDialogs["ACTION_OUTDATED_VERSION"] = {
  text = "[WARNING]\n\nYou are currently running an old version of A.\n\nPlease close the game and update.)",
  button1 = "Got it",
  OnAccept = function()
      StaticPopup_Hide ("ACTION_OUTDATED_VERSION")
  end,
  timeout = 0,
  whileDead = true,
  hideOnEscape = true,
  preferredIndex = 2,  -- avoid some UI taint, see http://www.wowace.com/announcements/how-to-avoid-some-ui-taint/
}

-- Addon version less than required date time of the need addon version
--print(GetUnixTimeStamp(A.DateTime) < GetUnixTimeStamp("31.07.2020"))
if GetUnixTimeStamp(A.DateTime) < GetUnixTimeStamp("30.07.2020") then
    TR.OptimalConfiguration = false
    StaticPopup_Show ("ACTION_OUTDATED_VERSION")
end

--if TR.OptimalConfiguration ~= true then
--    A.SendNotification("[WARNING]You are currently using Taste Rotations with outdated Action, please update.", 182530, 10, false)  
--end	