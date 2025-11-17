Set objShell = CreateObject("WScript.Shell")
Set objFSO = CreateObject("Scripting.FileSystemObject")

' Get the directory where this script is located
scriptDir = objFSO.GetParentFolderName(WScript.ScriptFullName)
psScript = scriptDir & "\Camerawatch.ps1"

' Run PowerShell completely hidden (window style 0 = hidden)
' Third parameter True = wait for the process to complete
' This keeps the VBS script running, which keeps the scheduled task in "Running" state
objShell.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & psScript & """", 0, True
