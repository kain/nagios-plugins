'********************************************************************
'* Author:		Thomas Rechberger
'* Version:		1.0 12/2013 initial version
'*     			1.1 01/2014 updated smart attribute alarm values
'*			1.2 01/2014 bugfix wrong alarm, improved id detection
'*			1.3 01/2014 removed hex values (were also wrong i.e. 1 was used instead 01)
'*			1.4 02/2014 changed ID181,200 alarm settings because samsung disks use high raw values here - added alarm for 17x values
'*			1.5 03/2014 fix output for multiple devices, better ssd support (ssd are whole different picture than hdd and more difficult to interpret)
'*			1.6 04/2014 minor changes
'* Description:	Check for SMART attributes, temperature and health on harddisks (meant for servers).
'*		The script doesnt work with drives in sleep state, dont know how to wake them.
'*		You can run the script also outside nagios with cscript.exe check_smartwmi.vbs
'*		Alarm thresholds are set relatively strict, if you get false alarms please report to:
'*		http://exchange.nagios.org/directory/Plugins/Operating-Systems/Windows/NRPE/check_smartwmi-SMART-Monitoring-for-Windows-by-using-builtin-WMI/details
'*		see also: http://en.wikipedia.org/wiki/S.M.A.R.T.
'* Module Name: check_smartwmi.vbs 
'* Arguments:   optional temperature monitoring with warning and critical threshold, example: /warn:40 /crit:50
'*		power on hours in seconds or minutes for some models: /poh:min or /poh:sec (valid for all found disks!)
'* License	    GNU free license, no warranties
'********************************************************************
'info: smart is storing in 6x8bit fields = 48bit, but wmi stores only 5x8bit

'*** user section ***
olddisk = 30000 'age in hours when the disk is considered to be old and prone to errors, a warning will then be generated. more suited for hdd
hddhealthcalc = "restricted" 'use restricted or standard for hdd health calculation, restricted takes defective sectors better in account according to disk sentinel
nagios = 1 'will change the message output to a shorter way because Nagios cannot display long text, disable if you dont use Nagios
'*** end user section ***

Err.Clear

'Constant declaration for Nagios
CONST Exit_OK = 0
CONST Exit_Warning = 1
CONST Exit_Critical = 2
CONST Exit_Unknown = 3

'set these values because they are used also outside the sub
poh = 0
temperature = 0
sumattrcriterror = 0
tempcriterror = 0
tempwarnerror = 0
healtherror = 0
predicterror = 0

'these regex patterns are to be searched later and have exclusions
'ssd have exclusion on id 5,171,172,181,182,196 and ssd will be detected based on id 202,231,233 as there is no easy way to read rotational speeds
Set objRegExpCrucialM500 = New RegExp 'currently not used
objRegExpCrucialM500.Pattern = "Crucial_CT\d+M50"
Set objRegExpSeagate = New RegExp 'used for making id1,7 raw read errors not critical (saw also 180,195 increasing steadily)
objRegExpSeagate.Pattern = "Seagate"
Set objRegExpIntel = New RegExp 'used for calculation of disk writes
objRegExpIntel.Pattern = "Intel"

'description for attributes
Dim arrIDdesc(254)
	arrIDdesc(1) = "Raw Read/Seek Error Rate      " 'some vendors use high raw values here on a new disc i.e. seagate - fujitsu is using only 2 fields
	arrIDdesc(2) = "Throughput Performance        " 'fujitsu is using only 2 fields
	arrIDdesc(3) = "Spin-Up Time in ms            " 'stores in only 2 fields, the other 2 are for average, the last one is unknown
	arrIDdesc(4) = "Start/Stop Count              "
	arrIDdesc(5) = "Reallocated Sector/NAND Count " 'critical, fujitsu uses other fields for something else (hidden remaps?), should be 0 anyway - for ssd values are increasing over time
	arrIDdesc(7) = "Seek Error Rate               " 'fujitsu seems to use less fields here
	arrIDdesc(8) = "Seek Time Performance         "
	arrIDdesc(9) = "Power-On Hours                "
	arrIDdesc(10) = "Spin Retry Count             " 'critical
	arrIDdesc(11) = "Recalibration Retries        "
	arrIDdesc(12) = "Power Cycle Count            "
	arrIDdesc(13) = "Soft Read Error Rate         "
	arrIDdesc(100) = "Gigabytes Erased            "
	arrIDdesc(170) = "Reserve Block Count         " 'on ssd value is decremeted as the reserve block count dimishes over drive life
	arrIDdesc(171) = "SSD Program Fail Count      "
	arrIDdesc(172) = "SSD Erase Fail Count        "
	arrIDdesc(173) = "SSD Block Erase Count       "
	arrIDdesc(174) = "Unexpected Power Loss       "
	arrIDdesc(175) = "Program Fail Count Chip     "
	arrIDdesc(176) = "Erase Fail Count Chip       "
	arrIDdesc(177) = "Wear Leveling Count         "
	arrIDdesc(179) = "Used Reserved Block Count   " 'used by SSD, normalized value is important
	arrIDdesc(180) = "Unused Reserved Block Count " 'reserve blocks that are available
	arrIDdesc(181) = "Progr Fail Count/4k non Alig"
	arrIDdesc(182) = "Erase Fail Count            "
	arrIDdesc(183) = "SATA Downshift Error        "
	arrIDdesc(184) = "Error Correction Count      "
	arrIDdesc(187) = "Uncorrectable Error         "
	arrIDdesc(188) = "Command Timeout             " 'seen high raw values on seagate discs in smartctl with normal thresholds, maybe only 2 fields are used
	arrIDdesc(189) = "High Fly Writes             "
	arrIDdesc(190) = "Temperature Airflow         "
	arrIDdesc(191) = "G-Sense Error Rate          "
	arrIDdesc(192) = "Unsafe Shutdown Count       "
	arrIDdesc(193) = "Load Cycle Count            "
	arrIDdesc(194) = "Temperature                 " 'only one field is used
	arrIDdesc(195) = "Hardware ECC Recovered      " 'uses more than 2 fields.  The raw value has different structure for different vendors and is often not meaningful as a decimal number.
	arrIDdesc(196) = "Reallocated Event Count     " 'critical, fujitsu uses other fields for something else, so dont use all fields together, crucial ssd can have value >0 here
	arrIDdesc(197) = "Current Pending Sector Count" 'critical
	arrIDdesc(198) = "Uncorrectable Sector Count  " 'critical
	arrIDdesc(199) = "UltraDMA CRC Error Count    " 'critical, mostly cable problems that should not happen
	arrIDdesc(200) = "Multi-Zone Error Rate       " 'critical, uses more than 2 fields
	arrIDdesc(201) = "Soft Read Error Rate        "
	arrIDdesc(202) = "Percent Lifetime Remaining  "
	arrIDdesc(203) = "Run Out Cancel              "
	arrIDdesc(204) = "Soft ECC Correction Rate    "
	arrIDdesc(205) = "Thermal Asperity Rate       "
	arrIDdesc(206) = "Write Error Rate            "
	arrIDdesc(207) = "ID207 Spin Buzz             "
	arrIDdesc(210) = "Successf RAIN Recovery Count"
	arrIDdesc(211) = "Vibration During Write      "
	arrIDdesc(212) = "Shock During Write          "
	arrIDdesc(220) = "Disk Shift                  "
	arrIDdesc(223) = "Count head changes position "
	arrIDdesc(224) = "Load Friction               "
	arrIDdesc(225) = "Load Cycle Count/Host Writes"
	arrIDdesc(226) = "Timed Workload Media Wear   "
	arrIDdesc(227) = "Timed Workload R/W Ratio    "
	arrIDdesc(228) = "Workload Timer              "
	arrIDdesc(230) = "Drive Live Protection Status"
	arrIDdesc(231) = "SSD Life Left               "
	arrIDdesc(232) = "Avail. Reserved Space in G  "
	arrIDdesc(233) = "Media Wearout Indicator     "
	arrIDdesc(235) = "Power Fail Backup Health    "
	arrIDdesc(241) = "Total LBAs Written (GiB)    "
	arrIDdesc(242) = "Total LBAs Read (GiB)       "
	arrIDdesc(246) = "Total Host Sector Writes    "
	arrIDdesc(247) = "CONTACT FACTORY             "
	arrIDdesc(248) = "CONTACT FACTORY             "
	arrIDdesc(250) = "Read Error Retry Rate       "
	arrIDdesc(254) = "Free Fall Protection        "
	
	
'get arguments
Set colNamedArguments = WScript.Arguments.Named
tempwarnarg = CInt(colNamedArguments.Item("warn"))
tempcritarg = CInt(colNamedArguments.Item("crit"))
poharg = CInt(colNamedArguments.Item("poh"))

strComputer = "."
set wbemServices = GetObject("winmgmts:\\" & strComputer & "\root\wmi")
set wbemObjectSetVendor = wbemServices.InstancesOf("MSStorageDriver_ATAPISmartData")
set wbemObjectSetPredict = wbemServices.InstancesOf("MSStorageDriver_FailurePredictStatus")

getvendorspecific()
getfailurepredict()

'generate exit codes and messages for Nagios Monitoring
if nagios = 1 then
	if ((predicterror > 0) OR (tempcriterror > 0) OR (sumattrcriterror > 0) OR (healtherror > 0)) then
		Wscript.Echo "CRITICAL (# of discs): Predicted Errors " & predicterror & " Health Errors " & healtherror & " Attribute Errors " & sumattrcriterror & " Temp Errors " & tempcriterror
		Wscript.Quit(Exit_Critical)
	elseif ((tempwarnerror > 0) OR (agewarnerror > 0)) then
		Wscript.Echo "WARNING (# of discs): Temp Errors " & tempwarnerror & " Age Errors " & agewarnerror
		Wscript.Quit(Exit_Warning)
	elseif ((poh = 0) AND (temperature = 0)) then 'if still matches we have not read any device yet
		Wscript.Echo "UNKNOWN: Cannot get any Smart values"
		Wscript.Quit(Exit_Unknown)
	elseif ((predicterror = 0) AND (agewarnerror = 0) AND (tempwarnerror = 0) AND (tempcriterror = 0) AND (attrcriterror = 0)) then
		Wscript.Echo "OK: All disks are OK"
		Wscript.Quit(Exit_OK)
	End If
End If

'MSStorageDriver_FailurePredictStatus 				
sub getfailurepredict()
  For Each wbemObject in wbemObjectSetPredict
	if wbemObject.PredictFailure = True then
		predicterror = predicterror + 1
		WScript.Echo vbcrlf & "Critical: Smart Predicted Failure on Disk " & wbemObject.Instancename & " with Reason " & wbemObject.Reason
	End If
  Next
end sub

'MSStorageDriver_ATAPISmartData
sub getvendorspecific()
  For Each wbemObject In wbemObjectSetVendor
     
	 
     	WScript.Echo "Disk : " & wbemObject.InstanceName 
     
	if not nagios = 1 then
		WScript.Echo "ID" & vbTab & "Description                    " & vbTab & "Actual" & vbTab & "Worst" & vbTab & "Data"
	End If
	
	'reset parameters (for next runs)
	poh = 0
	temperature = 0
	attrcriterror = 0
	hddattrcriterror = 0
	lbawrite = 0
	softreaderror = 0
	dmacrcerror = 0
	uncorrectablesectors = 0
	pendingsectors = 0
	reallocationevent = 0 
	commandtimeout = 0
	endtoend = 0
	erasefailcount2 = 0
	erasefailcount = 0
	programfailcount = 0
	programfailcount2 = 0
	spinretry = 0
	reallocatedsectors = 0
	rawreaderror = 0
	seekerror = 0
	reserveblocks = 0
	remainblocksperc = ""
	lifetimeremain = 0

	 
     arrVendorSpecific = wbemObject.VendorSpecific
	 
     for i=0 to 359 '362 in total but not all are used
		 
		if ((arrVendorSpecific(i) = 0) OR (arrVendorSpecific(i) = 16)) then 'field is 0 or 16? (only first row uses 16)
			i2 = i+1
			
			if arrVendorSpecific(i2) = 0 then 'next field is also zero?
				i3 = i2+1 'get 3rd column where smart id is stored
				i6 = i2+4 'get 6th column where actual normalized data is stored
				i7 = i2+5 'get 7th column where worst normalized data is stored
				i8 = i2+6 'get 8th column where raw value is stored as decimal
				i9 = i2+7 'get 9th column where raw value is stored as decimal
				i10 = i2+8 'get 10th column where raw value is stored as decimal
				i11 = i2+9 '11th column
				i12 = i2+10 '12th column	
				
				'attributes may have different ways of calculation
				Select Case arrVendorSpecific(i3)
					Case 4,9,193,195,200,225,241,242,246 'for those attributes where values up to 65k is not enough
						vendec = arrVendorSpecific(i12) * (16^8) + arrVendorSpecific(i11) * (16^6) + arrVendorSpecific(i10) * (16^4) + arrVendorSpecific(i9) * (16^2) + arrVendorSpecific(i8) 
					Case 194 'temperature is using only one field
						vendec = arrVendorSpecific(i8)
					Case Else 'some attributes like id3 are using only 2 fields, other fields may display average or other things
						vendec = arrVendorSpecific(i9) * (16^2) + arrVendorSpecific(i8) 
				End Select
				
				'output lines
				if not nagios = 1 then
					for idcounter=1 to 254
						if arrVendorSpecific(i3) = idcounter then
							WScript.Echo idcounter & vbTab & arrIDdesc(idcounter) & vbTab & arrVendorSpecific(i6) & vbTab & arrVendorSpecific(i7) & vbTab & vendec
						End If
					next
				End If
				
				'set alarm if needed
				if arrVendorSpecific(i3) = 1 then
					'some vendors use high raw values here on a new disc i.e. seagate
					'fujitsu is using only 2 fields
					rawreaderror = vendec
					'if not ((rawreaderror = 0) AND (objRegExpSeagate.Test(wbemObject.InstanceName))) then 'exception for seagate
					'	hddattrcriterror = hddattrcriterror + 1
					'End If	
		
					if ((arrVendorSpecific(i6) <= 50) OR (arrVendorSpecific(i7) <= 50)) then
						attrcriterror = attrcriterror + 1
					End if

				elseif arrVendorSpecific(i3) = 3 then
					'stores in only 2 fields, the other 2 are for average, the last one is unknown
					spinavg = arrVendorSpecific(i11) * (16^2) + arrVendorSpecific(i10)
					if ((arrVendorSpecific(i6) <= 50) OR (arrVendorSpecific(i7) <= 50)) then
						attrcriterror = attrcriterror + 1
					End if					
				
				elseif arrVendorSpecific(i3) = 5 then
					'Count of reallocated sectors. When the hard drive finds a read/write/verification error, it marks that sector as "reallocated" and transfers data to a special reserved area (spare area).
					'a brand new disc has already reallocated sectors which are not shown, so this value shouldnt really not increase because also the reserved area has a very limited amount of space.
					'fujitsu uses other fields for something else (hidden remaps?), should be 0 anyway - ssd use higher values and indicate as failed flash memory blocks
					'on ssd this value increase as it ages
					reallocatedsectors = vendec
					if reallocatedsectors > 0 then
						hddattrcriterror = hddattrcriterror + 1
					End If
					if ((arrVendorSpecific(i6) <= 10) OR (arrVendorSpecific(i7) <= 10)) then
						attrcriterror = attrcriterror + 1
					End if
				elseif arrVendorSpecific(i3) = 7 then
					'fujitsu seems to use less fields here
					'The raw value has different structure for different vendors and is often not meaningful as a decimal number.
					seekerror = vendec
					'if not ((seekerror = 0) AND (objRegExpSeagate.Test(wbemObject.InstanceName))) then 'exception for seagate
					'	hddattrcriterror = hddattrcriterror + 1
					'End If
					
					if ((arrVendorSpecific(i6) <= 60) OR (arrVendorSpecific(i7) <= 60)) then
						attrcriterror = attrcriterror + 1
					End if
				elseif arrVendorSpecific(i3) = 9 then
					'some vendors use minutes or even seconds
					if poharg = "min" then
						poh = vendec / 60
					elseif poharg = "sec" then
						poh = vendec / 3600
					else
						poh = vendec
					End If
				elseif arrVendorSpecific(i3) = 10 then
					'Count of retry of spin start attempts. This attribute stores a total count of the spin start attempts to reach the fully operational speed 
					'(under the condition that the first attempt was unsuccessful). An increase of this attribute value is a sign of problems in the hard disk mechanical subsystem.
					spinretry = vendec
					if spinretry > 0 then
						attrcriterror = attrcriterror + 1
					End If
				elseif arrVendorSpecific(i3) = 170 then
					if ((arrVendorSpecific(i6) <= 10) OR (arrVendorSpecific(i7) <= 10)) then
						attrcriterror = attrcriterror + 1
					End if
					reserveblocks = vendec
				elseif arrVendorSpecific(i3) = 171 then
					'(Kingston)Counts the number of flash program failures. This Attribute returns the total number of Flash program operation failures since the drive was deployed. 
					'This attribute is identical to attribute 181.
					programfailcount = vendec
					if programfailcount > 0 then	
						hddattrcriterror = hddattrcriterror + 1
					End If
					if ((arrVendorSpecific(i6) <= 10) OR (arrVendorSpecific(i7) <= 10)) then
						attrcriterror = attrcriterror + 1
					End if
				elseif arrVendorSpecific(i3) = 172 then
					'(Kingston)Counts the number of flash erase failures. This Attribute returns the total number of Flash erase operation failures since the drive was deployed. 
					'This Attribute is identical to Attribute 182.
					erasefailcount = vendec
					if erasefailcount > 0 then
						hddattrcriterror = hddattrcriterror + 1
					End If
					if ((arrVendorSpecific(i6) <= 10) OR (arrVendorSpecific(i7) <= 10)) then
						attrcriterror = attrcriterror + 1
					End if
				elseif arrVendorSpecific(i3) = 173 then
					if ((arrVendorSpecific(i6) <= 10) OR (arrVendorSpecific(i7) <= 10)) then
						attrcriterror = attrcriterror + 1
					End if
				elseif arrVendorSpecific(i3) = 177 then
					if ((arrVendorSpecific(i6) <= 10) OR (arrVendorSpecific(i7) <= 10)) then
						attrcriterror = attrcriterror + 1
					End if
				elseif arrVendorSpecific(i3) = 179 then
					'ssd reserved blocks shows remaining reserve blocks in percent
					if ((arrVendorSpecific(i6) <= 10) OR (arrVendorSpecific(i7) <= 10)) then
						attrcriterror = attrcriterror + 1
					End if
				elseif arrVendorSpecific(i3) = 180 then
					'reserve blocks
					reserveblocks = vendec
				elseif arrVendorSpecific(i3) = 181 then
					'program fail count
					programfailcount2 = vendec
					if programfailcount2 > 0 then
						hddattrcriterror = hddattrcriterror + 1
					End If
					if ((arrVendorSpecific(i6) <= 10) OR (arrVendorSpecific(i7) <= 10)) then
						attrcriterror = attrcriterror + 1
					End if
				elseif arrVendorSpecific(i3) = 182 then
					'"Pre-Fail" Attribute used at least in Samsung devices.
					erasefailcount2 = vendec
					if erasefailcount2 > 0 then
						hddattrcriterror = hddattrcriterror + 1
					End if
					if ((arrVendorSpecific(i6) <= 10) OR (arrVendorSpecific(i7) <= 10)) then
						attrcriterror = attrcriterror + 1
					End if
				elseif arrVendorSpecific(i3) = 183 then
					'runtime bad block
					if ((arrVendorSpecific(i6) <= 10) OR (arrVendorSpecific(i7) <= 10)) then
						attrcriterror = attrcriterror + 1
					End if
				elseif arrVendorSpecific(i3) = 184 then
					'This attribute is a part of Hewlett-Packard's SMART IV technology, as well as part of other vendors' IO Error Detection and Correction schemas, 
					'and it contains a count of parity errors which occur in the data path to the media via the drive's cache RAM
					endtoend = vendec
					if endtoend > 0 then
						attrcriterror = attrcriterror + 1
					End if
					if ((arrVendorSpecific(i6) <= 50) OR (arrVendorSpecific(i7) <= 50)) then
						attrcriterror = attrcriterror + 1
					End if
				elseif arrVendorSpecific(i3) = 188 then
					'The count of aborted operations due to HDD timeout. Normally this attribute value should be equal to zero and if the value is far above zero, 
					'then most likely there will be some serious problems with power supply or an oxidized data cable.
					'seen high raw values on seagate discs in smartctl with normal thresholds, maybe only 2 fields are used
					commandtimeout = vendec
					if commandtimeout > 0 then
						attrcriterror = attrcriterror + 1
					End if
				elseif arrVendorSpecific(i3) = 194 then
				'temperature stores value only in one field
					temperature = vendec
					tempmax = arrVendorSpecific(i12)
					tempmin = arrVendorSpecific(i10)
				elseif arrVendorSpecific(i3) = 196 then
					'critical, fujitsu uses other fields for something else, so dont use all fields together
					'many crucial m500 use 16 as raw value. ssd have increasing values over time
					reallocationevent = vendec
					If reallocationevent > 0 then
						hddattrcriterror = hddattrcriterror + 1
					End If
				elseif arrVendorSpecific(i3) = 197 then
					'critical value
					pendingsectors = vendec
					If pendingsectors > 0 then
						attrcriterror = attrcriterror + 1
					End If
				elseif arrVendorSpecific(i3) = 198 then
					'critical value
					uncorrectablesectors = vendec
					If uncorrectablesectors > 0 then
						attrcriterror = attrcriterror + 1
					End If
				elseif arrVendorSpecific(i3) = 199 then
					'mostly cable problems that should not happen
					dmacrcerror = vendec
					If dmacrcerror > 0 then
						attrcriterror = attrcriterror + 1
					End If
				elseif arrVendorSpecific(i3) = 200 then
					'the count of errors found when writing a sector. The higher the value, the worse the disk's mechanical condition is.
					'uses more than 2 fields
					if ((arrVendorSpecific(i6) <= 99) OR (arrVendorSpecific(i7) <= 99)) then
						attrcriterror = attrcriterror + 1
					End if
				elseif arrVendorSpecific(i3) = 201 then
					'Count of off-track errors.
					softreaderror = vendec
					If softreaderror > 0 then
						attrcriterror = attrcriterror + 1
					End If
				elseif arrVendorSpecific(i3) = 202 then
					'lifetime remaining in % on crucial ssd
					lifetimeremain = arrVendorSpecific(i6)
					if ((arrVendorSpecific(i6) <= 10) OR (arrVendorSpecific(i7) <= 10)) then
						attrcriterror = attrcriterror + 1
					End if
				elseif arrVendorSpecific(i3) = 225 then
					lbawrite = vendec
				elseif arrVendorSpecific(i3) = 226 then
					'media war, value is remaining life in percent
					if ((arrVendorSpecific(i6) <=10) OR (arrVendorSpecific(i7) <= 10)) then
						attrcriterror = attrcriterror + 1
					End if
				elseif arrVendorSpecific(i3) = 230 then
					'drive life protection status kingston
					if arrVendorSpecific(i7) <= 90 then
						attrcriterror = attrcriterror + 1
					End if
				elseif arrVendorSpecific(i3) = 231 then
					'Indicates the approximate SSD life left, in terms of program/erase cycles or Flash blocks currently available for use
					lifetimeremain = arrVendorSpecific(i6)
					if ((arrVendorSpecific(i6) <=10) OR (arrVendorSpecific(i7) <= 10)) then
						attrcriterror = attrcriterror + 1
					End if
				elseif arrVendorSpecific(i3) = 232 then
					'Available reserved space SSD
					if ((arrVendorSpecific(i6) <=10) OR (arrVendorSpecific(i7) <= 10)) then
						attrcriterror = attrcriterror + 1
					End if
				elseif arrVendorSpecific(i3) = 233 then
					'ssd wearout indicator
					lifetimeremain = arrVendorSpecific(i6)
					if ((arrVendorSpecific(i6) <=10) OR (arrVendorSpecific(i7) <= 10)) then
						attrcriterror = attrcriterror + 1
					End if
				elseif arrVendorSpecific(i3) = 241 then
					'Total count of LBAs written
					lbawrite = vendec
				elseif arrVendorSpecific(i3) = 246 then
					'Total count of LBAs written
					lbawrite = vendec

				End If	
				
			End If
		End If     
		i=i+11 'goto next smart row
	next
	
	'calculate health with restrict option out of: id1 (weight 2),id5 (weight 6),10 (weight 6),196 (weight 4),197 (weight 4),198 (weight6)
	'standard calculation: id1 (weight 0,5), id5 (weight 1), 10 (weight 3), 196 (weight 0,6), 197 (weight 0,6), 198 (weight 1)
	if lifetimeremain = 0 then 'dirty way of how to detect hdd
		if hddhealthcalc = "restricted" then
			health = 100 * (100 - reallocatedsectors * 6) * (100 - rawreaderror * 2) * (100 - spinretry * 6) * (100 - reallocationevent * 4) * (100 - pendingsectors * 4) * (100 - uncorrectablesectors * 6) / 10^12
		elseif hddhealthcalc = "standard" then
			health = 100 * (100 - reallocatedsectors * 1) * (100 - rawreaderror * 0.5) * (100 - spinretry * 3) * (100 - reallocationevent * 0.6) * (100 - pendingsectors * 0.6) * (100 - uncorrectablesectors * 1) / 10^12
		End If 
	
		if health <= 99 then
			WScript.Echo "Critical: HDD Device health is " & health & "%."
			healtherror = healtherror + 1
		else
			WScript.Echo "HDD Device health is " & health & "%."
		End If
	End If

	'Calculate SSD health based on remaining sectors id170,id180
	if not lifetimeremain = 0 then 'dirty way of how to detect ssd
		If reserveblocks > 0 and reallocatedsectors >= 0 then	
			remainblocksperc = 100 * reserveblocks / (reserveblocks + reallocatedsectors)
		
			If remainblocksperc <= 10 then
				WScript.Echo "Critical: SSD remaining reserve blocks " & remainblocksperc & "%."
				healtherror = healtherror + 1
			else
				WScript.Echo "SSD remaining reserve blocks " & remainblocksperc & "%."
			End If
		End If
	End If
	
	'Print if there were critical smart attributes
	if not nagios = 1 then
		if lifetimeremain > 0 then 'detect ssd
			if attrcriterror > 0 then
				WScript.Echo "Critical: Device is reporting a problem on Smart Attribute(s)."
				sumattrcriterror = sumattrcriterror + 1
			End If
		else
			if attrcriterror > 0 or hddcriterror > 0 then
				WScript.Echo "Critical: Device is reporting a problem on Smart Attribute(s)."
				sumattrcriterror = sumattrcriterror + 1
			End If
		End If
	End If
	
	'check if disk is of old age
	if poh > olddisk then
		if not nagios = 1 then
			WScript.Echo "Warning: Old age (please verify, some vendors use minutes or seconds instead hours)."
		End If
		agewarnerror = agewarnerror + 1
	End If

	if not nagios = 1 then
		'display written GiB for SSDs
		if lbawrite > 0 then
			If objRegExpIntel.Test(wbemObject.InstanceName) then
				lbawritecalc = lbawrite * 32 / 1024
				WScript.Echo "Writes to Disk " & lbawritecalc & " GiB (32MiB units)."
			else
				lbawritecalc = CInt(lbawrite * 512 / (1024 ^ 3))
				WScript.Echo "Writes to Disk " & lbawritecalc & " GiB (512byte sector count convert)."
			End If
			
		End If
	
		
	End If
	
	'check if temperature is ok
	if ((temperature > tempcritarg) AND (tempcritarg <> 0)) then
		if not nagios = 1 then
			WScript.Echo "Critical: Temperature " & temperature & "C is above critical limit of " & tempcritarg & "C. (Max/Min " & tempmax & "/" & tempmin & ")"
		End If
		tempcriterror = tempcriterror + 1
	elseif ((temperature > tempwarnarg) AND (tempwarnarg <> 0)) then
		if not nagios = 1 then
		WScript.Echo "Warning: Temperature " & temperature & "C is above warning limit of " & tempwarnarg & "C. (Max/Min " & tempmax & "/" & tempmin & ")"
		End If
		tempwarnerror = tempwarnerror + 1
	elseif ((tempwarnarg <> 0) OR (tempcritarg <> 0)) then 'if limits were given but there is no alarm
		if not nagios = 1 then
		WScript.Echo "Temperature " & temperature & "C is within bounds. (Max/Min " & tempmax & "/" & tempmin & ")"
		End If
	else
		if not nagios = 1 then 'if no limits given, just show temperature
		WScript.Echo "Temperature is " & temperature & "C. (Max/Min " & tempmax & "/" & tempmin & ")"
		End if
	End If

	'display average spin time
	if spinavg > 0 and not nagios = 1 then
		WScript.Echo "Average spin time is " & spinavg & "ms."
	End If
	 
  Next
  
  
end sub
