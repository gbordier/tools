FILEACL changelog



**What's new? :** 

3.0.2.2 corrected a regression that loops when a non existing trustee is given 

handling NT "VIRTUAL MACHINE" authority.

3.0.2.1 added new authorities in RawSID

3.0.2.0 disabled SysWow64 file redirection for x64 so that System32 goes to System32 and not SysWow64
[Filesystem redirection](https://learn.microsoft.com/en-us/windows/win32/api/wow64apiset/nf-wow64apiset-wow64disablewow64fsredirection) 

3.0.1.8 added support for \\?\Volumes...

3.0.1.7 march 08 :: add a new error code 

3.0.1.6 backed out of a nasty bug with UNC introduced in 3.0.1.5 

​            Do not follow hard links and junction points anymore (useful for Vista)

​            Corrected bug with /targetpwd

3.0.1.5       create Execute2 method for invocation by JavaScript or other scripting language that do not support Output parameters, read the output of the Execute2 method on the Output Property added /FULLRAWSECDESC that gives a full security descriptor (not just the DACL)

 

3.0.1.4       long hunt for the lost buffer :( FILEACLCOM.dll does not leak a byte anymore!

 

3.0.1.3       corrected the /VERBOSE bug as well as changed the behavior of /QUOTE when not in /BATCH mode, 

​            add the quotes even for the root drive

3.0.1.2       corrected two bugs : 

\- /O with a SID would truncate the last part from a SID

\- /NODIRS was not impling /FILES

3.0.1.1 corrected a sid lookup optimization bug where fileacl was confused by some well known sids (thanksWilfred Wong)

3.0.1.0 corrected a printing bug that prevented FILEACL COM version from writing to a file

3.0.0.9 corrected pointer bug in SAM lookup, correct unsigned long integer SID bug !!!. Thanks to Rytis Lietuvaitis for those one.

3.0.0.8 corrected SAM lookup logic when using DFS shares (for settings ACLs)

3.0.0.7 corrected SAM lookup logic when using DFS shares

3.0.0.6       corrected bug that would not write textual SID if the SID is not found
 corrected bug that would prevent /INHERIT /SUB /FILES without ACE

3.0.0.5 corrected the /BATCH error that has been wrong for DENY since 2.9.4 

3.0.0.4 corrected /SIMPLE /OWNER combination that failed (thanks to Robin)

3.0.0.3 corrected two bugs in /BATCH and /BATCHREAL thanks to Franco Fassio
           First /BATCH was not quoting the directory names as expected, second, /BATCHREAL was not including /PROTECT at the end of the first line 

3.0.0.2 re-activated /BATCHREAL which was lost somewhere 

3.0.0.1 corrected a bug with the COM interface thanks to Daniel Merriott 

3.0.0.0 Large code refactoring, added cached credential to speed up 

2.9.0.7 Small bug fixes 

2.9.0.6      Added /OUTPUT, /ANSI and /UNICODE to handle output file 

2.9.0.5      Corrected ACL overflow with very large ACLs 

2.9.0.4      Corrected RWXDDc (every right except ownership and write permissions) may appear as “F” (Full Access) in display mode. Use /ADVANCED to show detailed rights. 

2.9.0.3 (nov 04) 

​            added /TARGETDC /TARGETUSER, /TARGETPWD and /NODISCONNECT         

2.9.0.1 (sept 04) 

​            added /SILENT option and corrected a bug thanks to Dave Heap 

corrected dependencies in fileaclcom.dll that would require msvcrt71.dll ! 

2.9.0.1 

​            added /SILENT option and corrected a bug in CreateAcl when no pRights structure was passed 

​            thanks to Dave Heap 

​            corrected dependencies in fileaclcom.dll that would require msvcrt71.dll ! 

 2.9.0.0 

​            First version of the COM interface 

​            Beware of the UNICODE macro in the COM project file 

​            huge factorization in the code , 

​            thread safe, no more globals, every global parameteres are passed to each function within the "Globals*" pointer 

​            added 'N' rights that map to 0 permissions but is not interpreted as "do not put permissions but rather as "put zero access permissions" 

​            Thanks to Norm Schulz for testing 

2.8.1.2 problem with files seem to be solved 

2.8.1.1 converted the whole stuff to Unicode and fixed some minor bugs 

2.8.0.6 added /quote as default for /batch mode + small memory leak correction 

2.8.0.4 empty DACL corrected + enable /NOINHERITED in /RAWSECDESC mode 

2.8.0.3 minor bug fix 

2.8.0.2 (April 2004) Documented the /ADVANCED option, fixed Dc (delete subdir ) right bad interpretation in display mode
       works (again) on NT 4.0           

2.8.0.1 (March 2004) Added Inheritance specification including propagation block after first level
       Corrected a display problem for multiple permissions aces 

2.7.8.4 Corrected /BATCH problem 

2.7.8.3 Corrected a regression from 2.7.8.2 when used in the localsystem context 

2.7.8.2 Corrected problem with cluster virtual names, added a filemask feature to scope only specific files (and no dirs)
        Just use fileacl c:\temp\*.exe ……. To use it. 

2.7.8.0 New feature : Error Codes, better stability with /FORCE 

- Got rid of forcesecdescread function that used backupRead to read     security descriptor 
- Removed all unreferenced variable 
- Corrected a bad buffer in AddSecurityRighsts (tokinfo) 
- Rewrote argument parsing to deal with "c:\" kind of files     with quotes (suggested by 

Jérôme Labriet) 

- Corrected problem when /O was before /S or other perm with the     /REPLACE flag 
- Added Error Codes 
- Corrected problem with setting ownership under Windows 2003 

2.7.7.4 Changed /BATCH behavior not to print quotes in any situation on root drives due to problem handling file name with trailing backslash 

2.7.7.3 Corrected /BATCH problem with owner thanks to Andria Henintsoa (again) 

2.7.7.2 Corrected Write perms right not being displayed in standard mode thanks to Andria Henintsoa 

2.7.7.1 Corrected a glitch in /BATCH /OWNER option with a misplaced 

2.7.7.0 Added /REMOVEDENY option to remove any deny ace from source ACL 

2.7.6.9 corrected the problem with "c:\" /quote 

2.7.6.8 Corrected bug about directories with names beginning with a dot (thanks to Laurent.MAZIER@teleca.fr) 

2.7.6.7 Added the /QUOTE option upon very good suggestion from jerome.labriet@ac-besancon.fr 

2.7.6.6 Fixed bad behavior when using SID form for trustees 

2.7.6.5 Minor fixes in recursive mode 

2.7.6.4 Minor fixes 

2.7.6.1 Recompiled with VC 7.0 + minor doc changes 

2.7.6 Fixed a Handle Leak and /FILES with only /INHERIT (Inheritance bit only, no rights) 

2.7.5 Added /NODIRS option to treat only files and not Directory 

2.7.4 Corrected a problem with Access Deny aces and synchronize right beeing wrongly added to a deny ace 
 corrected a problem with U/R/R type rights 

2.7.3 [WIN2K] added /RAWSECDESC which prints the security descriptor textually with ConvertSecurityDescriptorToStringSecurityDescriptor Corrected a bug in /INHERIT with no arguments. added a createacl case 

2.7.2 Fixed some /batch option display problems 

2.7.1 many improvements, auto-propagation for Windows 2000, batch mode ... 

2.6.7 fixed a small bug with /force where you have read but not write access on ressource 

2.6.6 fixed new Win2K account lookup problem
 fixed /FORCE problem with recursive features 

2.6.5 corrected bad file mask due to Win2k compliance (null mask) 

2.6.4 corrected bad mask for DENY + only one ace (0x3) for folder/files/subfolders in WIN2K 

2.6.3 corrected problem with accounts in different domains 

2.6.2 better support for DENY access, sorting ACEs DENY first , other after ! 

2.6.1 reworked the examinemask function to make it generic (use with regacl) added support for special file and named pipes (\\.\a: ...) removed filtering of 0 mask as well as NULL PACL 

2.6.0 : W2K compliant added 0x10 inheritance + special WRITE access masks bug repair : LookupAccountName was passed a null pointer in some cases ! 

2.5.3 : code cleanup, added currentworkingdir /RAWSID /RAWMASK 2.5.2 : added FAT detection 
