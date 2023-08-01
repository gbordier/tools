# tools
This repo contains the old Win32 based tools for handling security within Windows.
those tools should work in ALL version of Windows (since NT4 :) )

# Command Line Tools
## [FILEACL](./fileacl/FILEACL.md)
Manages NTFS file ACLs locally or remotely, including  NASes. Leverages SeBackupPrivilege to read non-accessible NTFS permissions when /FORCE is used and user is administrator.

## [XDIR](./xdir/XDIR.md)
Calculates folder content size traversing all hierarchy including non-accessible ones using /FORCE switch when user is administrator.


# Azure related 
## Powershsll 
### [CopyVMCrossTenant](https://github.com/gbordier/CopyVMCrossTenant) is a tool to copy Azure Virtual Machines from One Tenant to the Other while doing some modifications 
- transform blob storage disks to Managed disks
- update dns info
- create underlying vnets and subnets

  
## Infras As Code (Bicep)
### DevBox Templates Bicep creation  [DevBox-Demo](https://github.com/gbordier/devbox-demo)
