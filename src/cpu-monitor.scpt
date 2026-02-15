-- CPU Monitor - AppleScript Edition v1.0.0-AS
-- Process CPU monitoring using ps command
-- Works without sudo for most user processes

-- ============================================================================
-- GLOBALS & PROPERTIES
-- ============================================================================

global conf
global lastPid
global countConsec
global csvBuf
global lastFlush
global shouldExit

property VERSION : "1.0.0-AS"
property DEF_THRESH : 85
property DEF_INTER : 30
property DEF_COUNT : 4
property DEF_DIR : "."
property FLUSH_SEC : 60

-- ============================================================================
-- INIT
-- ============================================================================

on init_all()
	set conf to {thresh:DEF_THRESH, inter:DEF_INTER, cnt:DEF_COUNT, dir:DEF_DIR, cmds:{}, dbg:false, help_req:false, ver_req:false}
	set lastPid to -1
	set countConsec to 0
	set csvBuf to {}
	set lastFlush to current date
	set shouldExit to false
end init_all

-- ============================================================================
-- DEBUG
-- ============================================================================

on printDbg(msg)
	if dbg of conf then
		log "[DEBUG] " & msg
	end if
end printDbg

-- ============================================================================
-- TIMESTAMP
-- ============================================================================

on getTimestamp()
	set now to current date
	set y to year of now
	set m to month of now as integer
	set d to day of now
	set h to hours of now
	set mi to minutes of now
	set s to seconds of now
	
	set ms to text -2 thru -1 of ("0" & m)
	set ds to text -2 thru -1 of ("0" & d)
	set hs to text -2 thru -1 of ("0" & h)
	set mis to text -2 thru -1 of ("0" & mi)
	set ss to text -2 thru -1 of ("0" & s)
	
	return y & "-" & ms & "-" & ds & "T" & hs & ":" & mis & ":" & ss & "Z"
end getTimestamp

-- ============================================================================
-- GET TOP PROCESS
-- ============================================================================

on getTopProcess()
	try
		set psOut to do shell script "ps -axo pid,%cpu,comm"
		set psLines to paragraphs of psOut
		
		set topProc to {pid:-1, name:"", cpu:0}
		set cnt to 0
		
		repeat with i from 2 to count of psLines
			set ln to (item i of psLines) as string
			set ln to trim_ws(ln)
			
			if ln is not "" then
				set toks to split_ws(ln)
				
				if (count of toks) >= 3 then
					try
						set p to ((item 1 of toks) as integer)
						set c to ((item 2 of toks) as real)
						
						set nm to ""
						repeat with j from 3 to count of toks
							if nm is "" then
								set nm to (item j of toks)
							else
								set nm to nm & " " & ((item j of toks) as string)
							end if
						end repeat
						
						if c > (cpu of topProc) then
							set topProc to {pid:p, name:nm, cpu:c}
						end if
						set cnt to cnt + 1
					on error
					end try
				end if
			end if
		end repeat
		
		printDbg("Sampling: total=" & cnt & " top_pid=" & (pid of topProc) & " top_cpu=" & (cpu of topProc))
		return topProc
		
	on error err
		log "ps error: " & err
		set shouldExit to true
		return {pid:-1, name:"", cpu:0}
	end try
end getTopProcess

-- ============================================================================
-- TRIM
-- ============================================================================

on trim_ws(s)
	set s to s as string
	repeat while s starts with " " or s starts with tab
		set s to text 2 thru -1 of s
	end repeat
	repeat while s ends with " " or s ends with tab
		set s to text 1 thru -2 of s
	end repeat
	return s
end trim_ws

-- ============================================================================
-- SPLIT BY WHITESPACE
-- ============================================================================

on split_ws(s)
	set res to {}
	set wd to ""
	
	repeat with i from 1 to length of s
		set ch to character i of s
		if ch is " " or ch is tab then
			if wd is not "" then
				set end of res to wd
				set wd to ""
			end if
		else
			set wd to wd & ch
		end if
	end repeat
	
	if wd is not "" then
		set end of res to wd
	end if
	
	return res
end split_ws

-- ============================================================================
-- SPLIT BY COMMA
-- ============================================================================

on split_comma(s)
	set res to {}
	set prev to text item delimiters
	set text item delimiters to ","
	set items_list to text items of s
	set text item delimiters to prev
	
	repeat with item_val in items_list
		set item_val to trim_ws(item_val)
		if item_val is not "" then
			set end of res to item_val
		end if
	end repeat
	
	return res
end split_comma

-- ============================================================================
-- CSV LOG SAMPLE
-- ============================================================================

on csvLog(pid, nm, cpu)
	set cs to cmds of conf
	if (count of cs) = 0 then
		return
	end if
	
	set found to false
	repeat with c in cs
		if nm contains c then
			set found to true
			exit repeat
		end if
	end repeat
	
	if not found then
		return
	end if
	
	set rec to {ts:getTimestamp(), pid:pid, nm:nm, cpu:cpu}
	set end of csvBuf to rec
end csvLog

-- ============================================================================
-- CSV FLUSH
-- ============================================================================

on csvFlush()
	if (count of csvBuf) = 0 then
		return
	end if
	
	printDbg("Flush " & (count of csvBuf) & " records")
	
	-- Group records by filename
	set fileDict to {}
	
	repeat with rec in csvBuf
		set procN to nm of rec
		set pref to text 1 thru 10 of procN
		set fn to sanitizeFn(pref)
		set d to dir of conf
		set fp to d & "/" & fn & ".csv"
		
		-- Find or create file entry
		set fileFound to false
		repeat with idx from 1 to count of fileDict
			set entry to item idx of fileDict
			if (filepath of entry) = fp then
				set fileFound to true
				set recs to records of entry
				set end of recs to rec
				set item idx of fileDict to {filepath:fp, records:recs}
				exit repeat
			end if
		end repeat
		
		if not fileFound then
			set end of fileDict to {filepath:fp, records:{rec}}
		end if
	end repeat
	
	-- Write all files
	repeat with entry in fileDict
		set fp to filepath of entry
		set rs to records of entry
		set nhdr to not (fileExist(fp))
		writeCsv(fp, rs, nhdr)
	end repeat
	
	set csvBuf to {}
	set lastFlush to current date
end csvFlush

-- ============================================================================
-- FILE EXIST
-- ============================================================================

on fileExist(fp)
	try
		POSIX file fp as alias
		return true
	on error
		return false
	end try
end fileExist

-- ============================================================================
-- SANITIZE FILENAME
-- ============================================================================

on sanitizeFn(n)
	set n to n as string
	set n to replace_tx(n, " ", "_")
	set n to replace_tx(n, "/", "_")
	set n to replace_tx(n, ":", "_")
	return n
end sanitizeFn

-- ============================================================================
-- REPLACE TEXT
-- ============================================================================

on replace_tx(s, old, new)
	set s to s as string
	set prev to text item delimiters
	set text item delimiters to old
	set s to text items of s
	set text item delimiters to new
	set s to s as string
	set text item delimiters to prev
	return s
end replace_tx

-- ============================================================================
-- WRITE CSV
-- ============================================================================

on writeCsv(fp, rs, nhdr)
	try
		-- Extract directory from path
		set last_slash to length of fp
		repeat while last_slash > 0
			if character last_slash of fp is "/" then
				exit repeat
			end if
			set last_slash to last_slash - 1
		end repeat
		
		if last_slash > 0 then
			set dir_path to text 1 thru last_slash of fp
			do shell script "mkdir -p " & quoted form of dir_path
		end if
		
		-- Use shell to append CSV data
		repeat with rec in rs
			set ln to (ts of rec) & "," & (pid of rec) & "," & (nm of rec) & "," & (cpu of rec)
			
			if nhdr then
				-- First record - write header plus data
				do shell script "echo 'timestamp,PID,command,CPU%' > " & quoted form of fp
				do shell script "echo " & quoted form of ln & " >> " & quoted form of fp
				set nhdr to false
			else
				-- Append subsequent records
				do shell script "echo " & quoted form of ln & " >> " & quoted form of fp
			end if
		end repeat
		
	on error err
		printDbg("CSV error: " & err)
	end try
end writeCsv

-- ============================================================================
-- SEND NOTIFICATION
-- ============================================================================

on notify(nm, pid, cpu)
	set msg to "High CPU: " & nm & " (PID " & pid & ") - " & cpu & "%"
	try
		display notification msg with title "CPU Monitor"
	on error
		log "NOTIFY: " & msg
	end try
end notify

-- ============================================================================
-- PARSE ARGS
-- ============================================================================

on parseArgs(argv)
	set conf to {thresh:DEF_THRESH, inter:DEF_INTER, cnt:DEF_COUNT, dir:DEF_DIR, cmds:{}, dbg:false, help_req:false, ver_req:false}
	
	set i to 1
	repeat while i <= count of argv
		set arg to ((item i of argv) as string)
		
		if arg = "--threshold" then
			if i + 1 <= count of argv then
				try
					set v to ((item (i + 1) of argv) as integer)
					if v < 1 or v > 100 then
						log "Error: threshold 1-100"
						set shouldExit to true
						return
					end if
					set thresh of conf to v
					set i to i + 2
				on error
					log "Error: bad threshold"
					set shouldExit to true
					return
				end try
			else
				log "Error: --threshold needs arg"
				set shouldExit to true
				return
			end if
			
		else if arg = "--interval" then
			if i + 1 <= count of argv then
				try
					set v to ((item (i + 1) of argv) as integer)
					if v < 3 then
						log "Error: interval >= 3"
						set shouldExit to true
						return
					end if
					set inter of conf to v
					set i to i + 2
				on error
					log "Error: bad interval"
					set shouldExit to true
					return
				end try
			else
				log "Error: --interval needs arg"
				set shouldExit to true
				return
			end if
			
		else if arg = "--check-count" then
			if i + 1 <= count of argv then
				try
					set v to ((item (i + 1) of argv) as integer)
					if v < 1 then
						log "Error: check-count >= 1"
						set shouldExit to true
						return
					end if
					set cnt of conf to v
					set i to i + 2
				on error
					log "Error: bad check-count"
					set shouldExit to true
					return
				end try
			else
				log "Error: --check-count needs arg"
				set shouldExit to true
				return
			end if
			
		else if arg = "--csv-commands" then
			if i + 1 <= count of argv then
				set cs to ((item (i + 1) of argv) as string)
				set cmds of conf to split_comma(cs)
				set i to i + 2
			else
				log "Error: --csv-commands needs arg"
				set shouldExit to true
				return
			end if
			
		else if arg = "--csv-dir" then
			if i + 1 <= count of argv then
				set dir of conf to ((item (i + 1) of argv) as string)
				set i to i + 2
			else
				log "Error: --csv-dir needs arg"
				set shouldExit to true
				return
			end if
			
		else if arg = "--debug" then
			set dbg of conf to true
			set i to i + 1
			
		else if arg = "--help" or arg = "-h" then
			set help_req of conf to true
			set i to i + 1
			
		else if arg = "--version" or arg = "-v" then
			set ver_req of conf to true
			set i to i + 1
			
		else
			set i to i + 1
		end if
	end repeat
end parseArgs

-- ============================================================================
-- PRINT HELP
-- ============================================================================

on printHelp()
	set txt to "CPU Monitor - AppleScript Edition v" & VERSION & "

USAGE:
  cpu-monitor-as [OPTIONS]

OPTIONS:
  --threshold PERCENT     CPU threshold (default: " & DEF_THRESH & ", range: 1-100)
  --interval SECONDS      Sampling interval (default: " & DEF_INTER & ", min: 3)
  --check-count N         Consecutive samples (default: " & DEF_COUNT & ", min: 1)
  --csv-commands NAME,... Processes to log to CSV
  --csv-dir PATH          CSV output directory (default: current directory)
  --debug                 Enable debug output
  --help, -h              Show this help
  --version, -v           Show version

EXAMPLES:
  cpu-monitor-as --threshold 50 --interval 30
  cpu-monitor-as --threshold 75 --check-count 2 --csv-commands node,python
  cpu-monitor-as --debug --threshold 0 --check-count 1 --interval 5

No sudo needed for most user processes.
"
	log txt
end printHelp

-- ============================================================================
-- PRINT VERSION
-- ============================================================================

on printVers()
	log "cpu-monitor-as version " & VERSION
end printVers

-- ============================================================================
-- MAIN LOOP
-- ============================================================================

on runLoop()
	set lastPid to -1
	set countConsec to 0
	set lastFlush to current date
	set shouldExit to false
	
	printDbg("Started")
	printDbg("Thresh: " & (thresh of conf) & "% | Interval: " & (inter of conf) & "s | Count: " & (cnt of conf))
	
	repeat until shouldExit
		set sample to getTopProcess()
		
		printDbg("Sample: PID=" & (pid of sample) & " Name=" & (name of sample) & " CPU%=" & (cpu of sample))
		
		if (pid of sample) ≠ lastPid then
			if (cpu of sample) >= (thresh of conf) then
				set countConsec to 1
			else
				set countConsec to 0
			end if
			set lastPid to pid of sample
		else
			if (cpu of sample) >= (thresh of conf) then
				set countConsec to countConsec + 1
			else
				set countConsec to 0
			end if
		end if
		
		printDbg("Counter: " & countConsec & " / " & (cnt of conf) & " thresh=" & (thresh of conf))
		
		if countConsec >= (cnt of conf) then
			printDbg("Alert: " & (name of sample) & " pid=" & (pid of sample) & " cpu=" & (cpu of sample))
			notify((name of sample), (pid of sample), (cpu of sample))
			set countConsec to 0
		end if
		
		csvLog((pid of sample), (name of sample), (cpu of sample))
		
		set elapsed to (current date) - lastFlush
		if elapsed >= FLUSH_SEC then
			csvFlush()
		end if
		
		delay (inter of conf)
	end repeat
	
	csvFlush()
end runLoop

-- ============================================================================
-- ENTRY
-- ============================================================================

on run argv
	init_all()
	parseArgs(argv)
	
	if help_req of conf then
		printHelp()
		return
	end if
	
	if ver_req of conf then
		printVers()
		return
	end if
	
	if not shouldExit then
		runLoop()
	end if
end run
