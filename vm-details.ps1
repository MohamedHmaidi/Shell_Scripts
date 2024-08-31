Import-Module VMware.PowerCLI

$vCenterServers = Get-Content -Raw -Path "C:\ProgramData\BackendVcentre\vCentreServers.json" | ConvertFrom-Json

$vmDetailsList = @()

foreach ($vCenter in $vCenterServers) {
    $vCenterServer = $vCenter.VcenterServer
    $username = $vCenter.Username
    $password = $vCenter.Password
    $serverName = $vCenter.ServerName
    $securePassword = ConvertTo-SecureString $password -AsPlainText -Force
    $credential = New-Object System.Management.Automation.PSCredential ($username, $securePassword)

    Connect-VIServer -Server $vCenterServer -Credential $credential | Out-Null

    $vms = Get-VM

    foreach ($vm in $vms) {
        $vmDetails = "" | Select-Object VcenterServer, ServerName, VMID, Name, Folder, CreatedDate, CPUCount, CPUUsage, RAMAllocated, RAMUsage, DiskUsage, HasSnapshot, IsBackedUp, IPAddress, OS, Tags, BackupSolutions, TotalDisk, SSDUsage, SASUsage, NLSASUsage, OtherTypeUsage, PowerState

        $vmDetails.VcenterServer = $vCenterServer
        $vmDetails.ServerName = $serverName
        $vmDetails.VMID = $vm.Id
        $vmDetails.Name = $vm.Name
        $vmDetails.PowerState = if ($vm.PowerState -eq 'PoweredOn') { 'ON' } else { 'OFF' }

        try {
            $vmDetails.Folder = (Get-Folder -Id $vm.FolderId).Name
        } catch {
            $vmDetails.Folder = "No Folder"
        }

        $vmView = Get-View -Id $vm.Id

        try {
            $cpuCount = $vmView.Summary.Config.NumCpu
            $vmDetails.CPUCount = if ($cpuCount) { $cpuCount } else { 0 }
        } catch {
            $vmDetails.CPUCount = 0
        }

        try {
            $cpuUsage = $vmView.Summary.QuickStats.OverallCpuUsage
            $vmDetails.CPUUsage = if ($cpuUsage) { $cpuUsage } else { 0 }
        } catch {
            $vmDetails.CPUUsage = 0
        }

        try {
            $ramAllocated = $vmView.Config.Hardware.MemoryMB
            $vmDetails.RAMAllocated = if ($ramAllocated) { [math]::Round(($ramAllocated / 1024), 2) } else { 0 }
        } catch {
            $vmDetails.RAMAllocated = 0
        }

        try {
            $ramUsage = $vmView.Summary.QuickStats.GuestMemoryUsage
            $vmDetails.RAMUsage = if ($ramUsage) { [math]::Round(($ramUsage / 1024), 2) } else { 0 }
        } catch {
            $vmDetails.RAMUsage = 0
        }

        # Initialize disk usage counters
        $totalDisk = 0
        $ssdUsage = 0
        $sasUsage = 0
        $nlsasUsage = 0
        $otherTypeUsage = 0

        # Get disk information and calculate usage
        $disks = $vmView.Config.Hardware.Device | Where-Object { $_.GetType().Name -eq "VirtualDisk" }

        foreach ($disk in $disks) {
            $diskCapacity = $disk.CapacityInKB / 1MB
            $totalDisk += $diskCapacity

            $diskPath = $disk.Backing.FileName

            if ($diskPath -match "NLSAS") {
                $nlsasUsage += $diskCapacity
            } elseif ($diskPath -match "SSD") {
                $ssdUsage += $diskCapacity
            } elseif ($diskPath -match "SAS") {
                $sasUsage += $diskCapacity
            } else {
                $otherTypeUsage += $diskCapacity
            }
        }

        $vmDetails.TotalDisk = [math]::Round($totalDisk, 2)
        $vmDetails.SSDUsage = [math]::Round($ssdUsage, 2)
        $vmDetails.SASUsage = [math]::Round($sasUsage, 2)
        $vmDetails.NLSASUsage = [math]::Round($nlsasUsage, 2)
        $vmDetails.OtherTypeUsage = [math]::Round($otherTypeUsage, 2)

        try {
            $diskUsage = $vmView.Summary.Storage.Committed
            $vmDetails.DiskUsage = if ($diskUsage) { [math]::Round(($diskUsage / 1GB), 2) } else { 0 }
        } catch {
            $vmDetails.DiskUsage = 0
        }

        if ($vmView.Config.CreateDate) {
            $vmDetails.CreatedDate = $vmView.Config.CreateDate.ToString("yyyy-MM-dd HH:mm:ss")
        } else {
            $vmDetails.CreatedDate = "0000-00-00 00:00:00"
        }

        try {
            $snapshots = Get-Snapshot -VM $vm -ErrorAction SilentlyContinue
            $vmDetails.HasSnapshot = if ($snapshots) { "OUI" } else { "NON" }

            $nakivoCount = 0
            $veeamCount = 0

            foreach ($snapshot in $snapshots) {
                $nakivoCount += ([regex]::Matches($snapshot.Description, "NAKIVO")).Count
                $veeamCount += ([regex]::Matches($snapshot.Description, "VEEAM")).Count
            }

            $vmDetails.IsBackedUp = if ($nakivoCount -gt 0 -or $veeamCount -gt 0) { "OUI" } else { "NON" }
            $vmDetails.BackupSolutions = if ($vmDetails.IsBackedUp -eq "OUI") {
                "$nakivoCount with NAKIVO and $veeamCount with VEEAM"
            } else {
                ""
            }
        } catch {
            $vmDetails.HasSnapshot = "NON"
            $vmDetails.IsBackedUp = "NON"
            $vmDetails.BackupSolutions = ""
        }

        try {
            $vmDetails.IPAddress = $vmView.Guest.IpAddress -join ", "
            $vmDetails.OS = $vmView.Guest.GuestFullName
        } catch {
            $vmDetails.IPAddress = "0.0.0.0"
            $vmDetails.OS = "Unknown"
        }

        try {
            $tags = Get-TagAssignment -Entity $vm
            $vmDetails.Tags = ($tags | Select-Object -ExpandProperty Tag).Name -join ", "
        } catch {
            $vmDetails.Tags = "No Tags"
        }

        $vmDetailsList += $vmDetails
    }

    Disconnect-VIServer -Server $vCenterServer -Confirm:$false | Out-Null
}

$jsonOutput = $vmDetailsList | ConvertTo-Json -Depth 3
$filePath = "C:\ProgramData\BackendVcentre\vmDetails.json"
$jsonOutput | Out-File -FilePath $filePath -Encoding utf8
