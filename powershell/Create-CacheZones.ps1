<#
.Description
Sets or removes DNS Zones for caching in the DNS Service.

.PARAMETER EmergencyShutOff
Used to remove the cache DNS Zones from the DNS service. This will send all traffic to the normal internet address and disable caching.
 
.PARAMETER CacheIp
Sets the IP Address for each caching DNS Zone to <IPAddress>. Set to the IP of your caching server. Must be a valid IP address.
#>

[CmdletBinding(DefaultParameterSetName = 'Cache')]
Param(
    [parameter(ParameterSetName="Emergency")][Switch]$EmergencyShutOff,
    [parameter(ParameterSetName="Cache",mandatory=$true)][IPAddress]$CacheIp,
    [parameter(ParameterSetName="Cache",mandatory=$false)][switch]$StandaloneDns
)

$microsoftZones = @(
    [PSCustomObject]@{ Zone='download.windowsupdate.com'; Record='Both' },
    [PSCustomObject]@{ Zone='tlu.dl.delivery.mp.microsoft.com'; Record='Both' },
    [PSCustomObject]@{ Zone='officecdn.microsoft.com'; Record='Root' },
    [PSCustomObject]@{ Zone='officecdn.microsoft.com.edgesuite.net'; Record='Root' }
)

$googleZones = @(
    [PSCustomObject]@{ Zone='dl.google.com'; Record='Root' },
    [PSCustomObject]@{ Zone='gvt1.com'; Record='WildCard' }
)

$adobeZones = @(
    [PSCustomObject]@{ Zone='ardownload.adobe.com'; Record='Root' },
    [PSCustomObject]@{ Zone='ccmdl.adobe.com'; Record='Root' },
    [PSCustomObject]@{ Zone='agsupdate.adobe.com'; Record='Root' }
)

$zoneGroup = $microsoftZones + $googleZones + $adobeZones

function Set-CacheRecord {
    Param(
        [switch]$Wildcard,
        [switch]$Root,
        [string]$ZoneName
    )
    if ( $Wildcard ) {
        $record = Get-DnsServerResourceRecord -ZoneName $ZoneName -RRType A -Node '*' -ErrorAction Ignore
        if ( $record -and $record.RecordData.IPv4Address -ne $CacheIp ) {
            Remove-DnsServerResourceRecord -ZoneName $ZoneName -Name "*" -Confirm:$false
        }
        if ( !$record ) {
            Add-DnsServerResourceRecord -A -IPv4Address $CacheIp -Name "*" -ZoneName $ZoneName -TimeToLive 00:05:00
        }
    }
    if ( $Root ) {
        $record = Get-DnsServerResourceRecord -ZoneName $ZoneName -RRType A -Node '@' -ErrorAction Ignore
        if ( $record -and $record.RecordData.IPv4Address -ne $CacheIp ) {
            Remove-DnsServerResourceRecord -ZoneName $ZoneName -Name "@" -Confirm:$false
        }
        if ( !$record ) {
            Add-DnsServerResourceRecord -A -IPv4Address $CacheIp -Name "@" -ZoneName $ZoneName -TimeToLive 00:05:00
        }
    }
}

# Emergency shut off section removes all cache zones from DNS
if ( $EmergencyShutOff ) {
    $zoneGroup.ForEach{Remove-DnsServerZone -Name $_.Zone -Force -Confirm:$false}
}

else {
    foreach ( $z in $zoneGroup ) {
        try {
            $zone = Get-DnsServerZone -Name $z.Zone -ErrorAction Ignore
            if ( !$zone -and $StandaloneDns ) {
                Add-DnsServerPrimaryZone -Name $z.Zone -ZoneFile "$($z.Zone).dns" -DynamicUpdate None
            }
            elseif ( !$zone ) {
                Add-DnsServerPrimaryZone -Name $z.Zone -ReplicationScope Domain -DynamicUpdate None
            }
        }
        catch {
            $Error[0]
            break
        }

        switch ( $z.Record ) {
            'Both' {
                try {
                    Set-CacheRecord -Wildcard -Root -ZoneName $z.Zone
                }
                catch {
                    $Error[0]
                    break
                }
            }
            'WildCard' {
                try {
                    Set-CacheRecord -Wildcard -ZoneName $z.Zone
                }
                catch {
                    $Error[0]
                    break        
                }
            }
            'Root' {
                try {
                    Set-CacheRecord -Root -ZoneName $z.Zone
                }
                catch {
                    $Error[0]
                    break        
                }
            }
            default {
                Write-Host -ForegroundColor "Yellow" "$($z.Zone) 'Record' should be either 'WildCard', 'Root' or 'Both'"
            }
        }
    }
}