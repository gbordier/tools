# FILEACL [Download](./files/fileacl.exe)
the return of the old FILEACL that has been around since before the beginning of the century :) 
According to email I receive and a few reviews such as [https://www.serverbrain.org/system-administration/taking-file-ownership.html] there as still a few people relying on this so I took a (last?) stab at this and compiled a fresh version.

see [ChangeLog](./ChangeLog.md)

FILEACL is an win32 console  free software by Guillaume Bordier that deals with NTFS Permissions on file systems.

FILEACL is **Freeware**.    

This SOFTWARE is owned and copyrighted by Guillaume Bordier. Your license  confers no title or ownership in the SOFTWARE and should not be construed as  a sale of any right in the SOFTWARE.    

You may distribute unlimited copies of this program in its **original form**  to any legal place.  

You may NOT distribute FILEACL into any sold product or software package  without express and written clearance from the author.   

Downloading FILEACL means you agree with  the terms above   

*FILEACL comes in two main versions:*    

- command line version
- COM Automation version that can be incorporated into scripts 



## History 

FILEACL has been around since 1997 and predates ICACLS which appeared in Windows Vista to handle detailed ACLs in NTFS. 

Its syntax is less complex than ICACLS and it is usually faster. 

the main use cases for FILEACL are

- read and reapply the same NTFS structure without actuall copying it (FILEACL /BATCH will produce a batch file to reapply permissions after the fact)
- inventory or apply permission on a large set of files and folder, accureately controlling inheritance ...



## Features

*Here are its features:* 

·     *View ACLs on any NTFS local or remote drive* 

·     *Set ACLs on any NTFS local or remote*

·     *View Ownership* 

·     *Change Ownership* 

·     *Uses Backup and Restore Rights to view/change ACL/ownership on non accessible files/dir* 

·     *recurse through files and directories* 

·     *[WIN2K] Inheritance auto-propogation aware* 

·     *shows RAW SID and/or Access Mask for an ACE* 

·     *Apply RAW SID and/or Access Mask (you could put ACL related to non-available domain trustees !)* 

·     *Address Deny rights* 

·     *Treats ALL inheritance matters of NTFS (unlike Windows NT 4.0 GUI)* 

·     *Batch Mode to dump permissions to a file and reapply later (/BATCH)* 

·     Dumping (saving) ACLs on large network shares 

·     Modifiy the resultant text file and restore it 

·     Accessing/viewing/modifying ACLs on Quota-locked directories. 

·     Change Ownership on dir/files 

·     Apply complex ACLs (complex Mask or complex inheritance scheme) 

·     debugging ACLs 



## Detailed Syntax 

Command Line : 

fileacl<File/Directory> 

[/{S|G|R|T|O|D} {trustee}:[[!]RWXDOPF][/[!]RWXDOPF][/[!]RWXDOPF] 

[options] 

 or 

  

fileacl<File/Directory> 

[/{S|G|R|T|O|D} {**trustee**}:[RWXDOPF] [:IO|OI|NP|CI|FO|F|FF|FSF|FS|SFF|SF 

[options] 

  

  

 

 

Main commands: 

| /S   | Set  permissions (overwrite any ACEs related to the trustee) |
| ---- | ------------------------------------------------------------ |
| /G   | Grant  permissions (enlarge ACEs related to the trustee)     |
| /R   | Revoke  trustee (deletes all ACEs related to the trustee)    |
| /T   | special :  Suppress all DENY ACEs for the trustee.           |
| /O   | Give ownership  to the trustee (require TakeOwnership privilege) |
| /D   | Put a  Deny Access ACE  instead of granting permission       |



**Trustee** could be user or group, domain\trustee or SID (S-1-x ....). 

Simple Rights 

| Right | Meaning   for Directories       | Meaning  for Files     |
| ----- | ------------------------------- | ---------------------- |
| R     | Read                            | Read                   |
| X     | Change  dir                     | Execute                |
| W     | Write                           | Write                  |
| D     | Delete                          | Delete                 |
| O     | Allowed  to take/give ownership | idem                   |
| P     | Write  permissions              | Write  permissions     |
| U     | Unspecified  (0 right)          | Unspecified  (0 right) |

  

Addotionnal Switches: 

| Display  mode Options         |                                                              |
| ----------------------------- | ------------------------------------------------------------ |
| /LINE                         | operate  in single-line mode display all ACEs on a file or directory on One row |
| /ADVANCED                     | Show  detailed rights                                        |
| /OWNER                        | Get the  owner name as well                                  |
| /NOINHERITED                  | do not  print inherited rights                               |
| /SIMPLE                       | Merge  inherited and direct ACL                              |
| /BATCH                        | Generate  a batch file for reapplying the same permissions, use with /SUB |
| /BATCHREAL                    | Batch  mode including inhirted right from the top level      |
| /RAW[SID\|MASK]               | Show the  RAW ACE SID and/or Mask                            |
| /RAWSECDESC                   | Show the RAW Security Descriptor with Textual Form ou may use this to  generate Win2K securitytemplates and apply them with secedit |
| /FULLRAWSECDESC               | Show the full RAW Security Descriptor with in SDDL syntax with SACL |
| /QUOTE                        | add  quotes to file and directory names (default with /BATCH) |
| /ANSI                         | Output  ANSI file                                            |
| /OUTPUT:<filename>            | output  stdout to a file                                     |
| /UNICODE                      | Output  text as Unicode Text (only for /OUPUT)               |
| Change  mode options          |                                                              |
| /PROTECT                      | This  permissions will be protected from upper levels permissions propagation  [WIN2K] |
| /INHERIT                      | Force  Propagation from upper levels [WIN2K]                 |
| /NOROOT                       | use with  /SUB, apply rights to all subdirs/subfile except the root dir |
| /REPLACE                      | deletes  existing ACL and replace with specified (SET )      |
| /NOPROPAGATE                  | Use old security API so that settings do not propagate to the lower  levels |
| /REMOVEDENY                   | Removes any Deny ACE from the folder / files                 |
| /SILENT                       | Do not display anything to the console                       |
|                               |                                                              |
| Both mode  options            |                                                              |
| /SUB[:n]                      | treats n  levels of subdirectories as well                   |
| /FILES                        | treats  files in directories as well                         |
| /NODIRS                       | treats  files only                                           |
| /FORCE                        | uses  SeBackupPrivilege and SeRestorePrivilege to Treat Objects without any rights  nor ownership |
| /NT4                          | Enforce  NT 4.0 compatibility for Write Masks later version will test dest computer |
| /TARGETDC:<domain controller> | Get the  account information from the specified DC (connects to the remote DC and  disconnects afterwards) |
| /TARGETUSER:<user>            | Give the  account name in case the current account does not have the right to connect  to the remote DC |
| /TARGETPWD:<pwd>              | Give the  password in case the current account does not have the right to connect to  the remote DC |
| /NODISCONNECT                 | (use with  /TARGETDC) Do not disconnect from the DC each time to save the connection  overhead |
|                               |                                                              |

  

FILEACL use a more accurate inheritance scheme and allow for "apply toobjects and sub-folders in this folder only"
 With standard FILEACL syntax, just add “**!**” in front of your access mask to limit propagation to the first level. 

Ex: 

FILEACL c:\temp\testacl /s user:R/**!**W/F will limit inheritance of Write access for files to the testacl directory. 

You also can use a different syntax adding your inheritance flag manually at the end of a single mask command line. 

Inheritance can be set using the following inheritance  : 

Inheritance flags are added to the mask after "**:**"

| Flag with  first syntax | Syntax 2 | Meaning                                                      |
| ----------------------- | -------- | ------------------------------------------------------------ |
| FO                      | FO       | Folder  Only                                                 |
| F                       | OI/IO    | Files  only / Inherit Only + Object Inherit                  |
| FF                      | OI       | Folder  and Files / Object Inherit                           |
| FSFF                    | CI/OI    | Folder  and subfolders and Files / Container Inherit + Object Inherit |
| FSF                     | CI       | Folder  and subfolders / Container Inherit                   |
| SF                      | CI/IO    | Subfolders  / Container Inherit + Inherit only               |
| SFF                     | CI/OI/IO | Subfolders  and Files / Container Inherit + Object Inherit + Inherit only |
| NP                      | NP       | Non  Propagation, can be appended on either of the later     |

FILEACL c:\temp\testacl /s user:R/!W/F 
 Would then translate into 
 FILEACL c:\temp\testacl /s user:R:FO /s user:W/F/NP /s user:F:SF
 or
 FILEACL c:\temp\testacl /s user:R:FO /s user:W/OI/IO/NP /s user:F/CI/IO 

Error Codes: 

| 0    | Success                  |
| ---- | ------------------------ |
| 100  | Return  usage            |
| 101  | Bad OS  version          |
| 102  | Bad  syntax              |
| 103  | Bad path                 |
| 104  | Bad  fileSystem          |
| 105  | Error  adding ACL        |
| 106  | Error  setting ownership |
| 107  | Error  listing ACLs      |
| 108  | Error  reading directory |
| 109  | Bad  Inheritance Flag    |

## Command Line Samples

Typical : 

FILEACL d:\temp\acltest /S user1:RW 

gives Read/Write access on directory d:\temp\acltest to trustee user1 

 

FILEACL [\\server\share\dir](file://server/share/dir) /S admingroup1:F /S usergroup1:RX/W/D /O admingroup1 /SUB:3 /FILES 

give admingroup1 Full right to network dir, and give usergroup1 RX to dir; right to modify existing files to dir, and delete files on 3 sub-levels of directories and files. 

admingroup1 is set as owner for all files and dirs 

 

FILEACL [\\server\share\dir](file://server/share/dir) /S S-1-5-21-1606980848-1383384898-842925246-1008:R 

give Read right to a user given its SID, even if the DC for that domain is not online or the account is not created/synchronized yet ! 

or even : 

FILEACL [\\server\share\dir](file://server/share/dir) /S S-1-5-21-1606980848-1383384898-842925246-1008:0x120089/0x100116 

to set a special mask 

 

FILEACL d:\temp\acltest /INHERIT /REPLACE  

Reset permissions and allow propagation from upper levels 

 

FILEACL d:\temp\acltest /owner /raw 

gives ACEs (one trustee per line) and owner with RAW sid and access mask 

 

**What are ACL and ACE ?** 

ACE stands for Access control entry, it specifies : 

·     a trustee 

·     an access mask 

·     an ACE type (could be deny ACE, audit ACE) 

·     an inheritance flag 

ACL stands for Access control List, it is a list of ACEs. 

 

**What does ACLs levels means ?** 

Multi-level ACLs treat inheritance (ONLY for directories !) 

**If you see/give one level 
 (/S trustee:RW = /S trustee:RW/RW/RW )** 

ACL is built with RW rights for the directory, and all inherited files and sub-directories. 

 

**If you see/give two levels of ACE 
 (/S trustee:RW/X = /S trustee:RW/X/RW )** 

ACL is built with RW rights for the directory and all inherited sub-directories, and X right for all inherited 

 

**If you see/give three levels of ACE 
 (/S trustee:RW/X/R )**

ACL is built with RW rights for the directory, X right for inheriting files and R right for inheriting sub-directories. 

 

**Difference between OSes** 

NT4 SP3, NT4 SP4 and later and Windows 2000 treats ACLs in a slightly different manner :

 

NT4 SP3 uses GENERIC_RIGHTS (ie 0x10000000 to 0x80000000 access masks) to grant access to files and inherited files. 

 

NT4 SP4 and later do not use GENERIC_RIGHTS any more (although it understands it), it uses the same masks for directories and files masks. 

 

On directories NT4 (All sps) always build a 2 ACEs ACL for a trustee, 

First ACE is set with Directory Inherit flag (0x2). 

Second ACE is set with Files inherit only flag (0x9). 

This means that the first ACE addresses the directory and its inherited sub-directories, and the second ACE addresses only inherited files. 

In only one case does NT4 build a single ACE ACL for a trustee : 

When you select "Take ownership" for a directory, it deletes the ACL and replace it with a 0x3 ACE (Inherit on files and directories). 

 

Windows 2000 is much more consistent about all that : it only create separate ACE if needed, each time a single ACE can be used, it is. 

 

**Differences in Access Masks :** 

Windows 2000 does not need READ_CONTROL (0x20000) mask for writing to a directory and NT4 does need it. 

A Write ACE would typically be (0x120116) with NT4 and (0x100116) with Windows 2000, be sure to use /NT4 switch if your ACLs will be read by NT 4.0 workstation . 

 

Windows 2000 introduce "Delete file and subfolder" right (0x110040). 

 

Windows 2000 has an Autopropagation feature, all rights on a parent are propagated on children. 

FILEACL keeps the protection status of a folder unless /PROTECT or /INHERIT 

Go Windows 2000 now ! 

 

Questions ? : [this](../contact.htm) 

OUTPUT : 
 d:\test;Administrators:F[I] Administrators have Inherited Full Control from Autopropagation([I]) 
 d:\test;Everyone:F/RWEveryone has Full Control over this directory and future sub-directories and RW on future Files
 d:\test;Guest:F/W/RGuest has Full Control in the dir, W on future files, and Read on future subdirs


 **Detailed Rights** 

| Right | Meaning   for Directories             | Meaning  for Files                |
| ----- | ------------------------------------- | --------------------------------- |
| Rr    | List  Directory                       | Read Data                         |
| Ra/Wa | Read /  Write Attributes              | Read /  Write Attributes          |
| Re/We | Read /  Write Extended Attributes     | Read /  Write Extended Attributes |
| X     | Change  dir                           | Execute                           |
| Ww    | Add Files  to directory               | Write  Data                       |
| A     | Add  subdir to directory              | Append  data to file              |
| D     | Delete                                | Delete                            |
| Dc    | Delete  Child (sub file or sub dir);  | No  Meaning                       |
| O     | Allowed  to take/give ownership       | idem                              |
| p/P   | Read /  Write Permissions             | Read /  Write Permissions         |
| U     | Unspecified  (0 right)                | Unspecified  (0 right)            |
| R     | Rr+Ra+Re+p                            |                                   |
| W     | Ww+A+Wa+We+P  (NT4 : W=Ww+A+Wa+We+P+p |                                   |


 **File Deletion** is performed if : 
 Parent dir has Rr and Dc access OR file has D 

Minimum Access for reading a file is Rr on parent dir and RrRep on file
 Minimum Access for saving an open file is Rr on parent and RrRepW on file 
 Minimum Access for creating new file is Ww on parent dir
 Minimum Access for creating new dir is A on parent dir 

Access masks are defined this way : 

  

| 31   | 30   | 29   | 28   | 27       | 26   | 25                      | 24                             | 23   | 22   | 21   | 20   | 19   | 18   | 17   | 16   | 15   | 14   | 13   | 12   | 11   | 10   | 9    | 8    | 7    | 6    | 5    | 4    | 3    | 2    | 1    | 0    |
| ---- | ---- | ---- | ---- | -------- | ---- | ----------------------- | ------------------------------ | ---- | ---- | ---- | ---- | ---- | ---- | ---- | ---- | ---- | ---- | ---- | ---- | ---- | ---- | ---- | ---- | ---- | ---- | ---- | ---- | ---- | ---- | ---- | ---- |
| GR   | GW   | GE   | GA   | Reserved | AS   | Standard  Access Rights | Object-Specific  Access Rights |      |      |      |      |      |      |      |      |      |      |      |      |      |      |      |      |      |      |      |      |      |      |      |      |

GR = Generic Read 

GW = Generic Write 

GE = Generic Execute 

GA = Generic All

AS = Access to Audit ACL (SACL) 
