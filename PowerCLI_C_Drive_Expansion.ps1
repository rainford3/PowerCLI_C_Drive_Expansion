Param([string]$vcenter, [string]$GuestUser = "", [string]$GuestPassword = "")

set-strictmode -version latest
$global:body = "<h2>Windows C: drive expansion report.</h2><span>This report contains information relating to the automated C: drive expansion script running against $vcenter.</span>"
$global:snapshot = $NULL
$logfile = "WP_C_Drive_Expansion.$vcenter.$(get-date -format `"dd-MM-yyyy_hh-mm`").log"
#workout date of one month
$d=get-date
$d = $d.addmonths(-1)
$d = $d.ToString("dd/MM/yyyy")
#store of historical data used to keep track of additions
$global:file = "$vcenter.csv"
$global:snapshotPresent = @()
$global:failed = @()
$global:pastIncrease = @()
$global:Increased = @()

if(Test-Path $global:file){}else{
	
	Set-Content $global:file -Value "Server,OriginalGuestSize,OriginalVMDKSize,NewVMDKSize,Date"

}

#log to a file
function log($string){

    write-host $string
    $string | out-file -Filepath $logfile -append

}

#Check if a snapshot is present
Function checkSnapshot($server){

	#reset global var to null
	$global:snapshot=$NULL
	
	#get snapshots for the VM
	$snapshot = Get-Snapshot -vm $server
	
	#check if snapshot present on vm
	if($snapshot){
	
		#set global snapshot var as true
		$global:snapshot=$true
		log "Found snapshot!"
		$global:snapshotPresent += $server
		$global:failed += $server
		
	}else{
	
		#set snapshot as false 
		$global:snapshot=$false
		log "No snapshot present."
		
	}
}

#log to a file
function increase-disk($server, $vm, $newdisksize, $increase, $GuestUser, $GuestPassword){
    
    if($increase){
    
        log "Drive hasn't been increased in the last month!"

    }else{
    
        log "Drive has been increased within the last month!"
		$global:pastIncrease += $server
		
    }
	
	if(checkSnapshot($server)){
	
		log "Cancelling expansion of $server bacause a snapshot was found!"
	
	}else{
		
		#set new VMDK size and run DISKPART in the guest OS of each of the specified virtual machines
	    Get-HardDisk -vm $server | Where {$_.Name -eq "Hard disk 1"} | Set-HardDisk -CapacityGB $newdisksize -Confirm:$false
		$shell = Invoke-VMScript -VM $server -ScriptText "ECHO RESCAN > C:\DiskPart.txt && ECHO SELECT Volume C >> C:\DiskPart.txt && ECHO EXTEND >> C:\DiskPart.txt && ECHO RESCAN >> C:\DiskPart.txt && ECHO EXIT >> C:\DiskPart.txt && DiskPart.exe /s C:\DiskPart.txt && DEL C:\DiskPart.txt /Q" -ScriptType BAT -GuestUser $GuestUser -GuestPassword $GuestPassword
		log $shell
	    $disk = Get-HardDisk -vm $server | Where {$_.Name -eq "Hard disk 1"}
	    $HarddiskCapacity = ($disk | measure-Object CapacityGB -Sum).sum

	    log $HarddiskCapacity
		#if increase vmdk expansion successful
	    if($HarddiskCapacity -eq $newdisksize){
	    
	        log "Drive Increased Succesfully!"
			#if diskpart successful, insert record in csv
            if($shell -Match "DiskPart successfully extended the volume."){

                log "Guest sucessfully expanded C: within Windows!"
				New-Object PsObject -Property @{ Server = $server; OriginalGuestSize = $GuestCapacity; OriginalVMDKSize = $HarddiskCapacity; NewVMDKSize = $newdisksize; Date = (Get-Date).ToString('dd/MM/yyyy')} | Export-Csv $global:file –append
				$global:increased += $server
				
            }
            else{
			
				$global:failed += $server
                log "Something went wrong with expanding the guest C: drive!"

            }
	       
	    }else{
		
			$global:failed += $server
			$failed = $server
	        log "Something went wrong while increasing the VMDK!"

	    }
		
	}

}

#generate a percentage
Function Percentcal {
    param(
    [parameter(Mandatory = $true)]
    [int]$InputNum1,
    [parameter(Mandatory = $true)]
    [int]$InputNum2)
    $InputNum1 / $InputNum2*100
}

#add in vmware powercli functionality
Add-PSSnapin VMware.VimAutomation.Core

#connect to vcenter (script.ps1 -vcenter "" -GuestUser "" -GuestPassword "" )
Connect-VIServer $vcenter -User $GuestUser -Password $GuestPassword

#Get all VM's in vCenter instance
$servers = get-vm | where-object{$_.powerState -eq "PoweredOn"}

#Iterate through each server
foreach($server in $servers){
    $vm = get-vmguest -vm $server
    
    $increase = $true
	
    Import-csv $global:file | Sort-Object { $_."Date" -as [datetime] } | Foreach-Object{

        if([System.DateTime]::Parse((date).ToString($_."Date")) -ge [System.DateTime]::Parse((date).ToString($d)) -and $_."Server" -eq $vm){
    
            $increase = $false

        }

    }

    #Check if VM is a Windows Server
    if($vm | Where-Object {$_.OSFullName -like "*Microsoft*"}){
    log $server
        #Check blacklist
        if($server -Notlike "*something*" -and $server -Notlike "servername"){
            
			#Attempt to increase C: in guest before attempting to add space as there may be capacity there already. This must be done before checking for disk size or it will skew the checks
			$shell = Invoke-VMScript -VM $server -ScriptText "ECHO RESCAN > C:\DiskPart.txt && ECHO SELECT Volume C >> C:\DiskPart.txt && ECHO EXTEND >> C:\DiskPart.txt && ECHO RESCAN >> C:\DiskPart.txt && ECHO EXIT >> C:\DiskPart.txt && DiskPart.exe /s C:\DiskPart.txt && DEL C:\DiskPart.txt /Q" -ScriptType BAT -GuestUser $GuestUser -GuestPassword $GuestPassword
			if($shell -Match "DiskPart successfully extended the volume."){
			
				log "DiskPart successfully extended the volume."
				
			}
			log $shell
			#get vmdk harddisk1 object
            $disk = Get-HardDisk -vm $server | Where {$_.Name -eq "Hard disk 1"}
            #get full name of vmdk (Includes path which we dont want)
            $filename = $disk.Filename
            #get vmdk name without path
            $datastore  = $filename.split("]")[0].split("[")[1]
            #get datastore which holds vmdk of harddisk 1
            $datastoreObject = Get-Datastore | Where {$_.Name -eq $datastore}
            #get percentage of free space on datastore
            $datastorePercentFree = Percentcal $datastoreObject.FreeSpaceMB $datastoreObject.CapacityMB
            #get capacity of vmdk
            $HarddiskCapacity = ($disk | measure-Object CapacityGB -Sum).sum
            #Add 10GB to existing harddrisk size for increase
            $newdisksize = $HarddiskCapacity + 10
            #get cluster of a datastore
            $cluster = Get-DatastoreCluster -Datastore $datastore
            
            log "The capacity of the VMDK is $HarddiskCapacity GB"            
            log "The Percentage Free of Datastore $datastore is $datastorePercentFree"

            #Check there is more than 20% free on the datastore
            if($datastorePercentFree -ge 20){
            
                log "$datastore has more than 20% free ($datastorePercentFree)"

                #Get each drive of the server
                ForEach ($drive in $server.Extensiondata.Guest.Disk){

                    $GuestFreespace = [math]::Round($drive.FreeSpace / 1GB)
                    $GuestCapacity = [math]::Round($drive.Capacity/ 1GB)
                    $SpaceOverview = "$GuestFreespace" + "/" + "$GuestCapacity" 
                    $PercentFree = [math]::Round(($GuestFreespace)/ ($GuestCapacity) * 100)

                    if($drive.DiskPath -like "*C:*"){
                    
                        log "The capacity of the guest C: drive is $GuestCapacity GB"
                        log "C: Drive has $GuestFreespace GB free"

                        #if guest harddisk is equal to size of vmdk (Tollerance of 1GB either way
                        if($GuestCapacity -eq $HarddiskCapacity -or ($GuestCapacity += 1) -eq $HarddiskCapacity -or ($GuestCapacity -= 1) -eq $HarddiskCapacity){
                           
							#if freespace is less than or equal to 5GB, add capacity to vmdk and guest
                            if($GuestFreespace -le "5"){
							
								#Have vSphere PowerCLI increase the size of the first hard drive in each target VM
                                log "Less than 5GB free!"
                                increase-disk $server $vm $newdisksize $increase 
								
							#free space is greater than 5GB
                            }else{
                                                            
                            }

                        }
                        #VMDK and guest harddisk dont match each other due to guest C: drive space not being equal to vmdk harddisk 1 or guest C: drive is not fully expanded to match the size fo harddisk 1
                        else{
                        	
							$global:failed += $server
                            log "VMDK and Guest disk sizes dont match! Expansion failed!"

                        }

                    }
								
                }
	
            }else{
            	
				$global:failed += $server
                log "Datastore has less than 20% free. Expansion Failed!"
			
            }

        }

    }

}

$global:body += "<table><tr><th>VM's increased today</th></tr>"
foreach ($element in $global:increased) {$global:body += "<tr>$element</tr>"}
$global:body += "</table><span>These are a list of VM's that have been increased today due to low space (<5GB) on the C: drive.</span>"

$global:body += "<table><tr><th>VM's increased in the past month</th></tr>"
foreach ($element in $global:pastIncrease) {$global:body += "<tr>$element</tr>"}
$global:body += "</table><span>These VM's have had their storage increased one or more times in the past month and require investigation as to why.</span>"

$global:body += "<table><tr><th>Snapshots present</th></tr>"
foreach ($element in $global:snapshotPresent) {$global:body += "<tr>$element</tr>"}
$global:body += "</table><span>These are a list of servers that have failed to expand due to snapshots preventing the VMDK expansion.</span>"

$global:body += "<table><tr><th>Failed expansions</th></tr>"
foreach ($element in $global:failed) {$global:body += "<tr>$element</tr>"}
$global:body += "</table><span>These have most likely failed due to a network error causing the auth to fail or a server existing off of the domain.</span>"

$email = @{
	From = "something@something.com"
	To = "something@something.com", "something@something.com"
	Subject = "$vcenter C: drive expansion report."
	SMTPServer = "something@something.com"
	Body = $global:body
	Attachments = $global:file, $logfile
}

send-mailmessage @email -BodyAsHtml