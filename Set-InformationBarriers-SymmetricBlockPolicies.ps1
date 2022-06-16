<#
	.SYNOPSIS
	Creates symmetric block policies for all segments in the Information Barriers portal, with an exclusion list.	
 
    .DESCRIPTION
    Requires the ExchangeOnlineManagement module:
        Install-Module -Name ExchangeOnlineManagement
        Import-Module -Name ExchangeOnlineManagement
    Assumes that there are no "Allow" policies and that you want to bulk block each Segment from each other.
    There is an option to exclude Segments so that custom policies can be created manually instead.

    .PARAMETER exclusions
    Specifies the prefix of segments that are allowed to talk to any other segment. Supports regex and wildcards. Combine multiple segment names with a '|' for example: corp*|sales|accounting

    .PARAMETER logPath
    Specifies the directory to generate log files. Default is:  C:\Temp\InformationBarriers

    .PARAMETER connect
    Creates a new EXO session by default.

    .PARAMETER disconnect
    Closes the EXO session by default.

    .EXAMPLE
    .\Set-InformationBarriers-SymmetricBlockPolicies.ps1 -exclusions 'corporate*|HR' -logPath 'C:\logs' -connect $false -disconnect $false

    .NOTES
    Run this script at your own risk. Microsoft and I will not provide any support or warranty for any actions performed by this script.
 
    AUTHOR
    Dan Chemistruck

    Authored Date
    06/15/2022

    MIT License

    Copyright (c) 2022 Dan Chemistruck
    
    All rights reserved.

    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to deal
    in the Software without restriction, including without limitation the rights
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all
    copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
    SOFTWARE.

#>
[CmdletBinding(SupportsShouldProcess=$True,ConfirmImpact='Medium')]
Param(        
    [Parameter(Mandatory=$false,
            HelpMessage="Enter the prefix of segments that are allowed to talk to any other segment. Supports regex and wildcards. Combine multiple segment names with a '|' for example: corp*|sales")]
            [ValidateLength(0,256)]
            [String]$exclusions='corporate*|corporate-sales',

    [Parameter(Mandatory=$false,
    HelpMessage='Enter $true to connect to Exchange Online or false if you already have a session established..')]
    [boolean]$connect = $true,

    [Parameter(Mandatory=$false,
    HelpMessage='Enter $true to connect to Exchange Online or false if you already have a session established..')]
    [boolean]$disconnect = $true,

    [Parameter(Mandatory=$false,
        HelpMessage="Directory to output files to")]
        [String]$logPath="C:\Temp\InformationBarriers"
)
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

if (!(test-path $logPath)){
    New-Item -Path $logPath -ItemType directory
}
$logPath = join-path $logPath "InformationBarriers-Logs.csv"

#Import the Exchange Online Management module or installs it, and connects to Exchange Online.
if ($connect){
    try {
        write-host Importing ExchangeOnlineManagement -foregroundcolor: yellow
        Import-Module ExchangeOnlineManagement -ErrorAction SilentlyContinue
    }
    catch {
        write-host ExchangeOnlineManagement Module is not installed.
        Install-Module -Name ExchangeOnlineManagement -Confirm $false
        Import-Module ExchangeOnlineManagement
    }
    Connect-IPPSSession
}

# Gathers all segments (and filters out segments on the exclusions list) and policies.
$segments = Get-OrganizationSegment| where{$_.Name -notmatch $exclusions}|sort name
$policies = Get-InformationBarrierPolicy
# Adds all filtered segments to existing policies or creates a new policy.
Foreach ($segment in $segments)
{
    $progress=$segment.name
    Write-Progress -Activity "Reviewing policy for $progress"
    # Define segments to exlcude block list. This includes the current segment a$nd other segments with the same prefix, which is identified with a '-'.
    $blockedsegments = $segments | where{$_.Name -notmatch $segment.name -and $_.name.split('-')[0] -notmatch $segment.name.split('-')[0]}
    $name = "Block " + $segment.name + " to non-corporate segments"
    write-host $progress
    # Find out if there is an existing policy and update it.
    if($policies|where {$_.assignedsegment -eq $segment.name}) {
        Write-Progress -Activity "Updating existing policy." -CurrentOperation "Reviewing policy for $progress"
        $guid = $policies|where {$_.assignedsegment -eq $segment.name}|select guid,name
        try{
            Set-InformationBarrierPolicy -id $guid.guid -SegmentsBlocked $blockedsegments.name -State Active -force -ErrorAction stop

            $logName = $guid.name
            $logObject = new-object PSObject
            $logObject| add-member -membertype NoteProperty -name "Policy" -Value $logName
            $logObject| add-member -membertype NoteProperty -name "Error" -Value "Success"
            $logObject| add-member -membertype NoteProperty -name "Step" -Value "Updating Existing Policy"
            $logObject| add-member -membertype NoteProperty -name "Time" -Value $(get-date -Format yyyy-MM-dd-HHmm-ss)
            $logObject| export-csv $logPath -nti -append -force     
        }
        catch{
            $errName = $guid.name
            Write-warning "Error with updating exising policy $errName. $_.Exception.Message"
            $errorObject = new-object PSObject
            $errorObject| add-member -membertype NoteProperty -name "Policy" -Value $errName
            $errorObject| add-member -membertype NoteProperty -name "Error" -Value $_.Exception.Message
            $errorObject| add-member -membertype NoteProperty -name "Step" -Value "Updating Existing Policy"
            $errorObject| add-member -membertype NoteProperty -name "Time" -Value $(get-date -Format yyyy-MM-dd-HHmm-ss)
            $errorObject| export-csv $logPath -nti -append -force
        }
    }
    # Otherwise, create a new policy.
    else {
        Write-Progress -Activity "Creating new policy:  $name." -CurrentOperation "Reviewing policy for $progress"
        try{
            New-InformationBarrierPolicy -Name $name -AssignedSegment $segment.name -SegmentsBlocked $blockedsegments.name -State Active -force -ErrorAction stop

            $logObject = new-object PSObject
            $logObject| add-member -membertype NoteProperty -name "Policy" -Value $name
            $logObject| add-member -membertype NoteProperty -name "Error" -Value "Success"
            $logObject| add-member -membertype NoteProperty -name "Step" -Value "Creating New Policy"
            $logObject| add-member -membertype NoteProperty -name "Time" -Value $(get-date -Format yyyy-MM-dd-HHmm-ss)
            $logObject| export-csv $logPath -nti -append -force     
        }
        catch{
            Write-warning "Error with creating new policy $name. $_.Exception.Message"
            $errorObject = new-object PSObject
            $errorObject| add-member -membertype NoteProperty -name "Policy" -Value $name
            $errorObject| add-member -membertype NoteProperty -name "Error" -Value $_.Exception.Message
            $errorObject| add-member -membertype NoteProperty -name "Step" -Value "Creating New Policy"
            $errorObject| add-member -membertype NoteProperty -name "Time" -Value $(get-date -Format yyyy-MM-dd-HHmm-ss)
            $errorObject| export-csv $logPath -nti -append -force
        }  
    }
}

# After creating or updating each policy, this will apply the new policies. This may take several hours to complete.
try{
    Start-InformationBarrierPoliciesApplication -ErrorAction stop

    $logObject = new-object PSObject
    $logObject| add-member -membertype NoteProperty -name "Policy" -Value "All Policies"
    $logObject| add-member -membertype NoteProperty -name "Error" -Value "Success"
    $logObject| add-member -membertype NoteProperty -name "Step" -Value "Applying Policy"
    $logObject| add-member -membertype NoteProperty -name "Time" -Value $(get-date -Format yyyy-MM-dd-HHmm-ss)
    $logObject| export-csv $logPath -nti -append -force     
}
catch{
    Write-warning "Error with applying all policies. $_.Exception.Message"
    $errorObject = new-object PSObject
    $errorObject| add-member -membertype NoteProperty -name "Policy" -Value "All Policies"
    $errorObject| add-member -membertype NoteProperty -name "Error" -Value $_.Exception.Message
    $errorObject| add-member -membertype NoteProperty -name "Step" -Value "Applying Policy"
    $errorObject| add-member -membertype NoteProperty -name "Time" -Value $(get-date -Format yyyy-MM-dd-HHmm-ss)
    $errorObject| export-csv $logPath -nti -append -force
}
# Disconnects from Exchange Online
if ($disconnect){
    Disconnect-ExchangeOnline -confirm:$false
}
