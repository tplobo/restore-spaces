on run
	set allAppsData to {}
	tell application "System Events"
		set allApps to every application process whose visible is true
		
		repeat with appProcess in allApps
			set appTitle to title of appProcess
			set windowTitles to {}
			
			
			if appTitle is "Safari" then
				tell application "Safari"
					repeat with win in windows
						set end of windowTitles to {id of win, name of every tab of win}
					end repeat
				end tell
			else if has scripting terminology of appProcess is true then
				try
					set appName to name of appProcess
					tell application appName
						repeat with win in windows
							set end of windowTitles to {id of win, properties of win}
						end repeat
					end tell
				on error errMsg
					set windowTitles to {"error for " & appName}
				end try
			else
				set windowTitles to {properties of appProcess}
				(*
				tell application appName
					repeat with win in windows
						set windowTitles to properties of win
						set end of appTitles to {windowTitles}
					end repeat
				end tell
				*)
				
			end if
			
			if windowTitles is not {} then
				set end of allAppsData to {appTitle, windowTitles}
			else
				set end of allAppsData to {appTitle, {}}
			end if
			
		end repeat
		
	end tell
	return allAppsData
end run

