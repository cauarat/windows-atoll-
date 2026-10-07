Coucou for Windows — portable
=============================

Mochi lives at the top centre of your screen and keeps an eye on your
Claude Code sessions.

This is the portable build: no installer, nothing written to Program Files,
nothing added to the registry unless you ask for it below.


Quick start
-----------

1. Unzip this folder somewhere you will keep it, for example
   C:\Users\<you>\Apps\Coucou
   Do NOT run it from inside the .zip — coucou.exe needs coucou-hook.exe
   sitting next to it, and Windows hides that when previewing an archive.

2. Double-click coucou.exe

   There is no window and no taskbar entry. That is normal. Look for:
     - the island at the top centre of your screen (move the mouse up there)
     - the Mochi icon in the notification area, next to the clock

3. Right-click the notification-area icon -> Settings...
   -> Claude Code -> Install hooks...

   You will see the exact diff of what changes in
   %USERPROFILE%\.claude\settings.json and the path of the dated backup
   taken first. Nothing is written until you click. Your own hooks are
   never touched.

4. Start a Claude Code session in any terminal. Permission requests now
   appear in the island with Deny / Allow.


Make it feel like an installed app (optional)
---------------------------------------------

Double-click  Add to Start Menu.cmd

It creates a Start Menu shortcut, and asks whether you also want Coucou to
start when you sign in. It writes only to your own user profile and needs
no administrator rights. Run it again to remove what it added.


If Windows warns you
--------------------

These binaries are not code-signed yet. Windows has two separate guards
that react to that, and they do not have the same fix.

SmartScreen shows "Windows protected your PC".
  -> Click "More info", then "Run anyway".

Smart App Control shows "Smart App Control blocked an app that might be
unsafe", and offers no way past it -- no "run anyway", no per-app
allowance. Unzipping does not help: it inspects coucou.exe itself.
  -> Settings > Privacy & security > Windows Security >
     App & browser control > Smart App Control settings > Off
     (Since the April 2026 update this can be switched back on later.)

If Microsoft Defender quarantines a file, it is a false positive on
unsigned Rust binaries. Report it at
https://www.microsoft.com/wdsi/filesubmission and, if you want to run it
meanwhile, add the folder under Windows Security -> Virus & threat
protection -> Manage settings -> Exclusions.


Where things are
----------------

  Log       %LOCALAPPDATA%\Coucou\coucou.log
  Relay     %LOCALAPPDATA%\Coucou\bin\coucou-hook.exe   (copied on launch)
  Settings  %APPDATA%\Coucou\
  API keys  Windows Credential Manager (never on disk)

No telemetry. Coucou only talks to services you configure yourself.


Uninstalling
------------

Run "Add to Start Menu.cmd" and choose remove, quit Coucou from the
notification-area icon, then delete this folder. To also remove the hooks,
use Settings... -> Claude Code -> Uninstall hooks first.
