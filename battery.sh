#!/system/bin/sh
# Battery temp + charging power notification. Runs in the phone's own shell (no root, no app).
# Usage:  battery.sh          run the loop (start it with setsid nohup ... &)
#         battery.sh --test   print what was detected and the text it would post, then exit
#
# Phone shell math may be 32-bit, so values are scaled to mA / mV before multiplying.

TAG=battmon
PIDFILE=/data/local/tmp/battery.pid
PS=/sys/class/power_supply

# --- 1. find the battery folder -------------------------------------------
# Prefer the standard "battery"; otherwise the first supply of type Battery that has current_now.
find_bat() {
  if [ -r "$PS/battery/current_now" ]; then echo "$PS/battery"; return; fi
  for d in "$PS"/*; do
    [ -r "$d/type" ] && [ -r "$d/current_now" ] || continue
    [ "$(cat "$d/type" 2>/dev/null)" = "Battery" ] && { echo "$d"; return; }
  done
  echo ""   # none found: power will show n/a
}
BAT=$(find_bat)

# --- 2. unit detection ----------------------------------------------------
# Current: the kernel standard is uA, but some phones report mA.
#   - any |reading| >= 20000 proves uA (20 A doesn't happen on a phone), and that sticks;
#   - until then, guess from the charge counter: uAh gives millions, mAh gives thousands.
CUR_UNIT=""
cc=$(cat "$BAT/charge_counter" 2>/dev/null)
[ -z "$cc" ] && cc=$(dumpsys battery | sed -n 's/^ *Charge counter: *//p')
if [ -n "$cc" ] && [ "$cc" -ge 100000 ] 2>/dev/null; then CUR_GUESS=uA; else CUR_GUESS=mA; fi

# These set variables instead of echoing: $(...) runs in a subshell, which would
# forget CUR_UNIT after every reading.
to_ma() {   # $1 = absolute raw current -> sets MA
  if [ "$1" -ge 20000 ]; then CUR_UNIT=uA; fi
  u=${CUR_UNIT:-$CUR_GUESS}
  if [ "$u" = uA ]; then MA=$(( $1 / 1000 )); else MA=$1; fi
}

to_mv() {   # $1 = raw voltage -> sets MV; uV if large, else mV
  if [ "$1" -ge 100000 ]; then MV=$(( $1 / 1000 )); else MV=$1; fi
}

# --- reading + text -------------------------------------------------------
make_text() {   # $1 = dumpsys battery output -> sets TEXT
  t=$(echo "$1" | sed -n 's/^ *temperature: *//p')   # tenths of a degree C
  sign=""
  if [ "$t" -lt 0 ]; then sign="-"; t=$(( -t )); fi
  temp="${sign}$(( t / 10 )).$(( t % 10 ))"

  i=$(cat "$BAT/current_now" 2>/dev/null)
  v=$(cat "$BAT/voltage_now" 2>/dev/null)
  [ -z "$v" ] && v=$(echo "$1" | sed -n 's/^ *voltage: *//p')   # dumpsys voltage is mV
  if [ -n "$BAT" ] && [ -n "$i" ] && [ -n "$v" ]; then
    i=${i#-}
    to_ma "$i"
    to_mv "$v"
    dw=$(( (MA * MV + 50000) / 100000 ))   # mA*mV = uW; /100000 = tenths of a watt
    power="$(( dw / 10 )).$(( dw % 10 )) W"
  else
    power="n/a"
  fi
  TEXT="Temp $temp C, Power $power"
}

# --- 3. cancel, with check and fallback ----------------------------------
is_showing() { cmd notification list 2>/dev/null | grep -q "|com.android.shell|2020|$TAG|"; }

cancel_notif() {
  # cmd notification has no cancel; INotificationManager.cancelNotificationWithTag is txn 8
  # on Android 16 (args: pkg, opPkg, tag, id 2020 used by cmd notification post, userId).
  # The number can differ on other Android versions, so check it really went away.
  service call notification 8 s16 com.android.shell s16 com.android.shell s16 "$TAG" i32 2020 i32 0 >/dev/null 2>&1
  sleep 1
  if is_showing; then
    cmd notification post -t "Battery" "$TAG" "Not charging" >/dev/null 2>&1
  fi
}

charging() { echo "$1" | grep -qE '(AC|USB|Wireless) powered: true'; }

# --- test mode ------------------------------------------------------------
if [ "$1" = "--test" ]; then
  d=$(dumpsys battery)
  echo "battery folder : ${BAT:-none found}"
  echo "current_now    : $(cat "$BAT/current_now" 2>/dev/null)"
  echo "voltage_now    : $(cat "$BAT/voltage_now" 2>/dev/null)"
  echo "charge counter : $cc  -> current unit guess: $CUR_GUESS"
  make_text "$d"
  echo "detected unit  : ${CUR_UNIT:-$CUR_GUESS} (after reading)"
  if charging "$d"; then echo "charging       : yes"; else echo "charging       : no"; fi
  echo "text           : $TEXT"
  exit 0
fi

# --- main loop ------------------------------------------------------------
echo $$ > "$PIDFILE"
posted=1   # cancel any leftover notification on first idle pass

while true; do
  d=$(dumpsys battery)
  if charging "$d"; then
    make_text "$d"
    cmd notification post -t "Battery" "$TAG" "$TEXT" >/dev/null 2>&1
    posted=1
    sleep 5
  else
    if [ "$posted" = 1 ]; then cancel_notif; posted=0; fi
    sleep 30
  fi
done
