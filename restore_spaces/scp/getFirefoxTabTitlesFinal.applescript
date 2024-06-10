tell application "Firefox"
	-- Configuration
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
	
	-- Ensure maxIdenticalConsecutives is not greater than bufferSize
	--if maxIdenticalConsecutives > bufferSize then
	--	set maxIdenticalConsecutives to bufferSize
	--end if
	
	activate
	
	-- Switch to first tab:
	tell application "System Events" to keystroke "1" using command down
	delay 0.1
	set firstTitle to name of front window
	copy firstTitle to the end of the |tabList|
	copy firstTitle to the end of the |tabBuffer|
	copy firstTitle to the end of the |firstTabs|
	
	repeat until (counter > maxTabs)
		tell application "System Events" to key code 121 using control down
		delay 0.1
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
			copy currentTitle to the end of the |firstTabs|
		else if (tabBuffer is equal to firstTabs) then
			set pruneFlag to true
			exit repeat
		end if
		
		copy currentTitle to the end of the |tabList|
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