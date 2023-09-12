<html>
<meta name="google-site-verification" content="O6a3XUVrky2UH1ImDuQMycZhvLMpAyacOcNat0iIdhk" />
</html>

# tools
This repo by Guillaume Bordier contains the old Win32 based tools for handling security within Windows as well as other 
those tools should work in ALL version of Windows (since NT4 :) )

# Command Line Tools
## [FILEACL](./fileacl/FILEACL.md)
Manages NTFS file ACLs locally or remotely, including  NASes. Leverages SeBackupPrivilege to read non-accessible NTFS permissions when /FORCE is used and user is administrator.
Old copies of this currently exist at [am.net(https://am.net/lib/tools/AM/fileacl.2.8.0.3.htm)] but I cannot vouch for the content served there which is why I decided to re-publish this tool.

## [XDIR](./xdir/XDIR.md)
Calculates folder content size traversing all hierarchy including non-accessible ones using /FORCE switch when user is administrator.
