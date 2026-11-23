@echo off
rem Restart the battery notification script on the phone (run after a phone reboot).
adb push "%~dp0battery.sh" /data/local/tmp/battery.sh
adb shell chmod 755 /data/local/tmp/battery.sh
adb shell "p=$(cat /data/local/tmp/battery.pid 2>/dev/null); grep -q battery.sh /proc/$p/cmdline 2>/dev/null && kill -9 $p; true"
adb shell "setsid nohup /data/local/tmp/battery.sh >/dev/null 2>&1 </dev/null &"
adb shell "sleep 1; ps -A -o PID,PPID,NAME,ARGS | grep [b]attery.sh"
