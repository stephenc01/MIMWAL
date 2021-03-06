<#
    This script is used to update WAL Workflow XOMLs for the latest version of the WAL assemblies.

	Run this script ONLY AFTER latest MIMWAL build is deployed on all the servers.

    It is highly recommended that this script will be run in a Test enviorment and updated workflows tested thoroughly
    before the updated Xomls are migrated to the Production enviorment using FIM / MIM configuration migration process.

    To avoid reusing the previous versions of the assemblies that might be already loaded in the PowerShell session,
    you are required start on a fresh PowerShell prompt.
#>

Set-StrictMode -version 2.0

$Error.Clear()

if (@(Get-PSSnapin | Where-Object { $_.Name -eq "FIMAutomation" }).Count -eq 0)
{
    Add-PSSnapin "FIMAutomation" -ErrorAction Stop
}

$DebugPreference = "Continue"
$VerbosePreference = "Continue"

$walAssemblyName = "MicrosoftServices.IdentityManagement.WorkflowActivityLibrary"
$walAssemblyPath = Join-Path $PWD.ProviderPath -ChildPath "$walAssemblyName.dll"

function TestIsAssemblyLoaded
{
    param([string]$assemblyName)

    foreach ($asm in [AppDomain]::CurrentDomain.GetAssemblies())
    {
        if ($asm.GetName().Name -eq $assemblyName)
        {
            return $true
        }
    }

    return $false
 }

function GetObject
{
    param($exportObject)
    end
    {
        $importObject = New-Object Microsoft.ResourceManagement.Automation.ObjectModel.ImportObject
        $importObject.ObjectType = $exportObject.ResourceManagementObject.ObjectType
        $importObject.TargetObjectIdentifier = $exportObject.ResourceManagementObject.ObjectIdentifier
        $importObject.SourceObjectIdentifier = $exportObject.ResourceManagementObject.ObjectIdentifier
        $importObject.State = 1 
        $importObject
     } 
}

function SetAttribute
{
    param($object, $attributeName, $attributeValue)
    end
    {
        $importChange = New-Object Microsoft.ResourceManagement.Automation.ObjectModel.ImportChange
        $importChange.Operation = 1
        $importChange.AttributeName = $attributeName
        $importChange.AttributeValue = $attributeValue
        $importChange.FullyResolved = 1
        $importChange.Locale = "Invariant"

        if ($object.Changes -eq $null)
        {
            $object.Changes = (,$importChange)
        }
        else
        {
            $object.Changes += $importChange
        }
    }
}

if (!(Test-Path $walAssemblyPath))
{
    throw ("Could not find file: {0}" -f $walAssemblyPath)
}

if (TestIsAssemblyLoaded $walAssemblyName)
{
    throw "The WAL assemblies were previously loaded in this PowerShell session. Please run the script on a fresh new command-line."
}

try
{
    Write-Debug "Loading Assembly: $walAssemblyPath"
        
    $walAssembly = [Reflection.Assembly]::LoadFile($walAssemblyPath)
}
catch
{
    throw ("Could not load assembly: {0}. Error: {1}" -f $walAssemblyPath, $_)
}

$assemblyName = $walAssembly.FullName
$assemblyShortName = ($assemblyName -Split ",")[0].Trim()

$workflows = Export-FIMConfig –onlyBaseResources -customconfig "/WorkflowDefinition"

foreach ($workflow in $workflows)
{
    $workflowName = ($workflow.ResourceManagementObject.ResourceManagementAttributes | where-object {$_.AttributeName -eq "DisplayName"}).Value
    $workflowXoml = ($workflow.ResourceManagementObject.ResourceManagementAttributes | where-object {$_.AttributeName -eq "Xoml"}).Value
    
    if ($workflowXoml -match $assemblyShortName -and !($workflowXoml -match $assemblyName))
    {
        ## Write-Verbose "Original Worflow Xoml:`n $workflowXoml"
        $workflowXoml = $workflowXoml -replace ";Assembly=$assemblyShortName,[^`"]+`"", ";Assembly=$assemblyName`""
        
        Write-Host "`nUpdating Workflow: $workflowName"
        
        $wf =  GetObject $workflow
        
        SetAttribute -object $wf `
                     -attributeName  "XOML" `
                     -attributeValue  $workflowXoml 
        
        $wf | Import-FIMConfig
    }
    else
    {
		if ($workflowXoml -match $assemblyName)
		{
			 Write-Host "`nSkipping Workflow : '$workflowName'. No updates necessary. It's already using the latest MIMWAL assembly '$assemblyName'."
		}
		else
		{
			 Write-Host "`nSkipping Workflow : '$workflowName'. No updates necessary. It does not use any MIMWAL activities."
		}
    }
}

