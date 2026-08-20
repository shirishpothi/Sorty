# Permiso

Permiso is Sorty's local macOS permission guide package. Its source-to-Settings
flight and draggable app card are based on the interaction described by
[AskForPermission](https://github.com/riko2chen/AskForPermission).

Sorty uses the drag target and a decorative Drag cue only for flat TCC lists
such as Full Disk Access. Automation and Notifications show a non-draggable
guide for the control macOS expects the user to change. Files & Folders stays
on `NSOpenPanel`, which grants access through the folder picker rather than
System Settings.

On macOS 26 and later, the guide uses `NSGlassEffectView`. Earlier macOS
versions retain the native popover material fallback.
