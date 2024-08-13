Import-Module VMware.PowerCLI

$vCenterServer = ""
$username = ""
$password = ""
$securePassword = ConvertTo-SecureString $password -AsPlainText -Force
$credential = New-Object System.Management.Automation.PSCredential ($username, $securePassword)

Connect-VIServer -Server $vCenterServer -Credential $credential | Out-Null

$vms = Get-VM
$vmDetailsList = @()

foreach ($vm in $vms) {
    $vmDetails = "" | Select-Object VMID, Name, Folder, CreatedDate, CPUCount, CPUUsage, RAMAllocated, RAMUsage, DiskUsage, HasSnapshot, IsBackedUp, IPAddress, OS, Tags, BackupSolutions

    $vmDetails.VMID = $vm.Id
    $vmDetails.Name = $vm.Name
    
    # Handle Folder Retrieval
    try {
        $vmDetails.Folder = (Get-Folder -Id $vm.FolderId).Name
    } catch {
        $vmDetails.Folder = "No Folder"  # Default value if folder cannot be found
    }

    # Retrieve VM View
    $vmView = Get-View -Id $vm.Id

    # Handle CPU Count
    try {
        $cpuCount = $vmView.Summary.Config.NumCpu
        $vmDetails.CPUCount = if ($cpuCount) { $cpuCount } else { 0 }
    } catch {
        $vmDetails.CPUCount = 0
    }

    # Handle CPU Usage
    try {
        $cpuUsage = $vmView.Summary.QuickStats.OverallCpuUsage
        $vmDetails.CPUUsage = if ($cpuUsage) { $cpuUsage } else { 0 }
    } catch {
        $vmDetails.CPUUsage = 0
    }

    # Handle RAM Allocation
    try {
        $ramAllocated = $vmView.Config.Hardware.MemoryMB
        $vmDetails.RAMAllocated = if ($ramAllocated) { [math]::Round(($ramAllocated / 1024), 2) } else { 0 }
    } catch {
        $vmDetails.RAMAllocated = 0
    }

    # Handle RAM Usage
    try {
        $ramUsage = $vmView.Summary.QuickStats.GuestMemoryUsage
        $vmDetails.RAMUsage = if ($ramUsage) { [math]::Round(($ramUsage / 1024), 2) } else { 0 }
    } catch {
        $vmDetails.RAMUsage = 0
    }

    # Handle Disk Usage
    try {
        $diskUsage = $vmView.Summary.Storage.Committed
        $vmDetails.DiskUsage = if ($diskUsage) { [math]::Round(($diskUsage / 1GB), 2) } else { 0 }
    } catch {
        $vmDetails.DiskUsage = 0
    }

    # Handle Created Date
    if ($vmView.Config.CreateDate) {
        $vmDetails.CreatedDate = $vmView.Config.CreateDate.ToString("yyyy-MM-dd HH:mm:ss")
    } else {
        $vmDetails.CreatedDate = "0000-00-00 00:00:00"
    }

    # Handle Snapshot and Backup Information
    try {
        $snapshots = Get-Snapshot -VM $vm -ErrorAction SilentlyContinue
        $vmDetails.HasSnapshot = if ($snapshots) { "OUI" } else { "NON" }

        # Initialize counts
        $nakivoCount = 0
        $veeamCount = 0

        # Count occurrences of "NAKIVO" and "VEEAM"
        foreach ($snapshot in $snapshots) {
            $nakivoCount += ([regex]::Matches($snapshot.Description, "NAKIVO")).Count
            $veeamCount += ([regex]::Matches($snapshot.Description, "VEEAM")).Count
        }

        # Set IsBackedUp and BackupSolutions
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

    # Handle IP Address and OS
    try {
        $vmDetails.IPAddress = $vmView.Guest.IpAddress -join ", "
        $vmDetails.OS = $vmView.Guest.GuestFullName
    } catch {
        $vmDetails.IPAddress = "0.0.0.0"
        $vmDetails.OS = "Unknown"
    }

    # Handle Tags Retrieval
    try {
        $tags = Get-TagAssignment -Entity $vm
        $vmDetails.Tags = ($tags | Select-Object -ExpandProperty Tag).Name -join ", "
    } catch {
        $vmDetails.Tags = "No Tags"  # Default value if tags cannot be retrieved
    }

    $vmDetailsList += $vmDetails
}

$jsonOutput = $vmDetailsList | ConvertTo-Json -Depth 3
$filePath = "C:\Users\Mohamed\Desktop\vmDetails.json"
$jsonOutput | Out-File -FilePath $filePath -Encoding utf8

Disconnect-VIServer -Server $vCenterServer -Confirm:$false | Out-Null
