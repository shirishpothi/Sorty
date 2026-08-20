# Permiso

Permiso is Sorty's local macOS permission guide package. Its source-to-Settings
flight and draggable app card are based on the interaction described by
[AskForPermission](https://github.com/riko2chen/AskForPermission). The flight
keeps both endpoints crisp, then uses a Gaussian blur bell curve at its apex.
The overlay reserves transparent space around the moving card so the blur halo
does not crop or shift the source button.

Sorty uses the drag target and a decorative Drag cue only for flat TCC lists
such as Full Disk Access. Automation and Notifications show a non-draggable
guide for the control macOS expects the user to change. Files & Folders stays
on `NSOpenPanel`, which grants access through the folder picker rather than
System Settings.

On macOS 26 and later, the guide uses `NSGlassEffectView`. Earlier macOS
versions retain the native popover material fallback.
