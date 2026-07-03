local guiNotification = {
	active = false,
	message = "",
	actions = {},
}

local function ShowGUINotification(msg: string, buttons: any)
	guiNotification.active = true
	guiNotification.message = msg
	guiNotification.actions = buttons
end

-- Session variables.
local firstFrame = true -- Used to follow freecam automatically.
local canPauseAgain = false
local areGroupedPaused = false

-- Configuration and stuff.
local newBallScaleMultiplier = 0.5
local automaticallySyncReplayStates = true -- Should we automatically sync replay playing states to areGroupedPaused?

-- Replay Spacing
local replaySpacingDifference = 0.5 -- Would space each replay this var apart in time.

-- Fast Forward and Rewind Keybinds
config.timeManipEnabled = config.timeManipEnabled or true
local fastForwardSeconds = 5 -- The amount of seconds to add when fast forwarding.
local rewindSeconds = -5 -- The amount of seconds to go back when rewinding.
local canInteractWithFastFoward = true
local canInteractWithRewind = true
local destinationTime = 0

-- Replay cache.
local replayCallbackCache = {}
config.replayCallbackCache = config.replayCallbackCache or {}
config.enableReplayCallback = config.enableReplayCallback or true
local replayCacheTicksSinceLastUpdate = 0

local function UpdateReplayCache()
	replayCallbackCache = {}
	local loadedReplays = Replay.listLoaded()

	for i = 1, #loadedReplays do
		local name = loadedReplays[i]
		replayCallbackCache[name] = {}
		local replay = Replay.getByIndex(i)
		if replay == nil then
			continue
		end
		replayCallbackCache[name]["time_stamp"] = tostring(replay:getPlaybackTimeSeconds())
	end
end

local function LoadReplayCallbackCacheFromConfig()
	print("Loading replay cache...")
	replayCallbackCache = {}
	Replay.unloadAll()
	local allReplays = Replay.listAll()
	for replayName: string, data in pairs(config.replayCallbackCache) do
		local replayFound = false
		local replayNameSplit = replayName:split("/")[8] -- So.. The replay system is just awkward and uses your directory while allReplays doesn't. We have to do this hackjob solution because AA hates me.
		for i = 1, #allReplays do
			print(allReplays[i] .. " --> " .. replayNameSplit)
			if allReplays[i] == replayNameSplit then
				replayFound = true
				break
			end
		end

		if replayFound == false then
			print("Replay not found.")
			continue
		end

		local replay = Replay.load(replayNameSplit)

		if replay == nil then
			continue
		end

		print(replayNameSplit .. " --> " .. config.replayCallbackCache[replayName]["time_stamp"])
		local ts = tonumber(config.replayCallbackCache[replayName]["time_stamp"])

		replay:setPlaybackTimeSeconds(ts)

		replayCallbackCache[replayName] = {}

		replayCallbackCache[replayName]["time_stamp"] = tostring(replay:getPlaybackTimeSeconds())
	end
end

-- Other functions
local function ToggleAllReplaysPlaying()
	if areGroupedPaused then
		areGroupedPaused = false
	else
		areGroupedPaused = true
	end

	for i = 1, #Replay.listLoaded() do
		local replay = Replay.getByIndex(i)

		replay.isPlaying = areGroupedPaused
	end
end

local function FirstFrameAutoFollowFreecam()
	camera:followCamera(getCameraById("anotheraxiom.freecam"))
	firstFrame = false
end

local function ResetAllReplaysToBegin()
	for i = 1, #Replay.listLoaded() do
		local replay = Replay.getByIndex(i)
		replay:setPlaybackTimeSeconds(0)
	end
end

local function UnloadAllReplays()
	Replay.unloadAll() -- Bye bye replay :D
end

local function SpaceAllReplays()
	local lastReplayTime: number = 0

	for i = 1, #Replay.listLoaded() do
		local replay = Replay.getByIndex(i)

		if i == 1 then
			replay:setPlaybackTimeSeconds(0)
			continue
		end

		replay:setPlaybackTimeSeconds(lastReplayTime + replaySpacingDifference)

		lastReplayTime = replay:getPlaybackTimeSeconds()
	end
end

local function PushTimeToReplays(time: number)
	for i = 1, #Replay.listLoaded() do
		local replay = Replay.getByIndex(i)

		replay:setPlaybackTimeSeconds(replay:getPlaybackTimeSeconds() + time)

		if replay:getPlaybackTimeSeconds() < 0 then
			replay:setPlaybackTimeSeconds(0)
		end

		if replay:getPlaybackTimestamp().ticks > replay:getEndTime().ticks then
			replay:setPlaybackTimestamp(replay:getEndTime())
		end
	end
end

-- Update loops
-- All of these functions will have DT as a reference just in case (even if unused.)
local function SpacebarPausing(dt: number)
	if Input.getKey(Input.Key.SpaceBar) and canPauseAgain == true then
		ToggleAllReplaysPlaying()
		canPauseAgain = false
	elseif Input.getKey(Input.Key.SpaceBar) == false and canPauseAgain == false then
		canPauseAgain = true
	end
end

local function ReplayStateSyncing(dt: number)
	if automaticallySyncReplayStates == false then
		return -- Toggleable setting :D
	end

	for i = 1, #Replay.listLoaded() do
		local replay = Replay.getByIndex(i)
		replay.isPlaying = areGroupedPaused
	end
end

local function FastForwardingAndRewind()
	if canInteractWithFastFoward and Input.getKeyDown(Input.Key.RightBracket) then
		PushTimeToReplays(fastForwardSeconds)
		canInteractWithFastFoward = false
	elseif canInteractWithFastFoward == false and Input.getKeyDown(Input.Key.RightBracket) == false then
		canInteractWithFastFoward = true
	end

	if canInteractWithRewind and Input.getKeyDown(Input.Key.LeftBracket) then
		PushTimeToReplays(rewindSeconds)
		canInteractWithRewind = false
	elseif canInteractWithRewind == false and Input.getKeyDown(Input.Key.LeftBracket) == false then
		canInteractWithRewind = true
	end
end

function tick(dt: number)
	if firstFrame == true then
		FirstFrameAutoFollowFreecam()
	end

	if config.enableReplayCallback then
		replayCacheTicksSinceLastUpdate = replayCacheTicksSinceLastUpdate + 1

		if replayCacheTicksSinceLastUpdate >= 50 then
			UpdateReplayCache()
			replayCacheTicksSinceLastUpdate = 0
		end
	end

	ReplayStateSyncing(dt)
	SpacebarPausing(dt)
	FastForwardingAndRewind()
end

function onGui()
	Gui.text("Layna's Replay Utilities")
	-- Gui.text("Script version: " .. metadata.version)
	Gui.spacing()

	if guiNotification.active then
		Gui.textColored(LinearColor.new(1, 0, 0, 1), "Important!")
		Gui.text(guiNotification.message)
		Gui.spacing()
		for i = 1, #guiNotification.actions do
			if Gui.button(guiNotification.actions[i][1]) then
				guiNotification.actions[i][2]()
				guiNotification.active = false
			end

			Gui.sameLine()
		end

		if Gui.button("Dismiss##builtInGuiNotification") then
			guiNotification.active = false
		end

		return
	end

	if Gui.beginTabBar("Tab") then
		if Gui.beginTabItem("Overview") then
			Gui.text("Replays Loaded: " .. #Replay.listLoaded())

			Gui.separator()
			Gui.spacing()

			newBallScaleMultiplier = Gui.sliderFloat("Ball Scale Multiplier", newBallScaleMultiplier, 0.3, 100)
			Gui.setItemTooltip("Change how much the scale of the balls in the replay are multiplied by.")
			spectatorDebug.replayBallScaleMultiplier = newBallScaleMultiplier

			Gui.spacing()

			Gui.text("Replay spacing works best when using the same replays loaded multiple times.")

			replaySpacingDifference =
				Gui.sliderFloat("Replay spacing difference (seconds)", replaySpacingDifference, 0.1, 50)

			Gui.setItemTooltip(
				"How much time should each replay be ahead of the last? (In seconds for those who want to do cool replay things like Rainsy :D)"
			)

			if Gui.button("Space Replay Time") then
				SpaceAllReplays()
			end

			Gui.spacing()

			if Gui.button(if areGroupedPaused == true then "Pause all Replays" else "Unpause all Replays") then
				ToggleAllReplaysPlaying()
			end

			if Gui.button("Reset all replays to beginning") then
				ResetAllReplaysToBegin()
			end

			if Gui.button("Unload all Replays") then
				UnloadAllReplays()
			end

			Gui.endTabItem()
		end

		if Gui.beginTabItem("Settings") then
			automaticallySyncReplayStates =
				Gui.checkbox("Automatically sync replay play states?", automaticallySyncReplayStates)
			Gui.setItemTooltip(
				"Whether the script should forcefully sync each replays playing status to what the script expects (every frame.)"
			)

			Gui.spacing()

			Gui.text("Time manipulation")

			config.timeManipEnabled = Gui.checkbox("Enable fast forward & rewind?", config.timeManipEnabled)
			Gui.sameLine()
			if Gui.button("Save##timeManipulation") then
				saveConfig()
			end

			if config.timeManipEnabled then
				fastForwardSeconds = Gui.sliderInt("Fast Forward by seconds", fastForwardSeconds, 1, 10000)

				rewindSeconds = Gui.sliderInt("Rewind by seconds", rewindSeconds, -1, -10000)
			end
			Gui.endTabItem()
		end

		if Gui.beginTabItem("Replay Callback") then
			config.enableReplayCallback = Gui.checkbox("Enable Replay Callback?", config.enableReplayCallback)
			Gui.sameLine()
			if Gui.button("Save##replayCallbackEnabled") then
				saveConfig()
			end

			if config.enableReplayCallback then
				for replayName, data in pairs(replayCallbackCache) do
					Gui.text(replayName .. " - " .. data.time_stamp)
				end

				Gui.spacing()

				if Gui.button("Force Reload") then
					UpdateReplayCache()
				end
				Gui.setItemTooltip(
					"Use this button if the information above is not correct and a bit behind. Shouldn't happen but might?"
				)

				Gui.sameLine()

				if Gui.button("Save cache") then
					config.replayCallbackCache = replayCallbackCache
					saveConfig()
				end
				Gui.setItemTooltip(
					"This will save the replay cache. Which means you can pull your replay states back another time!"
				)

				Gui.sameLine()

				if Gui.button("Load from save") then
					ShowGUINotification(
						"Are you sure? By loading from your last save, You will lose all current progress!",
						{
							{ "I'm sure!", LoadReplayCallbackCacheFromConfig },
						}
					)
				end
				Gui.setItemTooltip("This will load your last saved replay cache from your storage!")
			end
			Gui.endTabBar()
		end

		Gui.endTabBar()
	end
end
