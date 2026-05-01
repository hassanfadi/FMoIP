# Safe Messaging Checklist

Use this checklist before publishing any new entry in `website/notifications.json`.

## 1) Message Intent and Necessity

- [ ] The message has a clear user benefit (service update, account/billing status, feature info, or critical notice).
- [ ] The selected `priority` matches the real urgency (no inflation of urgency).
- [ ] `popupOnOpen` is enabled only when immediate attention is truly needed.
- [ ] `persistent` is used only for critical items and still provides user control.

## 2) Content Safety and Tone

- [ ] Title/body are factual, clear, and not misleading.
- [ ] No manipulative language (fear pressure, fake deadlines, deceptive urgency).
- [ ] No impersonation, fake system alerts, or confusing security claims.
- [ ] Language is respectful and suitable for all audiences.

## 3) Store Billing and Payments Compliance

- [ ] The message does not instruct users to bypass Google Play / App Store billing for digital goods.
- [ ] Links do not route users to external payment for in-app digital entitlements.
- [ ] Subscription/payment status prompts use supported platform flows.
- [ ] Google Play transactional subscription prompts remain handled by Play Billing in-app messaging where applicable.

## 4) Links and Destinations

- [ ] `url` is optional and included only when needed.
- [ ] URL is HTTPS, trusted, and controlled/approved by your team.
- [ ] Destination content is consistent with the message text.
- [ ] Destination does not contain policy-risk content (misleading offers, prohibited claims, unsafe downloads).

## 5) Targeting and Scope

- [ ] `platforms` targeting is correct (`all`, `android`, `ios`) and intentional.
- [ ] `versionTarget` is set correctly (all/specific/below/above/range).
- [ ] `expiresAt` is set for temporary campaigns so stale messages are removed.
- [ ] Message timing avoids excessive repeat prompts.

## 6) User Control and UX

- [ ] Users can dismiss, ignore, or remind later when appropriate.
- [ ] Non-critical messages are easy to close and do not block core app usage.
- [ ] Frequency is reasonable (avoid spam-like behavior).
- [ ] Badge/unread behavior is proportional and not used to pressure users.

## 7) Privacy, Data, and Logging

- [ ] Any message interaction tracking is covered by your privacy policy.
- [ ] No sensitive personal data is embedded in message payloads.
- [ ] Logging excludes secrets and personal identifiers.
- [ ] Retention of message-related state is minimal and justified.

## 8) Localization and Accessibility

- [ ] Localized text is accurate and culturally appropriate.
- [ ] Fallback language is acceptable if a locale key is missing.
- [ ] Message text is concise and readable on small screens.
- [ ] Critical meaning remains clear across all supported languages.

## 9) Technical Validation (Pre-Publish)

- [ ] JSON validates and required fields are present.
- [ ] IDs are unique and stable.
- [ ] Date formats are valid ISO-8601.
- [ ] Notification is tested on Android and iOS (display, interaction, dismissal, deep-link behavior).

## 10) Final Approvals

- [ ] Product/content owner approved wording and urgency level.
- [ ] Policy/compliance review completed for billing and external links.
- [ ] Release owner approved publish window and rollback plan.

---

## Quick Reject Rules

Do **not** publish the message if any of the following is true:

- It contains misleading, coercive, or deceptive text.
- It pushes users to external payment flows for digital in-app content.
- It cannot be dismissed but is not truly critical.
- Targeting or expiration is missing for a temporary or platform-specific message.

