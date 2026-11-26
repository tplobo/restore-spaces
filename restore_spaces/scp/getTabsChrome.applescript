-- `getTabsChrome.applescript`

-- Tab titles of all windows of Google Chrome, by scripting it directly.
-- Usage: osascript getTabsChrome.applescript
-- Output: same as `getTabsSafari.applescript`. Chrome window IDs are not the IDs
-- of Hammerspoon, so the caller matches windows by the title of the selected tab.

on run
	set fieldSeparator to character id 31
	set recordSeparator to character id 30
	set resultText to ""
	tell application "Google Chrome"
		repeat with theWindow in windows
			try
				set tabTitles to title of every tab of theWindow
				set activeTitle to title of active tab of theWindow
				set resultText to resultText & my formatWindow(id of theWindow, activeTitle, tabTitles, fieldSeparator) & recordSeparator
			end try
		end repeat
	end tell
	return resultText
end run

on formatWindow(windowId, activeTitle, tabTitles, fieldSeparator)
	set oldDelimiters to AppleScript's text item delimiters
	set AppleScript's text item delimiters to fieldSeparator
	set joinedTitles to tabTitles as text
	set AppleScript's text item delimiters to oldDelimiters
	return (windowId as text) & fieldSeparator & activeTitle & fieldSeparator & joinedTitles
end formatWindow