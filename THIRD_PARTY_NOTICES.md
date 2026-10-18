# Digital Wellbeing implementation notice

The Digital Wellbeing feature in Daily Tracker is a new Flutter UI and Android-native implementation inspired by the feature set and interaction concepts in [Dragon Launcher](https://github.com/Elnix90/Dragon-Launcher), including usage awareness, mindful pauses, app-session limits, reminders, and an optional overlay at the end of a session.

Dragon Launcher is distributed under the GNU General Public License v3.0. Its license and source remain available in the upstream repository. The Daily Tracker implementation uses its own Dart/Kotlin files and does not transplant Dragon Launcher source files verbatim.

This feature reads Android Usage Access data locally on the device. Android special access must be granted by the user before usage statistics can be read; overlay permission is optional.
