--######################################################################--
-- GET KEYS TO JUMP TABS
--######################################################################--
on getAppTabJumpKeys(appName)
	
	-- Key codes to jump one tab to the right and one tab to the left
	-- (original combination for Firefox: key code 121 using control down)
	set keyList to {"app", "right-tab key code and modifiers", "left-tab key code and modifiers"}
	set end of keyList to {"Firefox", {48, {control down}}, {48, {control down, shift down}}}
	set end of keyList to {"Google Chrome", {48, {control down}}, {48, {control down, shift down}}}
	set end of keyList to {"Safari", {48, {control down}}, {48, {control down, shift down}}}
	set end of keyList to {"other", {48, {control down}}, {48, {control down, shift down}}}
	
	-- Find appropriate the key code
	set rightTabKeys to false
	set leftTabKeys to false
	repeat with i in keyList
		if item 1 of i is appName then
			set rightTabKeys to item 2 of i
			set leftTabKeys to item 3 of i
			exit repeat
		end if
	end repeat
	if rightTabKeys is false or leftTabKeys is false then
		log "Unknown key combination for application: " & appName
		log "... using default key combinations for jumping to right and left tabs."
		repeat with i in keyList
			if item 1 of i is "other" then
				set rightTabKeys to item 2 of i
				set leftTabKeys to item 3 of i
				exit repeat
			end if
		end repeat
	end if
	
	return {rightTabKeys, leftTabKeys}
	
end getAppTabJumpKeys

--######################################################################--
-- GET ALL TABS OF A SINGLE WINDOW
--######################################################################--
on getWindowTabs(appName)
	
	-- Configuration
	set tabDelay to 0.1
	set bufferSize to 3
	set maxTabs to 100
	set maxIdenticalConsecutives to 5
	
	-- Initialization
	set tabList to {}
	set counter to 0
	set tabBuffer to {}
	set firstTabs to {}
	set counterIdenticalConsecutives to 0
	
	-- Define key combinations to jump to right and left tabs
	set keyCombinations to getAppTabJumpKeys(appName)
	set rightTabKeys to item 1 of keyCombinations
	set leftTabKeys to item 2 of keyCombinations
	
	set pruneFlag to false
	
	tell application appName
		
		activate
		
		-- Switch to first tab:
		set firstTitle to name of front window
		copy firstTitle to the end of the tabList
		copy firstTitle to the end of the tabBuffer
		copy firstTitle to the end of the firstTabs
		
		set keyCode to item 1 of rightTabKeys
		set keyModifiers to item 2 of rightTabKeys
		repeat until (counter > maxTabs)
			tell application "System Events" to key code keyCode using (items of keyModifiers)
			delay tabDelay
			set currentTitle to name of front window
			
			-- Copy URL instead:
			--tell application "System Events" to keystroke "l" using command down
			--tell application "System Events" to keystroke "c" using command down
			--copy (the clipboard) to the end of the |tabList|
			
			-- Add the current tab to the buffer
			if (length of tabBuffer) is equal to bufferSize then
				-- Remove the oldest entry from the buffer
				set tabBuffer to items 2 through -1 of tabBuffer
			end if
			copy currentTitle to the end of the tabBuffer
			
			-- Check for identical consecutive tabs
			if (currentTitle is equal to item -1 of tabList) then
				set counterIdenticalConsecutives to counterIdenticalConsecutives + 1
				if (counterIdenticalConsecutives is equal to maxIdenticalConsecutives) then
					exit repeat
				end if
			else
				set identicalTabCounter to 0
			end if
			
			-- Check if we have looped back to the first tab
			if (length of firstTabs) is less than bufferSize then
				copy currentTitle to the end of the firstTabs
			else if (tabBuffer is equal to firstTabs) then
				set pruneFlag to true
				exit repeat
			end if
			
			copy currentTitle to the end of the tabList
			set counter to counter + 1
		end repeat
		
		if pruneFlag is true then
			set tabListLength to length of tabList
			set pruneCount to (bufferSize - 1)
			
			-- Remove the first (bufferSize - 1) entries from the end of tabList
			if tabListLength > bufferSize or tabListLength is equal to bufferSize then
				--if tabListLength ³ bufferSize then
				set tabList to items 1 through (tabListLength - pruneCount) of tabList
			end if
			
			-- Go back (bufferSize - 1) tabs to the left
			set keyCode to item 1 of leftTabKeys
			set keyModifiers to item 2 of leftTabKeys
			repeat pruneCount times
				tell application "System Events" to key code keyCode using (items of keyModifiers)
				delay tabDelay
			end repeat
		end if
		
	end tell
	
	log length of tabList
	log tabList
	
	return tabList
	
end getWindowTabs

--######################################################################--
-- GET TABS OF ALL WINDOWS IN A SPACE
--######################################################################--
on getVisibleTabs(appName)
	
	-- Configuration
	set debugMode to false
	set windowDelay to 0.2
	set reportDelimiter to "###"
	
	-- Initialize the list of tab lists
	set visibleTabs to {}
	
	tell application appName
		
		-- Get the list of windows of the application in the current space
		tell application "System Events"
			if debugMode is true then
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
		repeat with currentWindow in visibleWindows
			tell application "System Events"
				tell process appName
					set frontWindow to (first window whose value of attribute "AXMain" is true)
					set currentTitle to value of attribute "AXTitle" of frontWindow
					repeat
						keystroke "`" using command down
						delay windowDelay
						set appWindows to every window
						repeat with singleWindow in appWindows
							if value of attribute "AXMain" of singleWindow is true then
								set frontWindow to singleWindow
								exit repeat
							end if
						end repeat
						set frontTitle to value of attribute "AXTitle" of frontWindow
						if frontTitle is equal to currentTitle then exit repeat
					end repeat
				end tell
			end tell
			set windowTabs to my getWindowTabs(appName)
			set reportTitle to reportDelimiter & currentTitle & reportDelimiter
			set end of visibleTabs to {reportTitle, windowTabs}
		end repeat
		
	end tell
	
	return visibleTabs
	
end getVisibleTabs

--######################################################################--
-- RUN
--######################################################################--
on run arguments
	set defaultName to "Safari"
	if ((count of arguments) > 0) then
		set appName to item 1 of arguments
	else
		set appName to defaultName
	end if
	try
		set visibleTabs to my getVisibleTabs(appName)
	on error errMsg
		return errMsg
	end try
	return visibleTabs
end run