#!/usr/bin/env bash
# SteamOS Desktop User Switcher
# All generated files and messages are in English.
# Edit DESKTOP_USER below, then run from any existing administrator account:
#   sudo bash ./steamos-user-switch.sh install
# Other commands:
#   sudo bash ./steamos-user-switch.sh check
#   sudo bash ./steamos-user-switch.sh uninstall
# Accounts must already exist. This script never grants group membership.
# Switching ends the current graphical session. Save your work first.
# This targets SteamOS using SDDM and the session files configured below.

DESKTOP_USER="USER_NAME"
GAMING_USER="deck"
DESKTOP_SESSION="plasma.desktop"
GAMING_SESSION="gamescope-wayland.desktop"

set -Eeuo pipefail
export PATH=/usr/bin:/usr/sbin:/bin:/sbin
export LC_ALL=C
BASE=/etc/steamos-desktop-user
OVERRIDE=/etc/sddm.conf.d/zzzz-steamos-desktop-user.conf
SERVICE=steamos-desktop-user-reset.service
UNIT=/etc/systemd/system/$SERVICE

die() { printf 'Error: %s\n' "$*" >&2; exit 1; }
[[ $EUID == 0 ]] || die 'Run this script with sudo.'
[[ $# -le 1 ]] || die 'Usage: sudo bash steamos-user-switch.sh [install|check|uninstall]'
ACTION=${1:-install}
case "$ACTION" in install|check|uninstall) ;; *) die 'Unknown action.' ;; esac
for tool in python3 visudo systemctl systemd-run runuser flock getent install stat; do
    command -v "$tool" >/dev/null || die "Required command not found: $tool"
done
exec 9>/run/steamos-desktop-user-install.lock
flock -n 9 || die 'Another installation or removal is in progress.'

# A literal final @include ensures that a later wheel rule cannot override
# this installer's NOPASSWD rule. Existing, unrelated sudoers lines are kept.
write_sudoers_candidate() {
    local action=$1 destination=$2
    python3 - /etc/sudoers "$destination" "$action" <<'PY'
import pathlib, sys
source, destination, action = sys.argv[1:]
text = pathlib.Path(source).read_text()
begin = '# BEGIN STEAMOS DESKTOP USER SWITCHER'
end = '# END STEAMOS DESKTOP USER SWITCHER'
lines = text.splitlines(keepends=True)
result = []
inside = False
blocks = 0
for line in lines:
    if line.rstrip('\r\n') == begin:
        if inside or blocks:
            raise SystemExit('Error: duplicate or malformed managed sudoers block.')
        inside = True
        blocks += 1
    elif line.rstrip('\r\n') == end:
        if not inside:
            raise SystemExit('Error: unmatched sudoers end marker.')
        inside = False
    elif not inside:
        result.append(line)
if inside:
    raise SystemExit('Error: incomplete managed sudoers block.')
out = ''.join(result)
if action == 'install':
    if out and not out.endswith('\n'):
        out += '\n'
    out += begin + '\n@include /etc/steamos-desktop-user/return.sudoers\n' + end + '\n'
elif action != 'uninstall':
    raise SystemExit('Error: invalid sudoers operation.')
pathlib.Path(destination).write_text(out)
PY
    visudo -cf "$destination"
}

load_installed_settings() {
    [[ -f $BASE/managed-v1 && -f $BASE/settings ]] || die 'No managed installation was found.'
    [[ $(stat -c '%u' "$BASE") == 0 ]] || die 'The installation directory is not owned by root.'
    # Only root can write this directory and its generated settings.
    source "$BASE/settings"
}

user_launcher() {
    local user=$1 name=$2 operation=$3
    # Resolve XDG directories in the user's own environment. All writes into
    # home directories happen with that user's privileges, never as root.
    runuser -u "$user" -- env -u XDG_CONFIG_HOME -u XDG_DATA_HOME \
        -u XDG_CACHE_HOME -u XDG_RUNTIME_DIR -u DBUS_SESSION_BUS_ADDRESS \
        /bin/bash -c '
      set -eu
      name=$1
      operation=$2
      desktop=$(/usr/bin/xdg-user-dir DESKTOP)
      case "$desktop" in /*) ;; *) echo "Error: invalid desktop directory." >&2; exit 1 ;; esac
      if [[ $operation == remove ]]; then
          rm -f -- "$desktop/$name" "$HOME/.local/share/applications/$name"
      else
          mkdir -p -- "$desktop" "$HOME/.local/share/applications"
          tee "$desktop/$name" "$HOME/.local/share/applications/$name" >/dev/null
          chmod u+x -- "$desktop/$name" "$HOME/.local/share/applications/$name"
      fi
    ' launcher "$name" "$operation"
}

if [[ $ACTION == check ]]; then
    load_installed_settings
    visudo -c
    systemctl is-enabled --quiet "$SERVICE" || die 'The boot reset service is not enabled.'
    runuser -u "$DESKTOP_USER" -- /usr/bin/sudo -n "$BASE/switch" check
    printf 'Gaming user: %s\nDesktop user: %s\n' "$GAMING_USER" "$DESKTOP_USER"
    printf '%s\n' 'Configuration checks passed. No session was switched.'
    exit 0
fi

if [[ $ACTION == uninstall ]]; then
    load_installed_settings
    tmp=$(mktemp /etc/.steamos-user-sudoers.XXXXXX)
    trap 'rm -f -- "$tmp"' EXIT
    write_sudoers_candidate uninstall "$tmp"
    install -o root -g root -m 440 "$tmp" /etc/sudoers
    systemctl disable "$SERVICE"
    rm -f -- "$OVERRIDE" "$UNIT"
    systemctl daemon-reload
    for user in "$GAMING_USER" "$DESKTOP_USER"; do
        user_launcher "$user" SteamOS-Desktop-User.desktop remove </dev/null
        user_launcher "$user" SteamOS-Gaming-Mode.desktop remove </dev/null
    done
    # Restore only modes that remain 700; preserve subsequent manual changes.
    for user in "$GAMING_USER" "$DESKTOP_USER"; do
        home=$(getent passwd "$user" | cut -d: -f6)
        old_mode=$(cat "$BASE/backups/$user.home-mode")
        [[ $old_mode =~ ^[0-7]{3,4}$ ]] || die 'Invalid saved home mode.'
        if [[ $(stat -c '%a' "$home") == 700 ]]; then chmod "$old_mode" "$home"; fi
    done
    # Keep root-only backups of earlier configuration for manual reference.
    rm -f -- "$BASE/switch" "$BASE/settings" "$BASE/return.sudoers" "$BASE/managed-v1"
    printf '%s\n' 'Uninstalled. Backups remain in /etc/steamos-desktop-user/backups.'
    printf '%s\n' 'Restart the device to return to the original Gaming Mode startup.'
    exit 0
fi

[[ $DESKTOP_USER != USER_NAME ]] || die 'Set DESKTOP_USER near the top of this file to an existing Linux username.'
for user in "$DESKTOP_USER" "$GAMING_USER"; do
    [[ $user =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] || die "Unsupported username: $user"
    entry=$(getent passwd "$user") || die "Account does not exist: $user"
    uid=$(cut -d: -f3 <<< "$entry")
    home=$(cut -d: -f6 <<< "$entry")
    shell=$(cut -d: -f7 <<< "$entry")
    [[ $uid != 0 && $home == /home/* && -d $home && ! -L $home ]] || die "Unsupported home or UID for $user"
    [[ $(stat -c '%u' "$home") == "$uid" ]] || die "Home directory ownership is incorrect for $user"
    [[ $shell != */nologin && $shell != */false ]] || die "Account cannot log in: $user"
done
[[ $DESKTOP_USER != "$GAMING_USER" ]] || die 'The desktop and gaming users must be different.'
for session in "$DESKTOP_SESSION" "$GAMING_SESSION"; do
    [[ $session =~ ^[a-zA-Z0-9._-]+\.desktop$ ]] || die 'Invalid session name.'
    [[ -f /usr/share/wayland-sessions/$session ]] || die "Wayland session is not installed: $session"
done
for tool in konsole xdg-user-dir; do command -v "$tool" >/dev/null || die "Required command not found: $tool"; done
systemctl is-active --quiet sddm.service || die 'This installer requires an active SDDM service.'
visudo -c

if [[ -e $BASE || -L $BASE ]]; then
    [[ -d $BASE && ! -L $BASE && $(stat -c '%u' "$BASE") == 0 ]] || die 'Unsafe installation directory.'
    if [[ -f $BASE/managed-v1 ]]; then
        # Do not silently move launchers or permissions to another account.
        requested_desktop=$DESKTOP_USER
        requested_gaming=$GAMING_USER
        requested_desktop_session=$DESKTOP_SESSION
        requested_gaming_session=$GAMING_SESSION
        source "$BASE/settings"
        [[ $DESKTOP_USER == "$requested_desktop" && $GAMING_USER == "$requested_gaming" ]] || die 'Uninstall the existing configuration before changing users.'
        DESKTOP_SESSION=$requested_desktop_session
        GAMING_SESSION=$requested_gaming_session
    else
        # An uninstall intentionally retains only the backup directory.
        for child in "$BASE"/* "$BASE"/.[!.]* "$BASE"/..?*; do
            [[ -e $child || -L $child ]] || continue
            [[ $child == "$BASE/backups" && -d $child && ! -L $child ]] || die 'Unrecognized files exist in the installation directory.'
        done
    fi
fi

# Verify both the fallback gaming configuration and the proposed desktop
# configuration using SDDM's documented configuration precedence.
python3 - "$GAMING_USER" "$GAMING_SESSION" "$DESKTOP_USER" "$DESKTOP_SESSION" "$OVERRIDE" <<'PY'
import configparser, pathlib, sys
gaming_user, gaming_session, desktop_user, desktop_session, own = sys.argv[1:]
skip = {own}
files = []
for directory in ('/usr/lib/sddm/sddm.conf.d', '/etc/sddm.conf.d'):
    files += sorted(pathlib.Path(directory).glob('*.conf'))
files += [pathlib.Path('/etc/sddm.conf')]
def read(path, state):
    parser = configparser.ConfigParser(strict=False, interpolation=None)
    parser.optionxform = str
    parser.read(path)
    if parser.has_section('Autologin'):
        state.update(parser.items('Autologin'))
state = {}
for path in files:
    if str(path) not in skip: read(path, state)
if state.get('User') != gaming_user or state.get('Session') != gaming_session:
    raise SystemExit(f'Error: original SDDM startup is not {gaming_user}/{gaming_session}. Stop and inspect the local SDDM configuration.')
state = {}
local_files = sorted(set(pathlib.Path('/etc/sddm.conf.d').glob('*.conf')) | {pathlib.Path(own)})
proposed = sorted(pathlib.Path('/usr/lib/sddm/sddm.conf.d').glob('*.conf')) + local_files + [pathlib.Path('/etc/sddm.conf')]
for path in proposed:
    if str(path) == own:
        state.update(User=desktop_user, Session=desktop_session, Relogin='true')
    elif str(path) not in skip: read(path, state)
if state.get('User') != desktop_user or state.get('Session') != desktop_session:
    raise SystemExit('Error: another SDDM file would override the desktop switch.')
print('SDDM configuration precedence checks passed.')
PY

stage=$(mktemp -d /run/steamos-user-switch.XXXXXX)
chmod 700 "$stage"
cp -p /etc/sudoers "$stage/sudoers.before"
had_install=0
if [[ -f $BASE/managed-v1 ]]; then
    had_install=1
    cp -a "$BASE" "$stage/previous-install"
    cp -p "$UNIT" "$stage/unit.before"
fi
rollback() {
    trap - ERR
    install -o root -g root -m 440 "$stage/sudoers.before" /etc/sudoers
    if [[ $had_install == 1 ]]; then
        cp -a "$stage/previous-install/." "$BASE/"
        install -o root -g root -m 644 "$stage/unit.before" "$UNIT"
    else
        systemctl disable "$SERVICE" >/dev/null 2>&1 || true
        rm -f -- "$UNIT"
        rm -f -- "$BASE/switch" "$BASE/settings" "$BASE/return.sudoers" "$BASE/managed-v1"
    fi
    systemctl daemon-reload || true
    printf '%s\n' 'Installation failed. The previous main sudoers file was restored. No session switch was requested.' >&2
    printf 'Diagnostic files: %s\n' "$stage" >&2
    exit 1
}
trap rollback ERR
umask 022
mkdir -p "$BASE/backups"
chown root:root "$BASE" "$BASE/backups"
chmod 755 "$BASE"
chmod 700 "$BASE/backups"
[[ -f $BASE/backups/sudoers.original ]] || cp -p /etc/sudoers "$BASE/backups/sudoers.original"
for user in "$GAMING_USER" "$DESKTOP_USER"; do
    home=$(getent passwd "$user" | cut -d: -f6)
    if [[ $had_install == 0 || ! -f $BASE/backups/$user.home-mode ]]; then
        stat -c '%a' "$home" > "$BASE/backups/$user.home-mode"
    fi
done
printf 'DESKTOP_USER=%q\nGAMING_USER=%q\nDESKTOP_SESSION=%q\nGAMING_SESSION=%q\n' \
    "$DESKTOP_USER" "$GAMING_USER" "$DESKTOP_SESSION" "$GAMING_SESSION" > "$BASE/settings"
chmod 644 "$BASE/settings"

cat > "$BASE/switch" <<'SWITCH'
#!/usr/bin/env bash
set -Eeuo pipefail
export PATH=/usr/bin:/usr/sbin:/bin:/sbin
export LC_ALL=C
[[ $EUID == 0 && $# == 1 ]] || { echo 'Error: this command requires root and one action.' >&2; exit 1; }
source /etc/steamos-desktop-user/settings
conf=/etc/sddm.conf.d/zzzz-steamos-desktop-user.conf
case "$1" in
  check) echo 'Passwordless return authorization is working.'; exit 0 ;;
  boot) rm -f -- "$conf"; exit 0 ;;
  desktop|gaming) ;;
  *) echo 'Error: unknown action.' >&2; exit 1 ;;
esac
exec 9>/run/steamos-desktop-user-switch.lock
flock -n 9 || { echo 'Error: another session switch is in progress.' >&2; exit 1; }
if [[ $1 == desktop ]]; then
    id "$DESKTOP_USER" >/dev/null
    tmp=$(mktemp /etc/sddm.conf.d/.steamos-desktop-user.XXXXXX)
    trap 'rm -f -- "$tmp"' EXIT
    printf '[Autologin]\nUser=%s\nSession=%s\nRelogin=true\n' "$DESKTOP_USER" "$DESKTOP_SESSION" > "$tmp"
    chmod 644 "$tmp"
    mv -f -- "$tmp" "$conf"
    trap - EXIT
else
    rm -f -- "$conf"
fi
if ! systemd-run --collect --unit="steamos-user-switch-$(date +%s)-$$" \
    /usr/bin/systemctl restart sddm.service; then
    rm -f -- "$conf"
    echo 'Error: restart could not be scheduled; the desktop override was removed.' >&2
    exit 1
fi
SWITCH
chmod 755 "$BASE/switch"
bash -n "$BASE/switch"
printf '%s ALL=(root) NOPASSWD: /etc/steamos-desktop-user/switch gaming, /etc/steamos-desktop-user/switch check\n' \
    "$DESKTOP_USER" > "$BASE/return.sudoers"
chmod 440 "$BASE/return.sudoers"
visudo -cf "$BASE/return.sudoers"
write_sudoers_candidate install "$stage/sudoers.new"
install -o root -g root -m 440 "$stage/sudoers.new" /etc/sudoers
visudo -c
runuser -u "$DESKTOP_USER" -- /usr/bin/sudo -n "$BASE/switch" check

cat > "$UNIT" <<'UNIT'
[Unit]
Description=Restore the SteamOS gaming user before graphical startup
Before=sddm.service

[Service]
Type=oneshot
ExecStart=/etc/steamos-desktop-user/switch boot

[Install]
WantedBy=multi-user.target
UNIT
chmod 644 "$UNIT"
systemctl daemon-reload
systemctl enable "$SERVICE"
systemctl is-enabled --quiet "$SERVICE"

cat > "$stage/desktop.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=Switch to Desktop User
Comment=Save your work first. This ends the current graphical session.
Exec=/usr/bin/konsole --hold -e /usr/bin/sudo /etc/steamos-desktop-user/switch desktop
Icon=system-switch-user
Terminal=false
Categories=System;
DESKTOP
cat > "$stage/gaming.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=Return to Gaming Mode
Comment=Save your work first. This ends the current graphical session.
Exec=/usr/bin/konsole --hold -e /usr/bin/sudo -n /etc/steamos-desktop-user/switch gaming
Icon=steam
Terminal=false
Categories=System;
DESKTOP
user_launcher "$GAMING_USER" SteamOS-Desktop-User.desktop install < "$stage/desktop.desktop"
user_launcher "$DESKTOP_USER" SteamOS-Gaming-Mode.desktop install < "$stage/gaming.desktop"

# Enable home-directory separation without changing file ownership or groups.
for user in "$GAMING_USER" "$DESKTOP_USER"; do
    home=$(getent passwd "$user" | cut -d: -f6)
    chmod 700 "$home"
done

printf '1\n' > "$BASE/managed-v1"
trap - ERR
rm -rf -- "$stage"
printf '\nInstalled successfully. No session was switched.\n'
printf 'Gaming user: %s\nDesktop user: %s\n' "$GAMING_USER" "$DESKTOP_USER"
printf '%s\n' 'Use Switch to Desktop User on the gaming desktop.'
printf '%s\n' 'Use Return to Gaming Mode on the desktop user account.'
printf '%s\n' 'If prompted by KDE, allow execution of the new desktop shortcut.'
printf '%s\n' 'Normal Log Out does not replace Return to Gaming Mode.'
printf '%s\n' 'The desktop user is automatically logged in; no password prompt is added.'
printf '%s\n' 'Existing administrator memberships and permissions are unchanged.'
printf '%s\n' 'On boot, the temporary desktop override is removed before SDDM starts.'
