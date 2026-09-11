@echo off
rem Starts the field app from wherever this folder is. The .exe needs the DLLs and data folder beside it.
start "" /D "%~dp0ScientistOutreachPortal-Windows" "%~dp0ScientistOutreachPortal-Windows\ScientistOutreachPortal.exe"
