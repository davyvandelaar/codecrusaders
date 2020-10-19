#!powershell

# Copyright: Davy van de Laar
# GNU General Public License v3.0+ (see COPYING or https://www.gnu.org/licenses/gpl-3.0.txt)

#AnsibleRequires -CSharpUtil Ansible.Basic
#Requires -Module Ansible.ModuleUtils.Legacy

$ErrorActionPreference = "Stop"

# input parameters
$params = Parse-Args $args -supports_check_mode $true
$hvserver_input = Get-AnsibleParam -obj $params -name "hv_server" -type "str" -failifempty $true
$hvusername = Get-AnsibleParam -obj $params -name "hv_username" -type "str" -failifempty $true
$hvpassword = Get-AnsibleParam -obj $params -name "hv_password" -type "str" -failifempty $true
$hvuserdomain = Get-AnsibleParam -obj $params -name "hv_domain" -type "str" -failifempty $true
$poollist = Get-AnsibleParam -obj $params -name "hv_pool_list" -type "list" -element "str" -failifempty $true

$result = @{
    changed = $false
    exists = @()
    create = @()
    entitled = @()
    entitle_exists =@()
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
            Get-HVPool -Poolname 'wg_dev_w00001' | New-HVPool -Poolname $pool.name -NamingPattern $pool.vdi
            Start-Sleep -Seconds 5
            Set-HVPool -PoolName $pool.name -Key automatedDesktopData.vmNamingSettings.patternNamingSettings.maxNumberOfMachines -Value $pool.poolsize
            $result.create += $pool.name + " wordt gemaakt"
            $result.changed = $true
        } catch {Fail-Json -obj $result "onbekende fout bij pool creatie"}
    }
    elseif ( $poolcheck.Base.Name -eq $pool.name){
        $result.exists += $poolcheck.Base.Name + " bestaat al"
    }
}

Exit-Json -obj $result
