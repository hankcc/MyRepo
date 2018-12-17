# List_licenses
# Script to list o365 licenses for a list of users, or all users in a tenent
# v 2018-03-26 by Magnus.Brannstrom@ericsson.com
#
# Run Connect MSOL-Service first to connect to O365 tenant
#
# Release History (click to expand):
<#
2018-03-26: Cleaned up the code a little bit
            Changed the way of switching between listing "all users" vs "users in a list".
            Remove the function to try to guess UPN for shared mailboxes
2017-09-20: Added PreferredDataLocation column to give "Multi-Geo" information
2017-02-01: Special version that will also try tom match on email if UPN not found. 
            Due to naming rules, this code finds UPN for most our shared mailboxes based on their email.
            Added blocked attribute to be read from the user (for experimentation purposes)
            Changed color for "not found" message to red
            Created list of "not found" and displayed in summary at the end
2016-11-24: Fixed a bug
2016-11-23: Added UsageLocation and isLicensed property as columns, constant column order, debug mode that writes UPN & counter
            It is also possible to easily alter the script to list all users instead of using the input file (see lines 44-57)
#>

#------------------------------------------------------------------
# Specify an input file in $Inputfile to list licenses for a group of users. To list all licenses in tenant, set $Inputfile to "" 
#$Inputfile = "C:\lic00502\test.txt"
$Inputfile = ""

# Specify an output file in the $Outputfile variable. This will be created as a .csv file
$Outputfile = "C:\temp2\lic1122.csv"

# Set $Detailed to $true to include sub-services in output file
$Detailed = $true

# Set $Debug to $true to print each UPN and a counter
$Debug = $true
#------------------------------------------------------------------

# Function to process each user
Function Load-UserData {
[CmdletBinding()] 
Param ($myuser)
        $usrobject = New-Object psobject
        $usrobject = $schemaobject.PSObject.Copy()

        # Add user info
        $usrobject.UPN = $myuser.UserPrincipalName 
        $usrobject.SIGNUM = $myuser.ImmutableId
        $usrobject.BLOCKED = $myuser.BlockCredential
        $usrobject.LOCATION = $myuser.UsageLocation
        $usrobject.PDL =  $myuser.PreferredDataLocation
        $usrobject.ISLICENSED = $myuser.isLicensed 
     
        if ($debug) { Write-Host $myuser.UserPrincipalName $counter}

        if ($myuser.Licenses.Count -gt 0) {
         foreach ($i in $myuser.Licenses) {
            $usrobject.($i.AccountSku.SkuPartNumber) = "Yes"
            if ($i.ServiceStatus.Count -gt 0 -And $Detailed) {
               foreach ($sst in $i.ServiceStatus) {$usrobject.($i.AccountSku.SkuPartNumber + ' ' + $sst.ServicePlan.ServiceName) = $sst.ProvisioningStatus}
            }
         }
        }
         $usrobject | Export-csv $outputfile -NoTypeInformation -Append
        }
 

#==========================================
Clear-Host
Remove-Item $outputfile -ErrorAction SilentlyContinue
$counter = 0
$notfound = "Users not found in Azure AD:`n"

#region Code to Build license "schema"
$schemaobject = New-Object psobject
$schemaobject | add-member -MemberType NoteProperty -name "UPN" -Value "" -PassThru | add-member -MemberType NoteProperty -name "SIGNUM" -Value "" -PassThru | add-member -MemberType NoteProperty -name "BLOCKED" -Value "" -PassThru | add-member -MemberType NoteProperty -name "LOCATION" -Value "" -PassThru | add-member -MemberType NoteProperty -name "PDL" -Value "" -PassThru | add-member -MemberType NoteProperty -name "ISLICENSED" -Value "" 
foreach ($mysku in (Get-MsolAccountSku | Sort-Object AccountSkuId)) {
    if ($mysku.ConsumedUnits -gt 0) {
        try {$schemaobject | add-member -MemberType NoteProperty -name $mysku.SkuPartNumber -Value "" -ErrorAction SilentlyContinue} catch {$null}
        foreach ($myser in $mysku.ServiceStatus) {
            if ($Detailed) {
                try {$schemaobject | add-member -MemberType NoteProperty -name ($mysku.SkuPartNumber + ' ' + $myser.ServicePlan.ServiceName) -Value ""  -ErrorAction SilentlyContinue} catch {$null}
            }
        }
    }
}
#endregion

# If no input file, run script against all users in tenant
If ($Inputfile.Length -eq 0) {
    Get-MsolUser -All | foreach { 
        $myuser = $_
        $counter+=1 
        Load-UserData -myuser $myuser 
    }
}

# If input file, run script against that file
If ($Inputfile.Length -gt 0) {
    Get-Content $Inputfile | foreach { 
            $myuser = $(try {Get-MsolUser -UserPrincipalName ($_.trim()) -ErrorAction SilentlyContinue} catch {$null}) 
            if ($myuser -ne $null) { 
                $counter+=1 
                Load-UserData -myuser $myuser 
            }
            Else {if ($_.Trim().Length -gt 0) {
                Write-Host $_' - Not found in Azure AD, please handle this user manually' -ForegroundColor Red
                $notfound += $_ + "`n"
            }
        }
    }
}
Write-Host
Write-Host $Counter "accounts found and added to output file`n" -ForegroundColor Yellow
Write-Host $notfound -ForegroundColor Yellow
