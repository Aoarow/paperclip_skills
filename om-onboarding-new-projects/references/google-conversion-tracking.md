# Google Ads conversion tracking for a client website

Load this when a Google Ads property has no verified conversion for its goal in `strategy.md`.
It records what Lexacore does as the agency, who does which step, and when tracking counts as
proven. First done end to end for `wordsbydaniela.com` (DOW) on 2026-09-17.

## Who does what

Most clients cannot set this up, and they should not have to. Lexacore does it, split by who can
reach the system:

| Step | Owner | Why |
| :--- | :--- | :--- |
| Decide the counted primary action | Human (records it in `strategy.md`) | Business decision |
| Create the conversion action | API, human-supervised session | Account write outside every autonomy level |
| Install the tag on the website | Human-supervised browser session with the client's CMS login | Agents have no CMS access |
| Consent entry for the tag | Same session | Legal requirement in DE |
| Real test submit | Human solves any captcha | Agents never solve captchas |
| Privacy-policy mention | Same session, text approved by a human | Not legal advice |
| Record evidence | `data-sources.md` | Peggy and the property agents read it |
| Lift the tracking gate | Human edits `strategy.md` | Human-owned file |

Peggy does not perform these steps. If tracking is missing she reports the exact gap and owner,
as `google.md` already requires.

## 1. Conversion action

- **Exactly one counted primary action per business outcome.** Every other action is secondary.
  A phone-call action next to a form action is secondary, even though a call is also a lead:
  campaign creation requires a single counted primary (see `om-google-campaign-creation`,
  pre-flight check 2). Google-hosted actions are system-managed and are ignored by that check.
- Lead form defaults: category `SUBMIT_LEAD_FORM`, type `WEBPAGE`, `ONE_PER_CLICK`,
  click-through window 90 days (couples and service buyers decide slowly). Google sets a
  default value of 1 EUR; leave it until a real average order value is known.
- Create with `validateOnly` first, then for real, then read back every field.

## 2. The tag

- Place the Google tag (`AW-…`) site-wide in the page head.
- **Fire the conversion only on a server-confirmed success**: a thank-you page, or the moment
  the form's success message becomes visible. **Never on the submit click.** A click also
  fires on validation errors and before a captcha.
- **Gate the whole snippet behind consent.** Without consent neither the tag nor `dataLayer`
  may exist on the page.

### IONOS MyWebsite Now

- Editor → Einstellungen → **Head-Code** holds custom head HTML. Its "Datenschutz-Zustimmung"
  selector gates the code behind one consent entry.
- Editor → Einstellungen → Datenschutz-Einstellungen → Einwilligungen → **Neue Zustimmung**
  creates that entry, e.g. "Google Ads (Conversion-Tracking)".
- The contact form submits via XHR and shows `.form-message.form-success` on success. It has
  no thank-you page. Watch that element with a `MutationObserver` and send the conversion once
  per page view.
- Changes go live only after "Veröffentlichen". Verify on the live page, not in the editor.
- Visitors who decided on the banner before the entry existed are not asked again.

## 3. Proof

Tracking counts as proven when all of these hold on the **live** site:

1. Without consent: no `googletagmanager` script and no `dataLayer`.
2. With consent: the tag loads.
3. A real submit (a human solves the captcha) shows the success message and produces exactly
   one `conversion` event with the right `send_to`. Hits to Google carry the conversion label.
4. The evidence is written to `data-sources.md`: action ID and settings, tag and label, where
   the code lives, test date and result.

Attribution to an ad click **cannot** be proven before the first real click. Keep
conversion-based bidding locked in `strategy.md` until the first attributed conversion. Zero
conversions at zero clicks is not a defect.

## 4. Privacy policy

The site's privacy policy must name Google Ads conversion tracking: provider, data, consent
basis, withdrawal, and US transfer. Client policies are often copied templates that list tools
the site does not use. Inventory what the site actually loads before writing. Text is approved
by a human; Lexacore gives no legal advice.
