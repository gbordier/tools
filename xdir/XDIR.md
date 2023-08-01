# XDIR [Download](./files/xdir.exe)



XDIR is an win32 console  free software by Guillaume Bordier to deal with directories

XDIR has been around since the years 2000, like FILEACL it is able to use the Backup and Restore privileges to read through directory trees that the (admin) user does not have permissions to.

XDIR  is **Freeware**.    

This SOFTWARE is owned and copyrighted by Guillaume Bordier. Your license  confers no title or ownership in the SOFTWARE and should not be construed as  a sale of any right in the SOFTWARE.    

You may distribute unlimited copies of this program in its **original form**  to any legal place.  

You may NOT distribute XDIR into any sold product or software package  without express and written clearance from the author.   

Downloading XDIR means you agree with  the terms above   

*XDIR comes in two main versions:*    

- command line version
- COM Automation version that can be incorporated into scripts 



## Syntax

XDIR <Directory> [/MIN:xxx\[GB|MB|KB|B]\] \[/LEV:xx\]\[/RMDIR\]



## Features

XDIR has 3 modes

- list directory [/DIR]

- list directories with size [/DIRUSE, default mode]
- delete directoy trees [/RMDIR]



Mode switches:
/DIRUSE			[default] calculate size for directory and first level of subdirs, diruse like
/RMDIR			!!!! this will DESTROY the directory and all sub elements!!!!! (like rd /Q /S)
/DIR						will list directory content with sizes

if XDIR is renamed /  linked to RMDIR.EXE the mode will default to /RMDIR.



## Detailed Syntax 

Default Behaviors:
[Directory Size mode] will use those values as default:

- list one level of subdirectories (like diruse /*) (change with /LEV)
- list only subdirectories that containt 500 MB or more (change with /MIN)
- automatic unit detection (change with /UNIT)



| Option     | Description                                                  |
| ---------- | ------------------------------------------------------------ |
| /LEV:nn    | Deph to report                                               |
| /FORCE     | uses SeBackupPrivilege and SeRestorePrivilege to bypass NTFS ACLS (and read System Volume information for instance), in /RMDIR mode                        this WILL destroy really all data unless files are still open in the directory. |
| /UNIT:Unit | Unit can be TB,GB,MB,KB,B, defaults to "Auto"                |
| /MIN:xxxuu |Minimum size to report for each directory         |
| /ONLYCURRENT | don't inlcude subdirectories in the size of current directory         |
| /INCUDEREMOTE | includes non local content (onedrive content) in sum|
|/CSV | output in CSV format|
|/OUTPUT:<file name>   |output to file instead of screen|
|/ANSI    |               output as ANSI instead of trying to convert to OEM charset|
|/UNICODE|                outputs as UNICODE (valid only with /OUTPUT|
|/DEBUG      |            give debug information|
|/VERBOSE     |           give [many] debug information|



## Command Line Samples

```cmd
calculate size for a directory
        XDIR <Directory> [/MIN:xxx[GB|MB|KB|B]] [/LEV:xx]
        or :
        XDIR c:\temp /MIN:900MB /LEV:3

delete a subdirectory:
        XDIR <Directory> /RMDIR
        or
        RMDIR <Directory>

list a subdirectory
        XDIR <Directory> /DIR
        or
        LSDIR <Directory>

```




