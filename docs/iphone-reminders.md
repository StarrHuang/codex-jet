# iPhone reminder integration preview

The open-source Mac app now includes an optional iPhone pairing section in **Reset notifications**. The iOS companion and notification relay are under development. This source preview uses an authenticated server inbox; APNs delivery and a public HTTPS endpoint are not available yet. Existing local quota charts and desktop notifications remain available without pairing.

The intended split is:

- The relay independently distributes Tibo reset announcements to subscribed phones, even when the Mac is offline.
- An online Mac checks its own account. Within 24 hours of the nearest weekly reset or banked-card redemption deadline, it submits a personal reminder only when measured consumption projects unused quota.
- A card expiry is a manual redemption deadline, not an automatic quota refill. Account credentials, prompts and local consumption history stay on the Mac.

Connect the companion to the same HTTPS relay, generate a five-minute code on the phone, then enter it on the Mac. The Mac shows and pairs the currently loaded account; refresh quota before pairing. Product bearer tokens are kept in Keychain. Changing Codex accounts suspends sending and revokes the previous binding; the new account must be paired explicitly.

Personal forecasts require at least three samples spanning 15 minutes and a latest sample no older than ten minutes. Faster consumption, insufficient data, an expired reading, or a deadline outside 24 hours causes silence. Each cycle is handled once; acknowledgement and a 15-minute pause are held by the relay, and a paused reminder requires a fresh Mac measurement to return. While the Mac sleeps or quits, it does not create personal reminders. Public announcements are independent.

A compatible relay needs the following product API; OpenAI login credentials are never sent to it:

- `POST /v1/pairings/claim`: exchange `{code, accountRef}` for `{macID, macToken, bindingID}`.
- `POST /v1/personal-reminders`: authenticate the Mac bearer and validate the version-2 quota observation/event, binding, expiry and cycle deduplication.
- `POST /v1/unpair`: revoke the binding and remove pending personal messages.

The server regenerates notification wording in the recipient's language. An accepted submission means the server accepted it, not that a phone displayed it. English, Simplified Chinese, Japanese and Korean are supported in the Mac pairing screen. The iOS release, privacy disclosures, distribution and real push tests remain separate work.

Run `./scripts/test-pocket.sh` for the Mac forecast, payload privacy, account isolation and URL-boundary behavior checks. The full app still builds with `swift build`. Reset-source attribution remains with [codex-reset.com](https://codex-reset.com/).
