-- `getTabsSafari.applescript`

-- Tab titles of all windows of Safari, by scripting it directly.
-- Usage: osascript getTabsSafari.applescript
-- Output: one record per window, each ended by the ASCII "record separator"
-- (30), with fields separated by the ASCII "unit separator" (31):
--     <window id> <US> <title of the selected tab> <US> <title of tab 1> <US> ...
-- Each app has its own file because AppleScript needs the dictionaries of all the
-- apps a file mentions to compile it: an app that is not installed (or whose
-- dictionary differs) would break every other app of a shared file.

on run
	set fieldSeparator to character id 31
	set recordSeparator to character id 30
	set resultText to ""
	tell application "Safari"
		repeat with theWindow in windows
			try
				set tabTitles to name of every tab of theWindow
				set activeTitle to name of current tab of theWindow
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