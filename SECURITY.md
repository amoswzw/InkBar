# Security policy

## Supported versions

Only the latest release is supported; fixes ship as a new release.

## Scope

InkBar runs as your user and needs two permissions, so these are the areas we care most about:

- **Accessibility**: InkBar reads the menu bar's items and presses or drags them for you.
- **Screen Recording**: InkBar captures pictures of menu bar items only, and keeps them in
  `~/Library/Application Support/InkBar/Icons`. Nothing leaves the Mac.
- It hides items through the macOS 27 menu bar allowlist (a private framework), which the
  system releases when InkBar quits.

Reports about InkBar reading, sending or keeping anything beyond that are especially welcome.

## Reporting a vulnerability

Please don't open a public issue for a security problem. Report it privately instead:
on GitHub, open the **Security** tab of this repository and choose **Report a vulnerability**.

Please include as much as you can:

- the affected version or commit
- your macOS version and Mac model
- steps to reproduce, or a proof of concept
- what an attacker could do with it
- any ideas for a fix

## Response

- New reports are acknowledged within 72 hours.
- A first assessment follows within 7 days.
- Once a fix is out, we agree on a disclosure timeline with the reporter.
