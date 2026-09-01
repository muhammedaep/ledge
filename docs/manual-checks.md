# Manual checks

> In Turkish: [`manual-checks.tr.md`](manual-checks.tr.md). The two files are
> the same list — if one changes, the other has to.

Everything in this list needs a human with a pointer and a screen. None of it can
be automated from a headless session, and all of it was left unverified when the
first version was built — so it is the shortest path from "the tests pass" to
"someone has actually seen this work".

Run it before a release. It takes about ten minutes.

## Setup

```
open Ledge.xcodeproj      # ⌘R
```

The app has no Dock icon. Look for a tray icon in the menu bar.

If macOS says **Not enough room to show “Ledge”**, the menu bar is full
and the status item was never created — the app is running, it just has nowhere
to appear. This is common on a notched MacBook, where the notch takes the middle
of the bar. Free a slot (⌘-drag an icon out of the bar, or turn Control Center
modules off in System Settings → Control Center), then **relaunch Ledge** — the
item is not retried after the failure. A menu bar manager does not help: it
hides items rather than creating slots.

macOS will ask for permission to read `~/Downloads` the first time. Allow it — if
you decline, you should get an explanatory screen rather than an app that silently
does nothing, and that is itself check 9.

---

## 1. The shelf drags — this is the product

Drop a file in `~/Downloads`, wait about five seconds, click the menu bar icon.
The row appears with its destination beneath it.

**Drag the row onto the Desktop.** The file should land there.

If this does not work, nothing else matters: rule-based filing without drag-out is
just an organiser, and the whole premise was doing both.

## 2. Undo returns the file

Click the row's undo arrow. The file returns to `~/Downloads` and the row
disappears.

Then press **⌘Z** with the shelf open — it should undo the most recent move. If
that move was part of an Organize Now batch, ⌘Z undoes the whole batch, not one row.

⌘Z on an empty shelf should do nothing at all — no error, no beep.

## 3. A stale row goes quiet

File something, then move that file somewhere else in Finder. Close the shelf and
reopen it **without downloading anything new**.

The row should dim, refuse to drag, and its undo button should be greyed. Undo is
the weakest link here — check it specifically.

Then move the file back and reopen. The row should come alive again.

## 4. Project mode routes downloads

Open the shelf's destination menu at the top, choose **Choose Project…**, and pick
a folder. The header should name it and the menu bar icon should change shape.

Download something. It should land in that project's category subfolder, not in
`~/Downloads`.

Then undo it. **It should return to `~/Downloads`** — where it was found — not into
the project. That distinction is deliberate.

Set the destination back to Downloads when you are done.

## 5. Organize Now never splits a folder

Make a scratch folder with loose files **and a subfolder containing a file**:

```
mkdir -p ~/Downloads/scratch/"Some Project"
cd ~/Downloads/scratch
touch a.png b.png c.mp4 notes.txt
touch "Some Project/inner.png"
```

Add `~/Downloads/scratch` as a watched folder in Settings, then open **Organize
Now…** and select it.

The preview should list `Some Project` as **one** entry, never `inner.png`. Move
them, then confirm `inner.png` is still inside `Some Project`. Then **Undo Last
Batch** and confirm everything returns.

Remove the watched folder and `rm -rf ~/Downloads/scratch` afterwards.

## 6. Ejecting a drive does not lock you out

If you watch a folder on an external drive: eject it while Ledge is running.

You should still be able to reach **Settings** and **Quit**. Earlier this was not
true — a permission screen replaced the entire shelf including both, and Activity
Monitor was the only way out.

With one folder blocked and another readable, the working folder's shelf should
still be visible and still filing. A blocked folder gets a banner, not a takeover.

## 7. Launch at login

Toggle it in Settings, then check:

```
sfltool dumpbtm | grep -i ledge
```

Toggle it back off if you do not want it.

## 8. Turkish layout — only if you run Ledge in Turkish

The interface is localised, but **it will not appear in Turkish unless your system
language is Turkish**, or you assign Turkish to Ledge specifically in System
Settings → General → Language & Region → the per-app list at the bottom.

If you do, the places most likely to break are, in order:

1. **Settings → Rules diagnostics.** The window is a fixed 560 × 460 and the
   warning text never truncates — it expands. Turkish runs 27–35% longer. Put two
   or three categories into a warning state at once: name two `Images` and
   `IMAGES`, and give one an extension a higher rule already claims. Watch for the
   pane outgrowing the window.
2. **The shelf row subtitle.** `Taşınmış veya silinmiş` is 38% longer than the
   English and sits in the app's tightest horizontal budget, competing with the
   date and the undo button. Look at a stale row with a long filename.
3. **The Organize sheet's Move button** with a three-digit count.

## 9. A denied permission explains itself

Deny Ledge access to `~/Downloads` in System Settings → Privacy & Security → Files
and Folders, then reopen the shelf.

You should get a screen that says what is wrong and offers a route to fix it —
along with Settings and Quit, which must never disappear.

## 10. What could not be established here at all

- Whether the menu bar panel notices access being **revoked while it is closed**.
  It is the only signal that catches that case, and no agent could test it.
- Anything about how the layout actually looks: spacing, alignment, whether the
  panel's cross-display frame jump when the Organize sheet attaches reads as a
  glitch.
