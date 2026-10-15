# Security Policy

## Reporting a vulnerability

MeetPaw handles OAuth tokens and calendar data, so security reports are taken
seriously. **Please do not open a public issue for security problems.**

Instead, email **nazreenexe@outlook.com** with:

- A description of the issue and its impact
- Steps to reproduce (a minimal case is ideal)
- Any relevant versions (macOS, MeetPaw)

You'll get an acknowledgement, and a fix or mitigation plan as quickly as
possible. Please give a reasonable window to address the issue before any
public disclosure.

## Scope

MeetPaw runs entirely on your Mac and stores tokens only in the macOS Keychain.
It has no backend servers. Relevant areas for reports include the OAuth flow,
token storage, the local loopback listener used during sign-in, and the Zoom
HTTPS redirect-forwarding page.
