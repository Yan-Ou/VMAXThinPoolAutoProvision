
# Automatic Thin Pool Managment (APM) Script
"New Run"

#Debug level
#1=console
#2=logfile
#3=email
$dub = 1
$dub_email = "" # Recepient's email 
$sp = "d:\scripts\APM" 
$lp = "d:\scripts\APM\LOG\"
$commitment= "commit" #"commit" #commit or prepare (debug) on symcli commands

$now = Get-Date
[string]$timestamp = [string]$now.Year + [string]$now.Month.ToString("00") + [string]$now.Day.ToString("00") + "_" + [string]$now.Hour.ToString("00") + [string]$now.Minute.ToString("00") + [string]$now.Second.ToString("00")
[string]$logfile = [string]$now.Year + [string]$now.Month.ToString("00") + [string]$now.Day.ToString("00") + "log.txt"
$logfile = $lp + $logfile


function log ([string]$message,[array]$logarray) 
{
"LOG: " + $message
if( $logarray.length -gt 0){
	write-host $logarray
}
$message | Out-File -FilePath $logfile -Append
$logarray | Out-File -FilePath $logfile -Append
}

log ("`r`r`r########################### New run " + $timestamp + "###########################`r`r`r")


#Watermarks
$highmark = 92
$lowmark = 89

$max_tdats_remove = 10 #only remove this many at a time

#Find system ID
#$sid = 72
$system = cmd /c "symcfg list" | select-string "Local"
$system = $system.tostring().trim() -split("\s+")
$sid = $system[0].trim("0")

#Identify pools
$pool_list = @()
#$pool_list_raw = (Get-Content $sp\pool_details.txt  | select-string "_SATA_0|_FC_0" )
log "Pool list raw" $pool_list_raw
$pool_list_raw = cmd /c "symcfg -sid $sid list -pool -thin -gb -detail" | select-string "_SATA_0|_FC_0"
log "pool_list_raw" $pool_list_raw
$pool_list_raw | %{ $pool_elements = $_.tostring().trim() -split("\s+")
					$pool_list += ,$pool_elements[0]}

log "We will attempt to manage the following pools" $pool_list

#$pool_name = "MEL2_SATA_01"
#log($pool_name)

$pool_list | foreach {
	
##############
#For each pool
	#Obtain a list of current TDATs and 
	#load them into an array ($se)
	$pool_name = $_
	log "We are checking the following pool: " $pool_name
	#$get_pool = get-content $sp\show_pool_01.txt 
	$get_pool = cmd /c "symcfg show -sid $sid -pool $pool_name -thin"
	$pools = $get_pool | Select-String "Enabled           $"
	#Pool utilization is found on last track list, we need to get from pool_list_raw
	$pool_sum = $get_pool | select-string "   Tracks"

	$tot_dev_pool = (( $get_pool | select-string "of Devices in Pool").tostring() -split("\s+"))[-1]
	$enb_dev_pool = (( $get_pool | select-string "Enabled Devices in Pool").tostring() -split("\s+"))[-1]
	log ("Total devices in pool " + $tot_dev_pool)
	log ("Total enabled devices in pool " + $enb_dev_pool)

	$se=@()
	$pools | foreach{ $elements=$_.tostring().trim() -split("\s+") 
	$se+= ,@($elements)}

	#Check current utilization
	#find current pool utilization from $pool_utils
	$pool_sum | %{$pool_sums=$_.tostring().trim() -split("\s+")}
	#Pool Utilization
	$pool_util = ($pool_list_raw | Select-String $pool_name | %{$_ -split("\s+")})[7]
	$pool_usable_trc = $pool_sums[1]
	$pool_used_trc = $pool_sums[3]
	$pool_tdats = $se.length
	$pool_tdat_trcs = $se[0][1]
	$tdats_being_removed = $tot_dev_pool - $enb_dev_pool
	$tdats_added=$false

	#We should do a lot of checks here..


	#TESTTESTTESTTESTTEST
	$some_check = $se[-2]-contains 55
	write-host $se.length $pool_util $se[-1][4] $pool_used_trc $pool_tdat_trcs


#If higher than water watermark, attempt to add
	if($pool_util -gt $highmark ){
	#Calculate how many TDATs we need to add to reach max mark
	$tdat_max = [Math]::round(($pool_used_trc/($highmark*$pool_tdat_trcs))*100  )
	$tdat_max
	#$tdat_add = ($pool_used_trc*100/($highmark*$pool_tdat_trcs))
	$tdats_to_add = ($tdat_max - $pool_tdats)
	log ("TDATs needed to be added to pool " + $pool_name + " " + $tdats_to_add)
	
	#if I still need more TDATS
	if($tdats_to_add -gt 0){
		$raw_tdats = (get-content $sp\$pool_name.csv)
		$te=@()
		$raw_tdats | foreach{ $elements=$_.tostring().trim() -split(",")
		$hash = [int]$elements[1]*10000000 + [int]$elements[2]*1000000 + [int]$elements[3]*100000 + ("0x" + $elements[0])
		$elements += ,$hash
		$te+= ,@($elements)}
		$te = $te | Sort-Object  @{Expression={$_[4]}; Descending=$false  } #| %{$_[0] + " " + $_[4]}
		$n=0
		$m=0
		$re=@()		
		#Load list to compare with disabled/draining devices
		if($tdats_being_removed -gt 0){
			#$disabled_tdats = (Get-Content $sp\show_pool_01_detail.txt | Select-String ".  Disabled|.  Draining"  )
			$disabled_tdats = (cmd /c "Symcfg show -pool $pool_name -thin -all -sid $sid" | Select-String ".  Disabled|.  Draining"  )			
			$disabled_tdats | foreach{ $elements=$_.tostring().trim() -split("\s+")
			$re += ,($elements[0])}
		}
		
		For($n=0;$n -lt $te.length; $n++){
			$on_list = $false
			For($m=0;$m  -lt $se.length; $m++){
					if( $te[$n][0] -eq $se[$m][0])
					{
					$on_list = $true
					}
			}
			if( $on_list -eq $false -and $tdats_to_add -gt 0){
					#ADD ENABLE COMMENT HERE
					$tdats_to_add--
					$tdat_to_enable = $te[$n][0]

						if($re -contains $tdat_to_enable )	#Dev currently being drained, just renable #make sure to check lenght first
						{
							log ("Enabling dev " + $tdat_to_enable + " that is currently draining/disabled state in pool " + $pool_name )
							$output = cmd /c "symconfigure -sid $sid -cmd `"enable dev $tdat_to_enable in pool $pool_name type=thin;`" -nop $commitment"
						}else{								#Dev not being drained, add to pool and enable
							log ("Adding dev " + $tdat_to_enable + " to pool " + $pool_name)
							$output = cmd /c "symconfigure -sid $sid -cmd `"add dev $tdat_to_enable to pool $pool_name type=thin, member_state=ENABLE;`" -nop $commitment"
						}
						log "output" $output


					$tdats_added=$true
					}

		}
		if($tdats_added -eq $true){
		log ("Rebalancing pool " + $pool_name)	
		$output = cmd /c "symconfigure -sid $sid -cmd `"start balancing on pool $pool_name;`" -nop $commitment"
		log "output" $output
		}
	}
}



#If less than lower watermark, attempt to remove
#modified	if($pool_util -lt $lowmark ){

	if($pool_util -lt $lowmark -and $pool_tdats -gt 10 ){
	#check first if we are not removing any, but if
	#how many?
	$tdat_min = [Math]::round(($pool_used_trc/($lowmark*$pool_tdat_trcs))*100  ) 		#

	if($tdat_min -lt 10){
	log ( "Less than 10 tdats to be left in pool, adjusting.")	
	$tdat_min = 10
	}

	$tdats_to_remove = ($pool_tdats - $tdat_min)
	
	#We will remove max $max_tdats_remove tdats at a time, work out how many minus currently being removed
	if (($tdats_to_remove + $tdats_being_removed) -gt $max_tdats_remove ){
		$tdats_maybe_to_remove = $max_tdats_remove - $tdats_being_removed

		#new check to ensure we don't have less than 10 tdats in each pool.
		if($tdats_maybe_to_remove -lt $tdats_to_remove){
			$tdats_to_remove = $tdats_maybe_to_remove
		}
	}
#else{
#	$tdats_to_remove -= $tdats_being_removed
#	}
	
	log ("TDATs we will remove from " + $pool_name + " " + $tdats_to_remove + ". Currently removing " + $tdats_being_removed + ". TDAT min " + $tdat_min )
	log ("Pool TDATs " + $pool_tdats + " Max TDATs to remove " + $max_tdats_remove + " TDATs to remove " + $tdats_to_remove)
	
	#How many we need removed
	$raw_tdats = (get-content $sp\$pool_name.csv)
	$te=@()
	$raw_tdats | foreach{ $elements=$_.tostring().trim() -split(",")
	$hash = [int]$elements[1]*10000000 + [int]$elements[2]*1000000 + [int]$elements[3]*100000 + ("0x" + $elements[0])
	$elements += ,$hash
	$te+= ,@($elements)}
	$n=0
	$m=0
	$te = $te | Sort-Object  @{Expression={$_[4]}; Descending=$true  } 
	

		
	
	For($n=0;$n -lt $te.length; $n++){
		For($m=0;$m  -lt $se.length; $m++){
				
				if( $te[$n][0] -eq $se[$m][0] -and $tdats_to_remove -gt 0){
				
				$tdat_to_remove = $te[$n][0]
				log ("Draining dev " + $tdat_to_remove + " from pool " + $pool_name)
				$output = cmd /c "symconfigure -sid $sid -cmd `"disable dev $tdat_to_remove in pool $pool_name, type=thin;`" -nop $commitment" 
				log "output" $output
				$tdats_to_remove--
				}
		}
	}
	}
	#Identify which to be removed
	#If we have disabled devices
	if($tdats_being_removed -gt 0 -and $tdats_added -ne $true){
		#$disabled_tdats = (Get-Content $sp\show_pool_01_detail.txt | Select-String ".  Disabled")
		[string]$disabled_tdats = ( cmd /c "Symcfg show -pool $pool_name -thin -all -sid $sid" | Select-String ".  Disabled")
		$disabled_tdats
		if($disabled_tdats.length -gt 0){
		$re=@()

		$disabled_tdats | foreach{ $elements=$_.tostring().trim() -split("\s+")
		$re+= ,$elements[0]}
		if($re.Length -gt 0){
			$re | %{ $tdat_to_remove_from_pool=$_
			log ("Removing disabled dev " + $tdat_to_remove_from_pool + " from pool " + $pool_name )
					$output = cmd /c "symconfigure -sid $sid -cmd `"remove dev $tdat_to_remove_from_pool from pool $pool_name, type=thin;`" -nop $commitment" 
					log "output" $output
			}	
			
		}
		}
	}
}
