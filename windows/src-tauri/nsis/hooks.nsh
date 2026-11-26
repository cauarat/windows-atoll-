; Install and uninstall hooks for the NSIS installer.
;
; The inbox and the log live in %LOCALAPPDATA%\Coucou, outside the install
; directory, so the installer never recorded them and the default uninstaller
; would leave them behind. They are ours, and uninstalling takes them.
;
; %LOCALAPPDATA%\Coucou\bin is deliberately left alone. Builds before the coding
; agents went copied coucou-hook.exe, Claude Code's relay, there at every
; launch, and anyone who wired Claude Code up named that path in their own
; %USERPROFILE%\.claude\settings.json. Nothing ships or copies the relay any
; more, but a copy already there keeps that entry harmless: with no Coucou
; listening it exits 0 at once and prints nothing. Deleting it would turn every
; Claude Code hook event into a "command not found" error in somebody's
; terminal, and their settings.json is theirs to edit, not ours.

; Adopt an install made before the app was renamed.
;
; The NSIS install directory and the uninstall registry key both come from
; ${PRODUCTNAME}, never from the bundle identifier. The template looks for a
; previous install under Software\${MANUFACTURER}\${PRODUCTNAME} and falls back
; to $LOCALAPPDATA\${PRODUCTNAME}; the identifier appears in none of those
; lookups. So the moment this stopped being called Coucou, every installer
; stopped being able to see the copies that still were. It writes a second
; install beside the first, leaves the old exe where it is, and leaves that
; copy's Run entry and shortcuts pointing at it.
;
; Both then start at login, and the single-instance mutex is `<identifier>-sim`
; on both sides of the rename — one string, no version in it — so whichever
; copy wins the race makes the other exit immediately. When the old one wins it
; is the one drawing the window, and a correctly installed new version looks
; like an install that silently did nothing.
;
; The old uninstaller is deliberately NOT run, and the old directory is
; deliberately NOT removed. Before the rename the install directory *was*
; $LOCALAPPDATA\Coucou — which is still where this app keeps its log and its
; inbox today, beside the relay older builds staged. A Tauri uninstaller
; removes its install directory whole, so running it here would take the live
; data with it. Only the two files that are the old install get deleted;
; everything else in that folder is ours and in use.
!macro NSIS_HOOK_PREINSTALL
  IfFileExists "$LOCALAPPDATA\Coucou\Coucou.exe" 0 adopt_done

    ; The template only closes $INSTDIR\${MAINBINARYNAME}.exe, which is the new
    ; name, so it never matches the copy that is actually running.
    nsExec::Exec 'taskkill /F /IM "Coucou.exe"'
    Pop $0

    Delete "$LOCALAPPDATA\Coucou\Coucou.exe"
    Delete "$LOCALAPPDATA\Coucou\uninstall.exe"

    ; tauri-plugin-autostart names its value after the product, so the old one
    ; is a separate entry that nothing else will ever clean up.
    DeleteRegValue HKCU "Software\Microsoft\Windows\CurrentVersion\Run" "Coucou"
    DeleteRegValue HKCU "Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run" "Coucou"

    ; And the row in Settings -> Apps, which would otherwise offer to run an
    ; uninstaller that is no longer there.
    DeleteRegKey HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\Coucou"
    DeleteRegKey HKCU "Software\Louis Raille\Coucou"

    Delete "$DESKTOP\Coucou.lnk"
    Delete "$SMPROGRAMS\Coucou.lnk"
    Delete "$SMPROGRAMS\Coucou\Coucou.lnk"
    RMDir "$SMPROGRAMS\Coucou"
    Delete "$SMSTARTUP\Coucou.lnk"

  adopt_done:
!macroend

!macro NSIS_HOOK_PREUNINSTALL
  RMDir /r "$LOCALAPPDATA\Coucou\inbox"
  Delete "$LOCALAPPDATA\Coucou\coucou.log"
!macroend
