# Security

## Intended deployment

Run the server only on a trusted private network. Do not forward port 8787 from your router or place the service on a public host. The current protocol authenticates every request but does not encrypt LAN traffic.

The iCloud Shared Album URL grants read access to the album. Keep it in your private configuration and use a dedicated album for the frame.

## Secrets and personal data

The installer creates a random 256-bit bearer token at:

`~/Library/Application Support/KindleVoyagePhotoFrame/data/server-token`

The file is mode `0600`. It is also copied to the Kindle. Configuration files, rendered photos, cache data, diagnostics, logs, and device backups must not be committed.

To rotate the token, stop the two LaunchAgents, delete `server-token`, start the server again, and rerun `scripts/install-kindle.sh` over USB.

## Reporting a vulnerability

Open a GitHub security advisory for the repository. Include the affected version, reproduction steps, and impact. Do not attach a real album URL, bearer token, personal photo, or diagnostic archive to a public issue.
