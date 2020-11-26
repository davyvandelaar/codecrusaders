#!powershell

# Copyright: Davy van de Laar
# GNU General Public License v3.0+ (see COPYING or https://www.gnu.org/licenses/gpl-3.0.txt)

# todo:
#   - use credential for vcenter / nsx connection
#   - created functions
#   - add functionality for
#       - checking
#       - absent / present state
#       - additional options
#       - more logic in error logging

#AnsibleRequires -CSharpUtil Ansible.Basic
#Requires -Module Ansible.ModuleUtils.Legacy

$ErrorActionPreference = "Stop"

# input parameters
$params = Parse-Args $args -supports_check_mode $true
$hvserver_input = Get-AnsibleParam -obj $params -name "hv_server" -type "str" -failifempty $true
$hvusername = Get-AnsibleParam -obj $params -name "hv_username" -type "str" -failifempty $true
$hvpassword = Get-AnsibleParam -obj $params -name "hv_password" -type "str" -failifempty $true
$hvuserdomain = Get-AnsibleParam -obj $params -name "hv_domain" -type "str" -failifempty $true
$hvtemplatepool = Get-AnsibleParam -obj $params -name "hv_template_poolname" -type "str" -failifempty $true
$addentitlement = Get-AnsibleParam -obj $params -name "hv_add_entitlement" -type "list" - element "str"-failifempty $false
$poollist = Get-AnsibleParam -obj $params -name "hv_pool_list" -type "list" -element "str" -failifempty $true

$result = @{
    changed = $false
    exists = @()
    created = @()
    entitled = @()
    entitle_exists =@()
    entitle_error = @()
}

Import-Module VMware.VimAutomation.HorizonView
Get-Module -ListAvailable 'VMware.Hv.Helper' | Import-Module

# make connection with connection server
try{
    $hvserver = Connect-HVServer $hvserver_input -User $hvusername"@"$hvuserdomain -Password $hvpassword
    $Global:services = $hvserver.ExtensionData
    $hvserver
} catch {Fail-Json -obj $result "check credentials en pre-requisites"}


foreach ($pool in $poollist) {
    $poolcheck = Get-HVPool -Poolname $pool.name
    if ( $poolcheck -like '*No Pool Found with given search parameters*' ){
        try {
            Get-HVPool -Poolname $hvtemplatepool | New-HVPool -Poolname $pool.name -NamingPattern $pool.vdi
            Start-Sleep -Seconds 5
            Set-HVPool -PoolName $pool.name -Key automatedDesktopData.vmNamingSettings.patternNamingSettings.maxNumberOfMachines -Value $pool.poolsize
            $result.created += $pool.name + " wordt gemaakt"
            $result.changed = $true
        } catch {Fail-Json -obj $result "onbekende fout bij pool creatie"}
    }
    elseif ( $poolcheck.Base.Name -eq $pool.name){
        $result.exists += $poolcheck.Base.Name + " bestaat al"
    }
}

if ( $null -ne $addentitlement.entitlement ){
    foreach ($entitlementpool in $addentitlement){
        $entitlecheck = (Get-HVEntitlement -ResourceName $entitlementpool.name -ResourceType Desktop).Base.Name
        if ($entitlecheck -eq $entitlementpool.entitlement){
            $result.entitle_exists += "de toewijzing " + $entitlementpool.entitlement + " bestaat al"
        }
        else {
            try{
                $entitleduser = $entitlementpool.entitlement
                $newentitlement = New-HVEntitlement -User $entitleduser'@'$hvuserdomain -ResourceName $entitlementpool.name -Type 'group'
                if ($newentitlement -like '*Unable to find specific user or group with given search parameters*'){
                    $result.entitle_error += "de groep voor entitlement " + $entitlementpool.name + " doe not exist"
                    $result.failed = $true
                }
                else {
                    $newentitlement
                    $result.entitled += $entitlementpool.entitlement + " toegevoegd aan pool " + $entitlementpool.name 
                    $result.changed = $true
                }
            } catch { Fail-Json -obj $result "er gaat iets mis bij het aanmaken van entitlement" + $entitlementpool.name }
        }
    }
}

Exit-Json -obj $result
