# The "Paywise" Shortcut

A double tap on the back of the iPhone (Back Tap) runs this Shortcut; the Action Button can run it too. It takes a
screenshot and hands it to Paywise's **Check Checkout** action. From the Share Sheet it checks the shared image
instead (SPEC §9.1, §4.5, §6.6 G1).

```
Receive Images from Share Sheet        If there's no input: Continue
If  Shortcut Input  has any value
    Check Checkout   Screenshot: Shortcut Input
Otherwise
    Take Screenshot
    Check Checkout   Screenshot: Screenshot   (the output of Take Screenshot)
End If
```

**Names, read from the code:** the action is **Check Checkout** (`CheckCheckoutIntent`, `static let title`) and its
only field is **Screenshot** (`@Parameter(title: "Screenshot") var image`). The built app's
`Metadata.appintents/extract.actionsdata` (Oct 15) has the same names.

**(u)** means not yet tried on an iPhone. Nothing here has run on a phone yet. Screen labels come from the
macOS 27.0.1 Shortcuts strings and from iOS 17/18. iOS 27 may name or place a few of them differently.

**Before you start:** install the Paywise build, open it once and add your cards. iOS lists the app's actions only
after the first launch (u). **Start a stopwatch. Target: steps 1–14 in under 2:00.**

---

## A. Get the Shortcut: pick one (≈0:15 for a file or link, ≈1:10 to build by hand)

**A1. From the file or link (fastest).** AirDrop `ios/Shortcut/Paywise.shortcut` from the Mac to the iPhone, or open
the team's iCloud link (see "Share it" below). Tap **Add Shortcut** (u). Then check it against the box above
(open it in Shortcuts) and go to **B**.

**A2. Build it by hand.**

1. Open **Shortcuts**, go to the **Shortcuts** tab and tap **+** (top right).
2. Tap the name at the top (**New Shortcut**), then **Rename**. Type `Paywise` and tap **Done**.
3. Tap **ⓘ** (Details) and turn on **Show in Share Sheet**, then tap **Done**. A **Receive Any … from Share Sheet** row appears at the top.
   (u: on some iOS versions **Details** is in the menu under the name.)
4. In that row, tap **Any** and then **Clear**. Tick **Images** only and tap **Done**. Make sure the row still says
   **If there's no input: Continue**. If it says *Stop and Respond* or *Ask For*, the branch that Back Tap and the Action Button run breaks.
5. In the action search at the bottom, type `if` and tap **If**. Its first token must read **Shortcut Input**. If it
   doesn't, tap the token and pick **Shortcut Input**.
6. Tap **Condition** and pick **has any value**.
7. Search `Check Checkout` and tap it (it's listed under **Paywise**). Drag it up so it sits between **If** and **Otherwise**.
8. In that action, tap **Screenshot** and pick **Shortcut Input**.
9. Search `Take Screenshot` and tap it. Drag it between **Otherwise** and **End If**.
10. Search `Check Checkout` again and tap it. Drag it under **Take Screenshot**, still above **End If**.
    Its field must show a blue **Screenshot** token with the Take Screenshot icon. If it shows the grey placeholder
    *Screenshot* instead, tap it and pick **Screenshot**.
11. Leave **Show When Run** on in both Check Checkout actions if a **›** shows it. Turning it off may hide the
    answer (u). No other action here has a prompt or notification to turn off.
12. Tap **Done**.

## B. Bind the trigger (≈0:15)

Back Tap first: it works on any iPhone that runs Paywise and leaves the Action Button alone. All the triggers run the same
**Paywise** Shortcut on the screen you're looking at, and none of them saves a screenshot to Photos: **Take
Screenshot** hands the image to Check Checkout in memory. iOS has no API for Back Tap, so the app can't turn it on,
see whether it's on, or open its settings page; the app's **Set Up Back Tap** screen shows the path instead.

13. **Back Tap:** **Settings › Accessibility › Touch › Back Tap › Double Tap** and pick **Paywise** (in the Shortcuts
    section). Then you double-tap the back of the phone at checkout. Back Tap 5/5 on the owner's iPhone, Oct 16
    (`docs/spikes.md`).
    **Action Button (optional):** if you don't use it for Silent, **Settings › Action Button**, swipe to **Shortcut**,
    tap **Choose a Shortcut…** (u: label) and pick **Paywise**. Then you press and hold it at checkout. (The iPhone's
    default is Silent Mode, and many people keep it.)
    **Control Center (u: not yet tested):** swipe down from the top right, tap **+ › Add a Control › Shortcut ›
    Choose › Paywise**. At checkout you open Control Center and tap it. Control Center must close before **Take
    Screenshot** runs, or the screenshot shows Control Center rather than the store; if it does, add **Wait 1 s** as the
    first action of the Paywise Shortcut and test again.

## C. Try it: clear the first-run prompts (≈0:25)

14. In the app, **Set Up Back Tap › Try it now** shows a sample checkout: double-tap the back of the iPhone there, and
    the screen turns to **Back Tap works ✓** when the check arrives. Or, in Safari, open
    **https://paywise-store.onrender.com/checkout.html?item=laptop** (it answered HTTP 200 on Oct 15) and double-tap the
    back (or press and hold the Action Button). Answer each prompt with **Always Allow**. Expect, once each (u: wording
    from the macOS 27 Shortcuts strings; the Shortcut and the app share a name, so "Paywise" appears twice):
    - **Allow "Paywise" to take a screenshot?**
    - **Allow "Paywise" to share "Screenshot" with "Paywise"?** (the middle part may read "1 image")

    *Checking* shows in the island, then the answer. Double-tap again: there should be no prompts, then **stop the
    stopwatch**. If the first double tap says "No checkout total found", the prompts covered the screen. Double-tap
    once more. Record the time in `docs/spikes.md` (S6 setup stopwatch, §15.7 step 14).

## D. Test the Share Sheet branch (optional, outside the 2:00)

15. On the same checkout page, take a screenshot (**Side + Volume Up**). Tap the thumbnail and then **Share** (↑).
    Scroll down the list and tap **Paywise**. If it isn't listed, tap **Edit Actions…** to add it (u). The answer
    comes from the shared image, and no new screenshot is taken. Expect one more **Allow … to share …** prompt the
    first time; answer **Always Allow**.
    The same works from **Photos**: open a screenshot, tap Share and pick **Paywise**. This is the §6.6 G1 fallback
    path ("screenshot → share → answer").

---

## Troubleshooting

| You see | Do |
|---|---|
| Nothing happens on a double tap | Open **Shortcuts**, long-press **Paywise** and tap **Details** (or open it and tap **ⓘ**). Check: Share Sheet on, Images only. In **Privacy**, nothing should be blocked. Back in the editor, tap **▶**. You should get "No checkout total found" for the Shortcuts screen, which proves the chain works, or an error that names the broken action. Also check that **Settings › Accessibility › Touch › Back Tap › Double Tap** (or **Settings › Action Button**) still shows Paywise. |
| The island works but the snippet never appears (§6.6 G2) | In the **Paywise** app, go to **Settings › Results › Switch results** and pick **Island alert, held 8 s**. Switch answers then come as an 8 s island alert. To save one, open the **Paywise** app: the **Check** tab shows your last check with **Paying with …**. |
| "Use the Paywise shortcut" | Check Checkout ran without an image. Redo steps 8 and 10 so both fields hold a blue token. |
| A prompt on every press | You tapped *Allow Once*. Go to **Details › Privacy › Reset Privacy**, press again and pick **Always Allow**. |
| **Check Checkout** isn't in the action search | Open the Paywise app once, then search `Paywise`. |
| "Couldn't check this time" | The backend didn't answer within 6 s. Press again. If it keeps happening, check `/health` (see `docs/hosting.md`). |
| The screenshot shows Shortcuts, Control Center or Paywise, not the store (G1 fails) | Report it with the What we sent text (it shows what was read). Try **Wait 0.5–1 s** before **Take Screenshot**, and Take Screenshot's **Ignore Contextual Assistance Layers** option (u). Until it's fixed, use the in-app **Check a screenshot**. Don't use a "When a screenshot is saved" automation: the owner ruled it out (Oct 16) because it fills Photos with checkout screenshots and runs on every screenshot. |

## Share it (for the setup screen's "Shortcut link", §5.1 step 3)

Until the link exists, the app's setup screen offers **Show the steps**: a short, user-facing copy of steps 1–15 above
(`ShortcutSteps` in `ios/Paywise/Onboarding/TriggerSetupView.swift`, same numbers). Change both together.

In **Shortcuts**, long-press **Paywise** and tap **Share › Copy iCloud Link** (u). Anyone who opens the link needs the
Paywise app installed first, because the Check Checkout steps belong to the app.

## The signed file `Paywise.shortcut`

This is the Shortcut in the box above, signed on the Mac with `shortcuts sign --mode anyone`. Before you rely on it,
open it on a phone and compare it with the box (u: the plist keys follow Apple's own gallery shortcuts in
WorkflowKit, and the app-action entry follows the Notes example there). The parts never tried on iOS are the If
condition code `100` = "has any value" and the `com.azealoo.paywise.CheckCheckoutIntent` action ID.

To change it, unpack it, edit `Shortcut.wflow` and sign it again (run in an empty folder):

```bash
python3 -I -c 'import plistlib,struct,sys;d=open(sys.argv[1],"rb").read();n=struct.unpack("<I",d[8:12])[0];open("leaf.der","wb").write(plistlib.loads(d[12:12+n])["SigningCertificateChain"][0])' Paywise.shortcut
openssl x509 -inform der -in leaf.der -noout -pubkey > leaf.pem
aea decrypt -i Paywise.shortcut -o payload.aar -sign-pub leaf.pem && aa extract -i payload.aar -d out   # out/Shortcut.wflow
plutil -convert xml1 out/Shortcut.wflow        # edit, then:
shortcuts sign --mode anyone --input out/Shortcut.wflow --output Paywise.shortcut
```

## Checklist

- [ ] The Paywise app has been opened once and has cards
- [ ] The Shortcut is named **Paywise** and matches the box: 6 actions, both fields hold blue tokens
- [ ] **Show in Share Sheet** is on, with **Images** only and **If there's no input: Continue**
- [ ] One direct trigger runs Paywise: **Back Tap › Double Tap › Paywise** (first), the **Action Button** (Shortcut › Paywise), or the Control Center Shortcut control (u)
- [ ] The first double tap (Try it now, or the demo store) answered both prompts with **Always Allow**, and a second one shows no prompt
- [ ] The Share Sheet branch was tested from a screenshot
- [ ] The time is recorded: ≤2:00 for steps 1–14
