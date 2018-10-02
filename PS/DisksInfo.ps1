$returnVolumes = New-Object System.Collections.ArrayList($null) 
Get-WmiObject Win32_DiskDrive | % {
  $disk = $_
  $partitions = "ASSOCIATORS OF " +
                "{Win32_DiskDrive.DeviceID='$($disk.DeviceID)'} " +
                "WHERE AssocClass = Win32_DiskDriveToDiskPartition"

  Get-WmiObject -Query $partitions | % {
    $partition = $_
    $drives = "ASSOCIATORS OF " +
              "{Win32_DiskPartition.DeviceID='$($partition.DeviceID)'} " +
              "WHERE AssocClass = Win32_LogicalDiskToPartition"
    

    Get-WmiObject -Query $drives | % {
      $returnVolumes.Add( (New-Object -Type PSCustomObject -Property @{
        Disk        = $disk.DeviceID
        Lun         = $disk.SCSILogicalUnit
        DiskSize    = "{0:N2}" -f ($disk.Size/1GB)
        DiskModel   = $disk.Model
        Partition   = $partition.Name
        RawSize     = "{0:N2}" -f ($partition.Size/1GB)
        DriveLetter = $_.DeviceID
        VolumeName  = $_.VolumeName
        Size        = "{0:N2}" -f ($_.Size/1GB)
        FreeSpace   = "{0:N2}" -f ($_.FreeSpace/1GB)
        VolumeUsed  = "{0:N2}" -f (($_.Size/1GB)- ($_.FreeSpace/1GB))
      })) 
    }
  }
}
$returnVolumes | ConvertTo-Json