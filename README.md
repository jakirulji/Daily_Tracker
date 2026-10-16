================================================================================
DAILY TRACKER  (repo: Study-Tracker, Flutter package name: study_planner)
================================================================================
A local-first Flutter app (Android target) with multiple "profiles". Each profile
is either a TRACKER (tasks + focus timer + stats) or a PRAYER checklist.
No backend, no login. All data is one JSON string in SharedPreferences.

This README is written so that a developer OR an AI assistant can understand and
modify the whole project from this file alone. Read sections 1-6 first.

--------------------------------------------------------------------------------
1. QUICK FACTS
--------------------------------------------------------------------------------
- Language / framework : Dart (SDK >=3.3), Flutter, Material 3
- State management     : one global ChangeNotifier singleton `st` (class Store)
- Storage              : shared_preferences, key "data" (JSON)
- Packages             : shared_preferences, flutter_local_notifications ^17,
                         timezone, share_plus ^10, path_provider, file_picker ^8
- Platform             : Android only. The android/ folder is NOT committed; it is
                         generated in CI (see section 8)
- Size                 : ~1000 lines in 9 files under lib/

--------------------------------------------------------------------------------
2. FILE MAP  (lib/)
--------------------------------------------------------------------------------
main.dart          Entry point. App (theme), Home (Scaffold, bottom nav, FAB),
                   asks notification permission on first frame.
store.dart         EVERYTHING about data: constants (palette, faiths, defaults),
                   task helper functions, class Store, global `st`.
                   READ THIS FIRST.
notify.dart        class Notif: local notifications (timer end, task reminders,
                   prayer reminders). Re-schedules from Store data.
ui.dart            Shared dialogs/widgets: snack, ask, confirm, pickTime,
                   taskDialog (add+edit), addProfile dialog, AppDrawer, Confetti.
today_page.dart    Tracker tab 1: header card, 7-day strip, task list, notes.
timer_page.dart    Tracker tab 2: Pomodoro-style timer.
stats_page.dart    Tracker tab 3: 7-day stacked bars, weekly summary, heatmap.
settings_page.dart Settings (both profile types): theme, goal, exam, backup,
                   test notification, timer modes, categories.
prayer_page.dart   Prayer profile main page: faith picker, daily checklist,
                   reminders, 7-day grid.
pubspec.yaml       Dependencies.
.github/workflows  CI that builds the signed APK (section 8).

--------------------------------------------------------------------------------
3. ARCHITECTURE
--------------------------------------------------------------------------------
- `final st = Store();` in store.dart is the single source of truth. Every page
  is wrapped in ListenableBuilder(listenable: st, ...) and rebuilds on change.
- To change data: mutate the Store fields / maps, then call st.save().
    st.save()          -> writes JSON to SharedPreferences, notifyListeners(),
                          and (debounced 600 ms) re-schedules notifications.
    st.save(q: true)   -> "quiet": writes only, no rebuild, no re-schedule
                          (used while typing the daily note, and for the
                          confetti flag).
- Only the CURRENT profile is loaded into Store fields (subjects, tasks, logs,
  ...). Other profiles stay as raw maps in profiles[i]['d'].
    * Store.pdata  = snapshot map of the live fields of the current profile
    * Store.json   = writes pdata into profiles[cur]['d'] then jsonEncode
    * Store.loadP(map) = fills live fields from a profile map
    * Store.dataOf(i)  = data map of any profile (live one via pdata)
    * switchTo/addProfile/removeProfile first save pdata, then loadP the target.
- Home picks pages by profile type:
    tracker -> Today, Timer, Stats, Settings
    prayer  -> Prayer, Settings
  IndexedStack uses ValueKey(st.cur) so pages are rebuilt when profile changes.

--------------------------------------------------------------------------------
4. DATA MODEL  (what is inside the JSON)
--------------------------------------------------------------------------------
Dates are strings "yyyy-MM-dd" produced by dk(DateTime).
Colors are ints (0xFFRRGGBB). Short keys are used on purpose; do not rename them
without writing a migration (old backups must keep loading).

Root (Store.json):
  { "profiles":[ {n, t, d}, ... ], "cur":int, "dark":bool, "amoled":bool,
    "seed":int }
  n = profile name, t = "tracker" | "prayer", d = profile data (below)

Profile data `d` (see Store.pdata / Store.loadP):
  subjects : [ {n:name, c:color} ]              task/timer categories
  tasks    : [ task, ... ]                      see below
  logs     : { date : { subjectName : minutes } }   focus time
  notes    : { date : "reflection text" }
  goal     : double 1..12                       daily goal in hours
  exam, examDate : string                       exam countdown ("" = unset)
  cel      : date string                        last day confetti was shown
  modes    : [ {n, f:focusMin, b:breakMin} ]    timer presets
  mi       : int                                selected mode index
  faith    : string                             prayer profile faith ("" = unset)
  prayers  : [ {n:name, rt:"HH:mm"|null} ]      rt = reminder time
  pdone    : { date : [prayerName, ...] }       ticked prayers
  oldCol   : { deletedSubjectName : color }     keeps colors of deleted categories

Task map:
  t  title            s  subject name         d  start date
  tm free-text time   rt reminder "HH:mm"|null
  rp repeat: "none" | "daily" | "weekly"  (missing = "none")
  x  done flag (non-repeating tasks)
  xd list of done dates (repeating tasks)
Helper functions in store.dart (use them, do not re-implement):
  recurring(task), occurs(task, date), isDone(task, date), setDone(task, date, v)
  Store.tasksOn(date), Store.active(date), Store.streak

Streak rule: a day counts if focus minutes > 0 OR at least one task occurring
that day is done. Streak = consecutive counted days ending today (or yesterday
if today is not counted yet).

Dart typing gotcha: maps are loose `Map` (Map<dynamic,dynamic>). When you create
a map literal that may later hold null, write <dynamic, dynamic>{...} or Dart may
infer Map<String,Object> and crash on null assignment.

--------------------------------------------------------------------------------
5. FEATURES
--------------------------------------------------------------------------------
Today      Greeting header (streak, badges at 3/7/30 days, exam countdown, goal
           ring), 7-day date strip, tasks for the selected date.
           Swipe right = toggle done. Swipe left = delete (repeating tasks ask
           for confirmation, deletes all repeats). Tap = edit. Carry-over list
           shows unfinished one-off tasks from past days. Daily note. Confetti
           when the daily goal is reached.
Task       Title, category, free-text time, optional reminder time, repeat
           (once/daily/weekly).
Timer      Preset/custom focus+break modes, category picker, 4-dot session
           counter, Start/Pause, "Reset & log" (logs elapsed minutes if >= 1).
Stats      Last 7 days stacked bar by category, weekly total/best day/vs last
           week, per-category bars, 12-week heatmap.
Prayer     Faith presets (Islam, Hinduism, Buddhism, Christianity, Sikhism,
           Other), custom prayers, per-prayer reminder time, daily ticks,
           full-day streak, editable 7-day grid.
Settings   Dark / AMOLED, 8 theme colors, daily goal, exam countdown, test
           notification, backup (file export/import + copy/paste text),
           timer modes, categories (deleting keeps color via oldCol).
Profiles   Drawer: add / rename / delete / switch. Types: tracker, prayer.

--------------------------------------------------------------------------------
6. TIMER AND NOTIFICATION DESIGN
--------------------------------------------------------------------------------
Timer (timer_page.dart)
- Works from an END TIMESTAMP (endAt), not a decrementing counter. Every second
  and on app resume it recomputes `left` from endAt, so it stays accurate when
  the app is in the background or the screen is off.
- On Start it schedules a notification for endAt (Notif.setTimer). Pause / reset
  / finish / dispose cancels it (Notif.clearTimer).
- When a focus session finishes, st.addLog(subject, minutes) is called.
- Timer state lives in the page State: switching profile resets it, and killing
  the app loses progress (the scheduled notification still fires).

Notifications (notify.dart)
- Notif.rescheduleAll(Store) = cancelAll, then re-add: running timer, and for the
  NEXT 7 DAYS every task reminder (occurring, not done) and every prayer reminder
  (not ticked) across ALL profiles. Called at app start and (debounced) on every
  non-quiet save.
- Notification ids: 1 = timer, 2 = test, 100..450 = reminders.
- Scheduled as absolute instants via tz.TZDateTime.from(dt, tz.UTC), so no
  timezone database / flutter_timezone is needed.
- Tries AndroidScheduleMode.exactAllowWhileIdle, falls back to
  inexactAllowWhileIdle if exact alarms are not permitted.
- Limitation: if the app is not opened for 7 days, reminders stop.
- Android 13+ asks for notification permission on first launch.

--------------------------------------------------------------------------------
7. HOW TO EXTEND  (recipes)
--------------------------------------------------------------------------------
Add a new per-profile field (e.g. "water")
  1. store.dart: add the field in Store.
  2. add it to Store.pdata.
  3. read it in Store.loadP with a safe default (m['water'] ?? 0).
  4. mutate it, then st.save().
  Old backups keep working because loadP supplies defaults.

Add a tab to tracker profiles
  main.dart: add the page to the tracker `pages` list AND a matching
  NavigationDestination (same order, same count).

Add a new profile type (e.g. "habit")
  - ui.dart addProfile dialog: add a ButtonSegment.
  - store.dart: `tracker` getter currently means (t != 'prayer'); adjust if the
    new type needs its own pages.
  - main.dart: choose pages for the new type.
  - drawer icon in ui.dart AppDrawer.

Add a new reminder type
  notify.dart rescheduleAll: loop over the data and call _at(id++, title, body,
  DateTime). Keep id <= 450.

Add a setting
  settings_page.dart: add a tile, change a Store field, call st.save().

Anything native Android (permissions, gradle, icon, manifest)
  Must be done in the CI workflow, because android/ is generated (section 8).

--------------------------------------------------------------------------------
8. BUILD AND RELEASE
--------------------------------------------------------------------------------
GitHub Actions (.github/workflows/*.yml, trigger: workflow_dispatch)
  Actions tab -> "Build APK" -> Run workflow -> download artifact "app"
  (it is a zip containing app-release.apk).
Steps the workflow performs:
  1. checkout, Java 17 (temurin), Flutter stable
  2. flutter create . --project-name study_planner --platforms=android
     (generates android/; existing lib/ and pubspec.yaml are kept)
  3. flutter pub get
  4. sed: set android:label to "Daily Tracker"
  5. Patch for notifications: add POST_NOTIFICATIONS, SCHEDULE_EXACT_ALARM,
     RECEIVE_BOOT_COMPLETED, VIBRATE permissions + the two
     flutter_local_notifications receivers to AndroidManifest.xml; enable core
     library desugaring (isCoreLibraryDesugaringEnabled + coreLibraryDesugaring
     desugar_jdk_libs 2.1.4) in android/app/build.gradle.kts
  6. Signing: decode KEYSTORE_BASE64 to android/app/upload-keystore.jks and patch
     build.gradle.kts with a "release" signingConfig
  7. flutter build apk --release
  8. upload build/app/outputs/flutter-apk/app-release.apk
Required repository secrets:
  KEYSTORE_BASE64, KEYSTORE_PASSWORD, KEY_ALIAS, KEY_PASSWORD
Keep the SAME keystore forever, otherwise the new APK cannot update the old
install (signature mismatch).

Local build (optional)
  flutter create . --project-name study_planner --platforms=android
  (apply the same manifest/gradle patches as step 5)
  flutter pub get && flutter build apk --release

--------------------------------------------------------------------------------
9. PITFALLS / DECISIONS TO KNOW
--------------------------------------------------------------------------------
- Package APIs are version-sensitive. flutter_local_notifications is pinned to
  ^17 (zonedSchedule needs androidScheduleMode and
  uiLocalNotificationDateInterpretation). share_plus ^10 uses
  Share.shareXFiles; file_picker ^8 uses FilePicker.platform.pickFiles. If you
  upgrade majors, these call sites in notify.dart and settings_page.dart change.
- Colors use .withOpacity(); newer Flutter marks it deprecated (warning only).
- Backups: st.json is the whole app state. Restore = Store.apply(jsonString); it
  rolls back to the previous state if parsing fails.
- Deleting a category does not delete its tasks/logs; its color is remembered in
  oldCol.
- Status note: the v1.1.0 change set (background timer, notifications, task edit
  + repeat, file backup, multi-file split) was written without a local compile.
  If CI fails, read the first compiler error in the "flutter build apk" log.
  Delete this note once a build has succeeded.

--------------------------------------------------------------------------------
10. KNOWN LIMITATIONS / IDEAS
--------------------------------------------------------------------------------
- Timer progress is lost on profile switch or app kill.
- Reminders only cover the next 7 days (refreshed on app open).
- No cloud sync, only manual backup.
- No Bangla/other localization; UI strings are hard-coded English.
- No month view in stats; no habit/expense profile types yet.
- The whole app is one global store; fine at this size, split if it grows.

--------------------------------------------------------------------------------
11. FOR AI ASSISTANTS: HOW TO GET THE FULL CODE
--------------------------------------------------------------------------------
Some AI tools cannot open GitHub folder pages (robots rules) and can only read
single files, so the lib/ folder may look empty to them. Fix: make ONE file with
all source and give that file (or paste it) to the AI:

  for f in pubspec.yaml .github/workflows/*.yml lib/*.dart; do
    echo "===== $f ====="; cat "$f"; done > ALL_SOURCE.txt

Reading order: this README -> lib/store.dart -> lib/main.dart -> the page you
need to change. When you change code, keep the data-model rules in section 4 and
always return complete files, not fragments.
================================================================================
