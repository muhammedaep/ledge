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
does nothing, and that is itself check 10.

---

## 1. The shelf drags — this is the product

Drop a file in `~/Downloads`, wait about five seconds, click the menu bar icon.
The row appears with its destination beneath it.

**Drag the row onto the Desktop.** The file should land there — a copy of it;
the filed one stays put, which is what keeps undo working (see
`known-limitations.md`).

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

Click the destination chip at the top of the shelf, choose **Choose Project…** from
the list that unfolds, and pick a folder. The header should name it and the menu bar icon should change shape.

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

## 6. Organize Now's count is what actually moves

Open **Organize Now…** on a folder holding more than one category. The
caption above the list and the **Move N Items** button below it should show
the same number.

Uncheck one category's toggle. Both numbers should drop together and still
agree with each other — not one counting the whole plan while the other
counts only what is selected. Click **Move** and confirm that many items
moved.

## 7. Ejecting a drive does not lock you out

If you watch a folder on an external drive: eject it while Ledge is running.

You should still be able to reach **Settings** and **Quit**. Earlier this was not
true — a permission screen replaced the entire shelf including both, and Activity
Monitor was the only way out.

With one folder blocked and another readable, the working folder's shelf should
still be visible and still filing. A blocked folder gets a banner, not a takeover.

## 8. Launch at login

Toggle it in Settings, then check:

```
sfltool dumpbtm | grep -i ledge
```

Toggle it back off if you do not want it.

## 9. Turkish layout — only if you run Ledge in Turkish

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
4. **The Rules tab's rewritten sentences, for correctness rather than fit.** Four
   Turkish sentences changed today when the Rules tab's vocabulary moved from
   "category" to "rule." Two independent reads found them sound and both flagged
   the same small thing: in "Bir kuralı yeniden adlandırmak, eski adla
   klasörlenmiş dosyaları taşımaz.", `eski adla` reads better as `eski adıyla` —
   "with *its* old name," which is what the sentence's antecedent wants. Small
   either way, but this is a call for a native reader, not a grammar rule, and
   nobody who reads Turkish has looked at it yet.

## 10. A denied permission explains itself

Deny Ledge access to `~/Downloads` in System Settings → Privacy & Security → Files
and Folders, then reopen the shelf.

You should get a screen that says what is wrong and offers a route to fix it —
along with Settings and Quit, which must never disappear.

## 11. A collapsed rule's Subfolders control is reachable

Settings → Rules. Pick a rule you have not touched — Videos, say. Change its
Subfolders to By month, save, reopen. If you cannot get at the control, that
is the defect.

Do it once with the pointer, then again with **Tab** alone. Both routes were
dead before the fix, and neither has been tried by hand since — the account of
how the keyboard one behaves came from reading the view tree, not from pressing
the key.

This is the check that would have caught a clean rule card, once collapsed,
never being reopenable again — nine of the ten default rules ship exactly
that way, with no other route to their Subfolders picker.

## 12. Screenshots get their own folder

Take a screenshot into a watched folder. It should land in `Screenshots/`, not
`Images/`. Open Settings → Rules: the Screenshots rule is there, above Images,
with its patterns visible and editable. Delete it, quit, relaunch — it must
stay deleted.

## 13. The visual pass

Look at the shelf in light and in dark, then again with Ledge set to Turkish
(System Settings → General → Language & Region → the per-app list). In each of
the four combinations:

- A filed row reads as an object you could pick up, not a line in a log. That
  containment is the whole design; if the rows read as a list, say so.
- A stale row is flat and obviously dead, and its undo is still *visible* —
  dimmed, not gone.
- The metadata line truncates from the right, so the destination survives and
  the time is what disappears. `Taşınmış veya silinmiş · 26 dk önce` must fit.
- Tab to the undo button. It takes a focus ring and fires on Return. If it
  cannot be reached without a pointer, that is a defect and not a nitpick.
- Settings → Rules: put two rules into a warning state at once and give one a
  Turkish diagnostic. The card grows, the list scrolls, nothing is clipped.
- The type badge on a screenshot is the image colour, not the Screenshots
  category's — a PNG looks like an image wherever it lands.
- File a `.zip` and a file with no extension into a watched folder. Both
  should get the neutral badge treatment — chip fill, chip border, secondary
  label — and the extensionless file's badge should carry no letters at all.
  The boards never drew this case; nobody has looked at it yet.
- Look closely at a Documents, Images or Videos badge in dark mode. The
  dark page and border (16% and 45% opacity over the family's dark label
  colour; 18% and 50% for images) are the design source's own dark values,
  read from the file rather than guessed — but nobody has seen them lit.
- With an empty shelf, or a fresh watched folder with nothing filed yet, read
  the empty state: `Nothing filed yet`, and beneath it
  `New downloads appear here — drag any row to use the file.` — the only
  line in the app that explains the product.
- Click the destination chip at the top of the shelf. A list unfolds inside
  the panel — not a menu, which would close it — with every watched-folder
  default, every project with a checkmark on the active one and a minus at
  its trailing end, and `Choose Project…` at the bottom. Click a project's
  minus: the row goes, the panel stays open, and if that was the active
  project the chip falls back to the watched folder. The folder on disk is
  untouched. The chip itself: a folder name, a `▸`, and a 16×16 accent-blue
  disclosure square carrying a white chevron.
- With a project active, the whole header block should carry a faint accent
  tint behind it — not just the label text reading `PROJECT MODE` instead of
  `FILING INTO`.
- Put a watched folder into the state check 7 describes, then click the warning
  banner's **Choose Folder Again…** button and confirm Settings comes to the
  front over whatever app you were in. Nobody has clicked this button yet. The
  code pairs `NSApplication.shared.activate(ignoringOtherApps: true)` with
  `openSettings()`, on the reasoning that the latter alone is not documented to
  raise the window while Ledge sits backgrounded as an accessory app — whether
  that pairing is doing real work or the `activate` call is redundant is
  answerable only by clicking it.

None of this replaces the checks above. An interface that looks better and
breaks the drag-out, undo, the stale row, project routing, the
folder-as-one-unit rule or the eject lockout is a loss, not a trade.

## 14. Appearance follows the setting, not the system

Settings → General → Appearance. Set it to **Light** while your Mac is in Dark
mode, then to **Dark** while your Mac is in Light mode. The shelf and the
Settings window must change together, and the choice must survive quitting and
relaunching.

Then set it back to **System** and confirm Ledge follows the Mac again.

This one cannot be checked off-screen. The project's usual colour evidence,
`ImageRenderer`, renders without a window and never sees the app appearance at
all — see `known-limitations.md`.

## 15. What could not be established here at all

Colour is deliberately missing from the list below. Three of the tasks that
built this interface measured it off-screen with `ImageRenderer` — rendering
the real view and reading pixels back, which needs no Screen Recording or
Accessibility permission at all — and that measurement is what caught a
conditional style rendering two states that were supposed to differ in the
identical grey, twice, before anyone looked at a screen. What follows is what
that technique cannot reach:

- Whether the menu bar panel notices access being **revoked while it is closed**.
  It is the only signal that catches that case, and no agent could test it.
- Anything about how the layout actually looks: spacing, alignment, whether the
  panel's cross-display frame jump when the Organize sheet attaches reads as a
  glitch, and whether the Turkish strings above actually fit the frames they
  were measured against on paper.
