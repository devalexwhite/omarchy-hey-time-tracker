# HEY Time Tracker for Omarchy

A native Quickshell bar plugin using your existing HEY CLI login. No additional Python packages are required.

Click the **play icon** to start a timer in HEY. The bar switches to a **stop icon with HH:MM:SS** and updates every second, including time spent suspended. It syncs with HEY every ten seconds and on each action, including timers started or stopped in another HEY app.

Click Stop to review the session. HEY continues tracking while the form is open. Edit start/end timestamps, category, and notes:

- **Save** completes the existing HEY timer with the reviewed fields.
- **Delete** removes that timer from HEY.
- Dismissing the menu continues the same HEY timer. Unsaved category and notes edits remain in the popup's memory until the shell reloads.

HEY owns the timer's ID and start time, so tracking survives shell restarts and reboots without a local timer file. An existing HEY timer is picked up automatically. Old `timer.json` files are ignored and are never automatically uploaded.

## Install

Requires Omarchy 4 (Quattro) with its Quickshell shell, Python 3, and HEY CLI 1.7.0 or newer with a stored login (`hey auth login` if needed).

Install and enable the widget with Omarchy's plugin manager:

```sh
omarchy plugin add https://github.com/devalexwhite/omarchy-hey-time-tracker --enable
```

Omarchy asks for confirmation and bar placement. The plugin runs from its own git checkout and does not include an install script or modify packaged system files.

```sh
omarchy plugin update io.github.devalexwhite.hey-time-tracker
```

After an update, run `omarchy restart shell` if the bar retains cached plugin code; the timer continues in HEY during the restart.

If you previously installed the local prototype, disable `local.hey-time-tracker` before enabling this version to avoid duplicate widgets. This does not stop a running HEY timer.

In Omarchy's bar settings, or on the plugin entry in `~/.config/omarchy/shell.json`, configure optional defaults:

```json
{
  "id": "io.github.devalexwhite.hey-time-tracker",
  "defaultCategory": "Client work",
  "defaultNotes": "",
  "account": ""
}
```

The configured account selects which HEY timer the bar follows. A blank account uses the HEY CLI's default account. Enter full local timestamps such as `2026-10-08T09:30:00`, or an explicit UTC offset such as `2026-10-08T09:30:00-04:00` to disambiguate daylight-saving transitions.

## Sync and save failures

HEY CLI 1.7 editing completes a running timer, so the review menu leaves it running until Save. Category and notes defaults apply to the review form; HEY receives them on Save. Blank optional fields preserve HEY's existing values because the CLI cannot clear them with blank flags.

Save and Delete verify that the current HEY timer still matches the form's recording ID. If another app has finished or replaced it, the action refuses to modify a different timer. Failed requests show an error; the next successful sync reads HEY again. No writes are retried automatically and Save never creates a replacement entry.

## Development

```sh
python3 -m unittest discover -s tests -v
```

The tests use a fake HEY client and do not write to your account.

The interface inherits the running Omarchy theme and its `qs.Ui` Button, TextField, Dropdown, WidgetButton, and KeyboardPanel components. Typography, colors, borders, focus states, spacing, and popup placement come from `qs.Commons.Style`, `Color`, and `Border`; no packaged system files are modified.

## Remove

```sh
omarchy plugin disable io.github.devalexwhite.hey-time-tracker
omarchy plugin remove io.github.devalexwhite.hey-time-tracker
```

Omarchy asks before removing the checkout. Removing the widget leaves any running HEY timer running. Stop or delete it in HEY if needed.

## License

MIT. This is an independent community plugin for HEY Calendar.
