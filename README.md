# Original idea by:
<https://steamcommunity.com/id/bbkr>
<https://steamcommunity.com/id/Ethorbit>
on this threed:
<https://steamcommunity.com/app/1675200/discussions/0/3319736698849624249/?utm_source=chatgpt.com>
Ethorbit version can be found here:
<https://gist.github.com/Ethorbit/725e878a04f632b7476399c5151c96e8>

# SteamOS Desktop User Switcher — Setup and Usage Guide

This guide accompanies **`steamos-user-switch.sh`**, the universal installer with a configurable desktop username.

The script keeps normal SteamOS Gaming Mode startup on `deck` user and adds a way to switch to a separate Linux desktop account, then return to Gaming Mode.

## Why this script is needed

**Steam accounts and Linux users are different.** A Steam account identifies your games, purchases, and Steam profile. A Linux user owns a home directory, application settings, and files. In the standard Steam Deck setup described here, Gaming Mode and the normal Desktop Mode both run as the Linux user `deck`. Switching Steam accounts does not create a separate Linux desktop user.

**Creating another Linux user is only the first step.** It gives that account its own home directory, but the configured SteamOS login flow still automatically selects `deck`. Ordinary desktop logout normally returns to Gaming Mode rather than displaying a user-selection screen. This script adds the missing workflow: keep normal startup on `deck` user, then explicitly switch to a separate account for desktop work.

**The switch helper changes the next login.** It writes a temporary SDDM configuration selecting the desktop user and the Plasma session, then restarts the display manager. Returning removes that override and restarts the display manager again, restoring the original gaming-user configuration. Each switch ends the current graphical session.

**The boot service restores normal startup.** Before SDDM starts at boot, it removes the temporary override. This prevents a restart during desktop work from leaving the device configured to start on the desktop account. The service runs at boot; it is not a background application continuously monitoring your desktop.

**The shortcuts trigger the helper.** **Switch to Desktop User** requests administrator authorization to enter the work desktop. **Return to Gaming Mode** uses a narrowly scoped, passwordless sudo rule to return to gaming. A separate root-owned helper performs the privileged operations, so the desktop account does not need unrestricted sudo access for the return action. Existing administrator privileges remain unchanged.

## 1. Understand what the script does

| Action | Result |
| --- | --- |
| Power on or restart the device | The boot service removes this script's desktop override; the original Gaming Mode configuration is used. |
| Select **Switch to Desktop User** on the gaming user's desktop | The current graphical session ends and Plasma starts as the configured desktop user. |
| Select **Return to Gaming Mode** on the desktop user's desktop | The current graphical session ends and Gaming Mode starts as the gaming user. |

**Save your documents before switching.** This is session replacement, not two graphical sessions running side by side. Open applications can be closed without saving.

The script uses automatic login. It does not add a password prompt when entering the desktop account. The return shortcut receives permission to run one fixed return action without a password, plus a harmless authorization check.

## 2. Requirements

Use this installer on a SteamOS installation with:

- SDDM as the active display manager.
- The `gamescope-wayland.desktop` and `plasma.desktop` Wayland sessions installed.
- An existing gaming account, normally `deck`.
- An existing separate desktop account.
- Both accounts owning ordinary, non-symlink home directories under `/home/`.
- A working administrator account that can use `sudo`, default is `deck`.

The script checks configuration precedence and stops if unrelated SDDM settings would prevent the expected switching behavior. It targets this SteamOS/SDDM setup; it is not an installer for every Linux distribution or display manager.

The switching behavior was confirmed on SteamDeckOled SO v3.9.5. Compatibility with other SteamOS versions or future updates still needs checking.

## 3. Prepare the accounts

### Step 1 — Enter Desktop Mode

Start the Steam Deck normally. Select:

**Steam → Power → Switch to Desktop**

Open **Console**.

### Step 2 — Confirm administrator access

Run:

```bash
whoami
```

Then check that your current administrator account can use `sudo`:

```bash
sudo -v
```

Enter the password of the account you are currently using. The terminal does not display characters while you type the password.

If you see `is not in the sudoers file`, stop and restore administrator access before continuing. Setting a new password alone does not grant administrator privileges.

### Step 3 — Check whether the desktop account exists

This guide uses `USER_NAME` as the example desktop username:

```bash
id USER_NAME
```

If the account exists, keep it and continue. Do not run the account-creation command again.

If you need to create a new account, replace `USER_NAME` with your chosen username and run these commands separately from an administrator account:

```bash
sudo useradd -m -U -s /bin/bash USER_NAME
```

```bash
sudo passwd USER_NAME
```

For a limited desktop account, do not add it to `wheel`. The installer does not grant or remove group membership. An account that already has full administrator access retains it.

**Do not remove `deck` from `wheel`.** Do not use `usermod -G` to replace its supplementary groups. If group changes are needed, understand the difference between replacement and `usermod -aG`, which appends groups.

## 4. Configure and install the script

### Step 4 — Save the installer locally

Download `steamos-user-switch.sh` to the Steam Deck. Keep the file for later checks or removal.

In Dolphin, open the folder containing the file. Open a terminal in that folder, using **Open Terminal Here** if available. You can also open Console and use `cd` to enter the download folder.

For example, if the file is in `~/Downloads`:

```bash
cd "$HOME/Downloads"
```

Confirm that the file is there:

```bash
ls -l ./steamos-user-switch.sh
```

Folder names may differ on a localized desktop. Use the folder where you actually saved the file.

### Step 5 — Set the desktop username

Open `steamos-user-switch.sh` in Kate or another plain-text editor. Near the top, find:

```bash
DESKTOP_USER="USER_NAME"
GAMING_USER="deck"
DESKTOP_SESSION="plasma.desktop"
GAMING_SESSION="gamescope-wayland.desktop"
```

Change only `DESKTOP_USER` to the existing account you want to use for desktop work. For example:

```bash
DESKTOP_USER="myuser"
```

Keep the quotation marks. On a standard Steam Deck setup, leave the other three values unchanged. Save the file.

The configurable username must begin with a lowercase letter or underscore and contain only lowercase letters, digits, underscores, or hyphens. The installer accepts at most 32 characters.

### Step 6 — Run the installer

Save open documents, then run:

```bash
sudo bash ./steamos-user-switch.sh install
```

Enter the password of your current administrator account if prompted.

You do **not** need `chmod +x` when using `sudo bash` as shown above.

The installer validates the accounts, SDDM configuration, sudo policy, and passwordless return authorization. It also enables the boot reset service, creates English desktop shortcuts, and changes both home-directory modes to `700` without recursively changing files or ownership.

A successful installation ends with:

```text
Installed successfully. No session was switched.
```

**Installation itself does not switch accounts.** If any command reports an error, retain the complete output and resolve it before using the shortcuts.

### Step 7 — Check the installed configuration

Run:

```bash
sudo bash ./steamos-user-switch.sh check
```

Look for:

```text
Passwordless return authorization is working.
```

and:

```text
Configuration checks passed. No session was switched.
```

## 5. Use the switcher

### Switch from Gaming Mode to the desktop account

1. Start the Deck normally in Gaming Mode.
2. Select **Steam → Power → Switch to Desktop**. This opens the gaming user's desktop.
3. Save and close documents or applications that should not be interrupted.
4. Open the new **Switch to Desktop User** shortcut.
5. If KDE asks whether to allow execution of the desktop file, allow it.
6. Enter the gaming user's password if `sudo` requests it.
7. Wait for the configured user's Plasma desktop to appear.

To confirm the active account, open Konsole and run:

```bash
whoami
```

The output should match `USER_NAME`.

### Return to Gaming Mode

1. Save your documents on the desktop account.
2. Open the new **Return to Gaming Mode** shortcut.
3. Allow execution if KDE asks.
4. Wait for Gaming Mode to start as `deck`, or your configured gaming user.

The configured desktop user should not be asked for a `sudo` password for this return action.

**Use the return shortcut rather than ordinary Log Out.** While the desktop override is active, ordinary Log Out may automatically log back into the desktop account.

### Restart or power on

At boot, the installed reset service removes the switcher's temporary desktop override before SDDM starts. With the original configuration validated by the installer, the device starts in Gaming Mode again.

This does not preserve an open desktop session or unsaved work across a restart.

## 6. Manual commands

These commands use the new universal installation path. They are independent of the chosen desktop username.

### Test passwordless return authorization without switching

Run from the configured desktop account:

```bash
sudo -n /etc/steamos-desktop-user/switch check
```

### Return to Gaming Mode immediately

Save your documents first, then run from the configured desktop account:

```bash
sudo -n /etc/steamos-desktop-user/switch gaming
```

### Open the configured desktop account

Run from the gaming user's desktop with administrator authorization:

```bash
sudo /etc/steamos-desktop-user/switch desktop
```

This ends the current graphical session.

## 7. Files and permission handling

| File or directory | Purpose |
| --- | --- |
| `/etc/steamos-desktop-user/settings` | Saved usernames and session names. |
| `/etc/steamos-desktop-user/switch` | Root-owned helper implementing the fixed switch actions. |
| `/etc/steamos-desktop-user/return.sudoers` | Narrow passwordless permission for the configured desktop account. |
| `/etc/sddm.conf.d/zzzz-steamos-desktop-user.conf` | Temporary desktop-user override while desktop work is selected. |
| `/etc/systemd/system/steamos-desktop-user-reset.service` | Boot service that removes that override. |
| `/etc/steamos-desktop-user/backups/` | Root-only configuration backups and saved home-directory modes. |

The installer adds this managed block at the end of `/etc/sudoers`:

```sudoers
# BEGIN STEAMOS DESKTOP USER SWITCHER
@include /etc/steamos-desktop-user/return.sudoers
# END STEAMOS DESKTOP USER SWITCHER
```

For `DESKTOP_USER="USER_NAME"`, the included rule is:

```sudoers
USER_NAME ALL=(root) NOPASSWD: /etc/steamos-desktop-user/switch gaming, /etc/steamos-desktop-user/switch check
```

The final include addresses the earlier problem where a later general administrator rule required a password despite an earlier `NOPASSWD` exception. The installer validates the complete candidate with `visudo` and tests authorization as the actual desktop user.

Do not move unrelated sudo rules or edit managed helper paths casually. If manual sudo configuration changes are required, use `visudo`.

The shortcut files are named:

- `SteamOS-Desktop-User.desktop` on the gaming account.
- `SteamOS-Gaming-Mode.desktop` on the desktop account.

They are also installed in each relevant user's `~/.local/share/applications/` directory.

## 8. Troubleshooting

### “A password is required” when returning

First confirm the active username:

```bash
whoami
```

Then run the harmless authorization check:

```bash
sudo -n /etc/steamos-desktop-user/switch check
```

Use the shortcut.

From a working administrator account, run:

```bash
sudo bash ./steamos-user-switch.sh check
```

If the check fails, keep its output. Do not solve this by granting unrestricted passwordless `sudo`.

### The return shortcut is missing

Check the application launcher menu for **Return to Gaming Mode**. To recreate the desktop copy from the installed application entry, run the following **without sudo**, while logged into the configured desktop account:

```bash
install -D -m 755 "$HOME/.local/share/applications/SteamOS-Gaming-Mode.desktop" "$(xdg-user-dir DESKTOP)/SteamOS-Gaming-Mode.desktop"
```

If the source file is missing, use the manual return command after saving your documents, then rerun the installer from an administrator account to recreate the shortcuts.

### “Account does not exist”

Check the username in `DESKTOP_USER`. Create the account if needed, or correct the variable and rerun installation. The script does not create accounts automatically.

### “Uninstall the existing configuration before changing users”

The installer found a managed installation for different usernames. Follow the account-change steps below. Do not rename installation directories manually.

### An SDDM configuration precedence check fails

Another configuration file changes the original login user or session, or would override the proposed desktop selection. Stop and inspect the reported configuration. Copying an old forum configuration over `holo.conf` is not required by this installer.

### A black screen appears during switching

Allow time for the session transition. If the device remains stuck, restart it. The boot service is intended to clear this switcher's temporary desktop override.

If an ordinary restart is impossible, Valve documents holding Power for a full **16 seconds on OLED** or **10 seconds on LCD**. Boot recovery does not guarantee preservation of unsaved work.


## 9. Reinstall, change users, or uninstall

### Reinstall for the same accounts

Run the install command again from an administrator account:

```bash
sudo bash ./steamos-user-switch.sh install
```

Keep the same configured usernames. The managed sudoers block is updated without duplication.

### Change the desktop account

1. Save work and return to Gaming Mode.
2. Open the gaming user's desktop.
3. Run the uninstall command below from an administrator account.
4. Ensure the new desktop account exists.
5. Edit `DESKTOP_USER` in the downloaded installer.
6. Run `install`, then `check` again.

Editing the downloaded script alone does not change the installed configuration. The `check` and `uninstall` commands read the installed settings.

### Uninstall

From an administrator account, in the folder containing the installer, run:

```bash
sudo bash ./steamos-user-switch.sh uninstall
```

This removes the managed sudoers include, disables and removes the boot reset service, removes the temporary override, removes the generated helpers and new shortcuts, and restores saved home-directory modes when their current mode is still `700`.

Accounts and personal files are kept. Root-only backups remain in `/etc/steamos-desktop-user/backups/`. Earlier scripts, shortcuts, and independently added sudoers rules are not comprehensively removed by this uninstall operation.

Restart the device afterward. Keep backups for reference; do not blindly overwrite the current `/etc/sudoers` with an older backup.

## 10. Security and update notes

- Home-directory mode `700` limits access by other ordinary users. It does not block root or another account with full administrator access.
- The installer leaves existing administrator group memberships and other sudo permissions unchanged. If `USER_NAME` was already in `wheel`, it remains an administrator.
- Passwordless return deliberately lets the desktop account start the gaming user's session. This setup separates application data and ordinary file access; it is not a lock against an untrusted person using the device.
- Do not make the root-owned switch helper or settings writable by ordinary users.
- The default start remains Gaming Mode only while the validated original configuration and boot service remain intact. After a SteamOS update, run `check` again before relying on the switcher.
- A successful `check` validates configuration and authorization; it does not launch a graphical session or prove full compatibility with a changed SteamOS build.
