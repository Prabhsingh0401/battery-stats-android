# Battery notification for Android (no root, no app)

Tested on a Pixel 7 with Android 16; written to work on other Android 10+ phones.

`battery.sh` runs in the phone's shell from `/data/local/tmp/battery.sh`.
While AC/USB/Wireless powered is true it posts "Temp 28.0 C, Power 14.1 W" every 5 s
(tag `battmon`, so it replaces itself). When not charging it removes the notification and checks every 30 s.

## Start / restart (e.g. after a phone reboot)
Connect adb, then run from this folder:

    start-battery.cmd

## Stop

    adb shell "kill -9 $(cat /data/local/tmp/battery.pid); service call notification 8 s16 com.android.shell s16 com.android.shell s16 battmon i32 2020 i32 0"

(The second part removes the notification if it is showing. `cmd notification` has no cancel command,
so this calls NotificationManager's cancelNotificationWithTag directly.)

## Phone settings
No phone settings are changed. (settings_enable_monitor_phantom_procs was briefly set to false,
then restored to default with `settings delete` on 2026-11-23, because a script started from adb
shell most likely isn't watched by the phantom process monitor.)
If the script ever gets killed on its own, this is the setting to try:
    adb shell settings put global settings_enable_monitor_phantom_procs false

## Trying it on another phone
Push it and run the test mode first; it prints what it detected and the text it would post:

    adb push battery.sh /data/local/tmp/battery.sh
    adb shell sh /data/local/tmp/battery.sh --test

Check that the Power value is believable while charging (most phones: 5-30 W, fast chargers more).

What the script adapts to by itself:
- **Battery folder**: uses `/sys/class/power_supply/battery`, else the first supply whose `type` is
  `Battery` and that has `current_now` (e.g. `bms`). If none, the text shows `Power n/a`.
- **Current units** (uA vs mA): any reading of 20000 or more proves uA (20 A doesn't happen on a phone).
  Below that it guesses from the charge counter: uAh gives millions, mAh gives thousands.
- **Voltage units** (uV vs mV): by size. If `voltage_now` is missing, it uses dumpsys `voltage` (mV).
- **Cancel**: the binder call number (txn 8) can differ between Android versions. After cancelling,
  the script checks `cmd notification list`; if the notification is still there, it replaces it
  with "Not charging" instead of leaving stale numbers.

Not handled: phone makers that kill background processes aggressively (some Xiaomi, Huawei,
OnePlus models) may stop the script; there is no workaround without root or an app.

## Notes
- The script does not survive a phone reboot; run `start-battery.cmd` again.
- Phone shell math may be 32-bit, so the script works in mA x mV to avoid overflow.
