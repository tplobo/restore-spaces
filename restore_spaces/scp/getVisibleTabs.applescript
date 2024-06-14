on getWindowTabs(appName, rightTabKeys, leftTabKeys)
	
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
	
	set pruneFlag to false
	
	tell application appName
		
		activate
		
		-- Switch to first tab:
		tell application "System Events" to keystroke "1" using command down
		delay tabDelay
		set firstTitle to name of front window
		copy firstTitle to the end of the tabList
		copy firstTitle to the end of the tabBuffer
		copy firstTitle to the end of the firstTabs
		
		repeat until (counter > maxTabs)
			set keyCode to item 1 of rightTabKeys
			set keyModifiers to item 2 of rightTabKeys
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
		
		-- Remove the first (bufferSize - 1) entries from the end of tabList
		if pruneFlag is true then
			set tabListLength to length of tabList
			if tabListLength ³ bufferSize then
				set tabList to items 1 through (tabListLength - bufferSize + 1) of tabList
			end if
		end if
		
	end tell
	
	log length of tabList
	log tabList
	
	return tabList
	
end getWindowTabs

on getAppTabJumpKeys(appName)
	
	-- Key codes to jump one tab to the right
	set keyList to {"app", "right-tab key code and modifiers", "left-tab key code and modifiers"}
	set end of keyList to {"Firefox", {48, {control down}}, {48, {control down, shift down}}} -- original: key code 121 using control down
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
		log "Using default right and left tab key combinations."
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

on getVisibleTabs(appName)
	
	-- Configuration
	set debugMode to false
	set windowDelay to 0.1
	
	-- Define key combinations to jump to right and left tabs
	set keyCombinations to getAppTabJumpKeys(appName)
	set rightTabKeys to item 1 of keyCombinations
	set leftTabKeys to item 2 of keyCombinations
	
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
				set currentTitle to title of currentWindow
				repeat
					keystroke "`" using command down
					delay windowDelay
					set appWindows to every window of process appName
					repeat with singleWindow in appWindows
						if focused of singleWindow is true then
							set frontWindow to singleWindow
							exit repeat
						end if
					end repeat
					set frontTitle to title of frontWindow
					if frontTitle is equal to currentTitle then exit repeat
				end repeat
			end tell
			set windowTabs to my getWindowTabs(appName, rightTabKeys, leftTabKeys)
			set end of visibleTabs to {currentTitle, windowTabs}
		end repeat
		
	end tell
	
	return visibleTabs
	
end getVisibleTabs

getVisibleTabs("Firefox")