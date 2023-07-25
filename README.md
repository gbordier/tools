# tools
This repo contains the old Win32 based tools for handling security within Windows.
those tools should work in ALL version of Windows (since NT4 :) )

# Main Tools
## FILEACL
Manages NTFS file ACLs locally or remotely, including  NASes. Leverages SeBackupPrivilege to read non-accessible NTFS permissions when /FORCE is used and user is administrator.

## XDIR
Calculates folder content size traversing all hierarchy including non-accessible ones using /FORCE switch when user is administrator.

