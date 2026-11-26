-- `getVisibleTabs.applescript`

--######################################################################--
-- CONFIGURATION OBJECTS
--######################################################################--
script appTabShortcuts
	property application : ""
	property rightTabShortcut : {0, {}}
	property leftTabShortcut : {0, {}}
	
	on new(applicationName, rightShortcut, leftShortcut)
		script newAppTabShortcut
			property application : applicationName
			property rightTabShortcut : rightShortcut
			property leftTabShortcut : leftShortcut
		end script
		return newAppTabShortcut
	end new
end script

script Config
	property debugMode : false
	property windowDelay : 0.2
	property tabDelay : 0.1
	property bufferSize : 3
	property maxTabs : 150
	property maxIdenticalConsecutives : 5
	property reportDelimiter : "###"
	property listTabShortcuts : {Â
		appTabShortcuts's new("other", {48, {"control"}}, {48, {"control", "shift"}}), Â
		appTabShortcuts's new("Firefox", {48, {"control"}}, {48, {"control", "shift"}}), Â
		appTabShortcuts's new("Safari", {48, {"control"}}, {48, {"control", "shift"}}), Â
		appTabShortcuts's new("Chrome", {48, {"control"}}, {48, {"control", "shift"}}) Â
		}
	
	on updateScalarProperty(propName, propValue)
		try
			set my (propName) to propValue
		on error errMsg
			log "Error updating property: " & errMsg
		end try
	end updateScalarProperty
	
	on updateTabShortcuts(plistArray)
		set listFromArray to {}
		repeat with i from 1 to count of plistArray
			set tabDict to item i of plistArray
			set end of listFromArray to appTabShortcuts's Â
				new(tabDict's |application|, Â
					tabDict's rightTabShortcut, Â
					tabDict's leftTabShortcut)
		end repeat
		set my listTabShortcuts to listFromArray
	end updateTabShortcuts
	
	on initializeFromPlist(plistPath)
		try
			tell application "System Events"
				tell property list file plistPath
					set my windowDelay to value of property list item "windowDelay"
					set my reportDelimiter to value of property list item "reportDelimiter"
					set my bufferSize to value of property list item "bufferSize"
					set my tabDelay to value of property list item "tabDelay"
					set my maxIdenticalConsecutives to value of property list item "maxIdenticalConsecutives"
					set my debugMode to value of property list item "debugMode"
					set my maxTabs to value of property list item "maxTabs"
					
					set plistArray to value of property list item "listTabShortcuts"
					my updateTabShortcuts(plistArray)
				end tell
			end tell
		on error errMsg number errorNumber
			if errorNumber is -43 then
				log "Warning: plist file not found. Using default configuration."
			else
				log "Error reading plist file: " & errMsg
			end if
		end try
	end initializeFromPlist
	
end script

--######################################################################--
-- GET KEYS TO JUMP TABS
--######################################################################--
on getAppTabJumpKeys(appName, Config)
	
	-- Initialize variables to hold the key codes
	set rightTabList to false
	set leftTabList to false
	
	-- Find the appropriate key code for the given application name
	repeat with entry in listTabShortcuts of Config
		if application of entry is appName then
			set rightTabList to rightTabShortcut of entry
			set leftTabList to leftTabShortcut of entry
			exit repeat
		end if
	end repeat
	
	-- Use default key combinations if specific application keys are not found
	if rightTabList is false or leftTabList is false then
		log "Unknown key combination for application: " & appName
		log "... using default key combinations for jumping to right and left tabs."
		repeat with entry in listTabShortcuts of Config
			if application of entry is "other" then
				set rightTabList to rightTabShortcut of entry
				set leftTabList to leftTabShortcut of entry
				exit repeat
			end if
		end repeat
	end if
	
	return {rightTabList, leftTabList}
	
end getAppTabJumpKeys

--######################################################################--
-- GET MODIFIER KEYS
--######################################################################--
on getModifierFromString(keyList)
	set keyCodes to {}
	repeat with keyElement in keyList
		set keyString to (keyElement as string)
		if keyString is equal to "control" then
			set end of keyCodes to control down
		else if keyString is "shift" then
			set end of keyCodes to shift down
		else if keyString is "option" then
			set end of keyCodes to option down
		else if keyString is "command" then
			set end of keyCodes to command down
		else
			-- Add additional mappings as needed
			error "Unknown key modifier mapping for: '" & keyString & "' "
		end if
	end repeat
	return keyCodes
end getModifierFromString

--######################################################################--
-- GET ALL TABS OF A SINGLE WINDOW
--######################################################################--
-- Logs "CYCLE|<first title>|<key presses>|<why it stopped>|<tabs found>" (read by
-- Hammerspoon). Stop reasons: loop (back at the first tab), stagnant (no new title
-- for `maxStagnantTabs` tabs), identical (the same title `maxIdenticalConsecutives`
-- times in a row), max (`maxTabs` key presses). Unless it looped, the tab that was
-- selected at the start is selected again at the end by pressing the opposite key
-- as many times as the key was pressed.
on getWindowTabs(appName, Config)
	
	-- Initialization
	set tabList to {}
	set counter to 0
	set pressCount to 0
	set tabBuffer to {}
	set firstTabs to {}
	set counterIdenticalConsecutives to 0
	set seenTitles to {}
	set stagnantCounter to 0
	set stopReason to "max"
	set stagnantLimit to 25
	try
		set stagnantLimit to maxStagnantTabs of Config
	end try
	
	-- Define key combinations to jump to right and left tabs
	set keyCombinations to getAppTabJumpKeys(appName, Config)
	set rightTabKeys to item 1 of keyCombinations
	set leftTabKeys to item 2 of keyCombinations
	
	tell application appName
		
		activate
		
		-- Switch to first tab:
		set firstTitle to name of front window
		copy firstTitle to the end of the tabList
		copy firstTitle to the end of the tabBuffer
		copy firstTitle to the end of the firstTabs
		copy firstTitle to the end of the seenTitles
		
		set keyCode to item 1 of rightTabKeys
		set keyModifiers to my getModifierFromString(item 2 of rightTabKeys)
		repeat until (counter > maxTabs of Config)
			tell application "System Events" to key code keyCode using (items of keyModifiers)
			delay tabDelay of Config
			set pressCount to pressCount + 1
			set currentTitle to name of front window
			
			-- Add the current tab to the buffer
			if (length of tabBuffer) is equal to (bufferSize of Config) then
				-- Remove the oldest entry from the buffer
				set tabBuffer to items 2 through -1 of tabBuffer
			end if
			copy currentTitle to the end of tabBuffer
			
			-- Check for identical consecutive tabs
			if (currentTitle is equal to item -1 of tabList) then
				set counterIdenticalConsecutives to counterIdenticalConsecutives + 1
				if (counterIdenticalConsecutives is equal to maxIdenticalConsecutives of Config) then
					set stopReason to "identical"
					exit repeat
				end if
			else
				set counterIdenticalConsecutives to 0
			end if
			
			-- Check if we have looped back to the first tab
			if (length of firstTabs) is less than (bufferSize of Config) then
				copy currentTitle to the end of firstTabs
			else if (tabBuffer is equal to firstTabs) then
				set stopReason to "loop"
				exit repeat
			end if
			
			-- Check whether the list stopped growing: titles that change between laps
			-- (_e.g._ tabs that load when they are selected) make the check above fail.
			-- Stop when no new title appeared for `maxStagnantTabs` tabs, and only
			-- after at least two laps' worth of presses.
			if currentTitle is in seenTitles then
				set stagnantCounter to stagnantCounter + 1
			else
				set stagnantCounter to 0
				copy currentTitle to the end of seenTitles
			end if
			if (stagnantCounter is greater than or equal to stagnantLimit) and (counter is greater than or equal to (2 * (length of seenTitles) + stagnantLimit)) then
				set stopReason to "stagnant"
				exit repeat
			end if
			
			copy currentTitle to the end of the |tabList|
			set counter to counter + 1
		end repeat
		
		-- Go back to the tab that was selected at the start
		set keyCode to item 1 of leftTabKeys
		set keyModifiers to my getModifierFromString(item 2 of leftTabKeys)
		if stopReason is "loop" then
			-- Remove the first (bufferSize - 1) entries from the end of tabList and
			-- go back (bufferSize - 1) tabs to the left
			set tabListLength to length of tabList
			set backCount to ((bufferSize of Config) - 1)
			if tabListLength is greater than or equal to (bufferSize of Config) then
				set tabList to items 1 through (tabListLength - backCount) of tabList
			end if
		else
			set backCount to pressCount
			if stopReason is "stagnant" then set tabList to seenTitles
		end if
		repeat backCount times
			tell application "System Events" to key code keyCode using (items of keyModifiers)
			delay tabDelay of Config
		end repeat
		
	end tell
	
	log "CYCLE|" & firstTitle & "|" & pressCount & "|" & stopReason & "|" & (length of tabList)
	
	-- Build delimited string with list of tab titles
	set tabsString to ""
	repeat with i from 1 to (count of tabList)
		set currentItem to item i of tabList
		set currentString to currentItem & (Config's reportDelimiter)
		if i is 1 then
			set tabsString to currentString
		else
			-- For all subsequent items, prepend the delimiter
			set tabsString to tabsString & currentString
		end if
	end repeat
	
	return tabsString
	
end getWindowTabs

--######################################################################--
-- GET TABS OF ALL WINDOWS IN A SPACE
--######################################################################--
on getVisibleTabs(appName, Config)
	
	set visibleTabs to {}
	tell application appName
		
		-- Get the list of windows of the application in the current space
		tell application "System Events"
			if debugMode of Config is true then
				set appWindows to every window of process appName
				log appWindows
				repeat with singleWindow in appWindows
					set windowProperties to properties of singleWindow
					log windowProperties
				end repeat
			end if
			set visibleWindows to every window of process appName whose description is "standard window"
			log visibleWindows
			if visibleWindows is {} then
				log "No visible windows for application: " & appName
				return visibleTabs
			end if
		end tell
		
		activate
		
		-- Iterate over each visible window
		set processedWindowIDs to {}
		repeat with i from 1 to count of visibleWindows
			tell application "System Events"
				tell process appName
					set frontWindow to (first window whose value of attribute "AXMain" is true)
					set currentTitle to value of attribute "AXTitle" of frontWindow
					set currentWindowID to currentTitle & " - " & i
					
					-- Check if this window has already been processed
					if currentWindowID is not in processedWindowIDs then
						set end of processedWindowIDs to currentWindowID
						
						set windowTabs to my getWindowTabs(appName, Config)
						set titleDelimiter to (reportDelimiter of Config) & (reportDelimiter of Config)
						set reportTitle to titleDelimiter & currentTitle & titleDelimiter
						set end of visibleTabs to {reportTitle, windowTabs}
					end if
					
					-- Switch to the next window
					if i < (count of visibleWindows) then
						keystroke "`" using {command down}
						delay (windowDelay of Config)
					end if
				end tell
			end tell
		end repeat
		
	end tell
	
	return visibleTabs
	
end getVisibleTabs

--######################################################################--
-- RUN
--######################################################################--
on run arguments
	set appDefault to "Safari"
	set pathDefault to (POSIX path of (path to home folder)) & ".hammerspoon/hs/restore_spaces/scp/scp_config.plist"
	if ((count of arguments) > 1) then
		set appName to item 1 of arguments
		set pathConfig to item 2 of arguments
	else if ((count of arguments) > 0) then
		set appName to item 1 of arguments
		set pathConfig to pathDefault
	else
		set appName to appDefault
		set pathConfig to pathDefault
	end if
	Config's initializeFromPlist(pathConfig)
	
	try
		set visibleTabs to my getVisibleTabs(appName, Config)
	on error errMsg
		return errMsg
	end try
	return visibleTabs
end run