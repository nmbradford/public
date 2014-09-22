
#update_imageprofile.ps1

# updates an existing imageprofile with vibs available in new imgaes as released by VMware
# while still retaining custom vibs such as vcd agent, fdm agent, drivers and the n1k vem.
#
# Nick Bradford - nick.m.bradford@accenture.com
#
# v0.1 16/06/12



trap [Exception] {
	
	Write-Host "Sorry - error occured"
	throw $_
	
}

function add-fdmdepot {

	$viserver = Read-Host "Enter the hostname of the vCenter Server"
	
	try {
		add-esxsoftwaredepot "http://$viserver/vSphere-HA-depot"
		if ( -not $? ) { throw "$($error[0])" }
		
		$script:laststatus = "Added HA depot on $viserver."
		$script:laststatuscolour = "Green"
	}
	catch{
		$script:laststatus = "Failed adding HA depot on $viserver`n$_"
		$script:laststatuscolour = "Red"
	}
	finally{}

}

function add-customdepot{

	Write-Host
	$depotpath = Read-Host "Enter path to esx image profile depot file" 
	
	while (-not (Test-Path $depotpath )) { 

		Write-Host -ForegroundColor Yellow "Path not found." 
		$depotpath = Read-Host "Enter path to esx image profile depot file"
	}
	
	try {
		Add-EsxSoftwareDepot $depotpath | Out-Null
		if ( -not $? ) { throw "$($error[0])"}
		
		$script:laststatus = "Added custom update depot $depotpath"
		$script:laststatuscolour = "Green"
	}
	catch{
		$script:laststatus = "Failed adding custom update depot $depotpath`n$_"
		$script:laststatuscolour = "Red"

	}
	finally{}
	
}

function add-vmwupdatedepot{

	try {
		Add-EsxSoftwareDepot https://hostupdate.vmware.com/software/VUM/PRODUCTION/main/vmw-depot-index.xml
		if ( -not $? ) { throw "$($error[0])"}
		$script:laststatus = "Added VMWare update depot"
		$script:laststatuscolour = "Green"
	}
	catch {
		$script:laststatus = "Failed adding VMware update depot.`n$_"
		$script:laststatuscolour = "Red"
		
	}
	finally{}
	
}

function get-intresponse { 

	param (	
		$prompt = ""
	)
	
	$responseok = $false
	while ( -not $responseok ) {
		try {
			[int]$response = Read-Host $prompt
			$responseok = $true
			}
		catch { }
			
		finally{
		
			$response
		}
	}
}

function out-menu{

	param ( 
		$optionhash,
		$section = "",
		$prompt= ""
		
	)
	
	Clear-Host
	
	Write-Host
	Write-Host -ForegroundColor Black -BackgroundColor Green "ESXi Auto Deploy image update - $section"
	Write-Host
	Write-Host -ForegroundColor Green "Reference profile: $referenceprofile"
	Write-Host -ForegroundColor Green "Comparison profile: $comparisonprofile"
	Write-Host 
	
	$optionhash.keys | sort-object | % { write-host "$_ -    $($optionhash.item($_))" }

	Write-Host
 	Write-Host -ForegroundColor $laststatuscolour  $laststatus
	$script:laststatus = ""
	
 	$response = ""
	$response = Read-Host $prompt
	
	if ($response -and (-not ($optionhash.containskey($response)))) { 
		
		$script:laststatus = "Invalid Choice."
		$script:laststatuscolour = "Red"
	}

	$response
}


#setup globals
$script:referenceprofile = ""
$script:comparisonprofile = ""
$script:laststatus = ""
$script:laststatuscolour = "White"
$script:exitconfirm = $false



#generate root menu
$imagecreated = $false
$imagesaved = $false

$roothash = @{}
$roothash.add("0", "Add image depot (software channel)")
$roothash.add("1", "List current depots (software channel)")
$roothash.add("2", "List/Select current image profiles")
$roothash.add("3", "Add custom VIB")
$roothash.add("4", "Create updated image")
$roothash.add("5", "Save updated image")
$roothash.add("h", "Help")
$roothash.add("x", "Exit")

while ($exitconfirm -ne $true ) {

	$response = out-menu $roothash "" "Choose an option"
	
switch -regex ($response) {
	
		"0"{
		
			#Add Depot
			$exitadddepot = $false
			while ( -not $exitadddepot) {
	
				$optionhash = @{}

				$optionhash.Add("0", "VMware Host Update Depot")
				$optionhash.Add("1", "vSphere HA Depot (requires vCenter Address)")
				$optionhash.Add("2", "Custom depot")
				$optionhash.Add("x", "Exit")
				
				
				$response = out-menu $optionhash "Add Depot" "Choose an option"

				switch -regex ($response) {
				
					"0"{ add-vmwupdatedepot }
					"1"{ add-fdmdepot}
					"2"{ add-customdepot}
					"x"{ $exitadddepot = $true }
				}
			}		
		}
		
		"1"{
			$exitlistdepot = $false
			while ( -not $exitlistdepot) {
				#List/Select profiles
				$depothash = @{}
				$i = 0
				get-esxsoftwaredepot | % { $depothash.Add("$i", $($_.ChannelId)); $i++}
				$depothash.Add("x", "Exit")
				$response = out-menu $depothash "Current Software Depots" "Hit the 'any key' to exit. ;)"

				switch -regex ($response) {
				
					default{ $exitlistdepot = $true}
				}
			}
		
		}
		"2"{
			$exitlistimage = $false
			while ( -not $exitlistimage) {
				#List/Select profiles
				$profilehash = @{}
				$i = 0
				get-esximageprofile | % { $profilehash.Add("$i", $($_.name)); $i++}
				$profilehash.Add("x", "Exit")
				$response = out-menu $profilehash "List Profiles" "Choose a profile"

				switch -regex ($response) {
				
					"x"{ $exitlistimage = $true }
					default{ 
						#no need to check for reponse existing in the hash - its already done in the out-menu fn
						
						$selectedimageprofilename = $profilehash.Item($response)
						
						#prompt for selected profile being updating or reference profile.
						$title = "Set profile as reference or comparison profile?"
						$message = "Choose whether the selected profile is to be the reference or comparison profile?"

						$comparisonprofilechoice = New-Object System.Management.Automation.Host.ChoiceDescription "&Comparison", `
						    "Selected profile is comparison profile."

						$referenceprofilechoice = New-Object System.Management.Automation.Host.ChoiceDescription "&Reference", `
						    "Selected profile is reference profile."

						$options = [System.Management.Automation.Host.ChoiceDescription[]]($referenceprofilechoice, $comparisonprofilechoice )

						$result = $host.ui.PromptForChoice($title, $message, $options, 0) 

						switch ($result){
					        0 {
								$script:referenceprofile = $selectedimageprofilename
								
							}
					        1 {
								$script:comparisonprofile = $selectedimageprofilename
							}	
						}
					}
				}
			}
		}
		"3"{
			#Add custom VIB
			write-host
			write-host -ForegroundColor Yellow "Not Implemented Yet.  Please mash the keypad to continue."
			read-host
			
		}
		"4"{
			#Update selected image
			$newprofile = Read-Host "Enter new image profile name"
			while ( Get-EsxImageProfile | ? { $_ -like $response}) {
				Write-Host "Image profile already exists."
				$newprofile = Read-Host "Enter new image profile name"
			}
			
			$diff = Compare-EsxImageProfile -ComparisonProfile $comparisonprofile -ReferenceProfile $referenceprofile
			New-EsxImageProfile -CloneProfile $referenceprofile -Name $newprofile | Out-Null
			Write-Host "Image profile $newprofile created from clone of $referenceprofile`n"
			write-host "Adding VIBs only found in $comparisonprofile"
			$diff.OnlyInComp | % { Add-EsxSoftwarePackage -ImageProfile $newprofile $_ | Out-Null ; Write-Host " - Added VIB $_ to $newprofile" }
			Write-Host
			Write-Host "Adding updated VIBs from $comparisonprofile"
			$diff.upgradefromref | % { Add-EsxSoftwarePackage -ImageProfile $newprofile $_  | out-null; Write-Host " - Added VIB $_ to $newprofile"}
			
			write-host
			write-host -ForegroundColor Green "Update complete.  Please mash the keypad to continue."
			read-host
			
		}
		"5"{
			#Save image
		
		}
		"h"{
		
			#Help
			Write-Host
			Write-Host "VMware Auto Deploy uses deploy rules that associate hosts with various configuration options."
			Write-Host "One such option is the name of the image profile that esentially defines the version"
			Write-Host "of ESXi that is booted and the image profile defines a list of vibs that make up the image."
			Write-Host
			Write-Host "The build number of the host is associated with the vib 'esxi-base', however there are"
			Write-Host "many other vibs required in an image profile including drivers, agents and third party"
			write-host "modules.  Examples include the fdm (VMware HA) agent, vCloud agent, the Cisco N1K vem module"
			Write-Host "and Cisco ucs drivers such as fnic and enic."
			Write-Host 
			Write-Host "When VMware release esxi updates, they release a number of updated image profiles, however to"
			write-host "be useful in most environments, these must be modified to include required packages before "
			Write-Host "being used."
			Write-Host 
			Write-Host "This script automates the construction of a new image profile based on an existing modified (reference) one"
			Write-Host "and a newly released  image profile (comparison) from VMware while still including required"
			Write-Host "vibs not found in the updated profile."
			Write-Host 
			Read-Host "Press the return key to continue"
		}
		"x"{ 
		
			#exit
			if ( $imagecreated -and ( -not $imagesaved)) { 
			
				$title = "Exit without saving?"
				$message = "The newly created image has not been exported. Are you sure you wish to exit?"
			
				$yes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes", `
				    "Confirm you wish to exit without exporting the new image."

				$no = New-Object System.Management.Automation.Host.ChoiceDescription "&No", `
				    "Return to the main menu."

				$options = [System.Management.Automation.Host.ChoiceDescription[]]($yes, $no)

				$result = $host.ui.PromptForChoice($title, $message, $options, 0) 

				if ($result -eq 0) { $exitconfirm = $true }

			}
			else {
			
				$exitconfirm = $true
			}
		}
		default {}
		
	}
}

