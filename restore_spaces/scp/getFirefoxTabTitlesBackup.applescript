on getVisibleTabs(appName)
	
	-- Key codes to jump one tab to the right
	set keyList to {"app", "right-tab key code and modifiers", "left-tab key code and modifiers"}
	set end of keyList to {"Firefox", {48, control down}, {48, {control down, shift down}}} -- original: key code 121 using control down
	set end of keyList to {"Google Chrome", {48, control down}, {48, {control down, shift down}}}
	set end of keyList to {"Safari", {48, control down}, {48, {control down, shift down}}}
	
	-- Find appropriate the key code
	set keyCode to false
	repeat with i in keyList
		if item 1 of i is appName then
			set rightKeyCode to item 2 of i
			set leftKeyCode to item 3 of i
			exit repeat
		end if
	end repeat
	if keyCode is false then
		display dialog "Unknown key combination for application: " & appName
		return
	end if
	
	-- Initialize the list of tab lists
	set visibleTabs to {}
	
	-- ...
	tell application "System Events"
		-- Get the list of visible windows for the specific application
		set visibleWindows to every window of process appName whose visible is true
		-- If there are no visible windows, exit the script
		if visibleWindows is {} then
			log "No visible windows for application: " & appName
			return
		end if
	end tell
	
	-- Iterate over each visible window
	tell application appName
		repeat with currentWindow in visibleWindows
			set frontmost of aWindow to true
			set tabList to my getWindowTabs(currentWindow, appName, rightKeyCode, leftKeyCode)
			set end of visibleTabs to {id of currentWindow, tabList}
		end repeat
	end tell
	
	return visibleTabs
	
end getVisibleTabs












on getWindowTabs(appName)
	
	tell application appName
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
		
		activate
		
		-- Switch to first tab:
		tell application "System Events" to keystroke "1" using command down
		delay tabDelay
		set firstTitle to name of front window
		copy firstTitle to the end of the tabList
		copy firstTitle to the end of the tabBuffer
		copy firstTitle to the end of the firstTabs
		
		repeat until (counter > maxTabs)
			tell application "System Events" to key code (item 1 of keyCode) using (item 2 of keyCode)
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
	
end getWindowTabs

getVisibleTabs("Safari")