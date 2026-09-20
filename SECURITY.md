# Security policy

Do not disclose sensitive vulnerability details, personal data or credentials in
public issues or pull requests.

Use GitHub private vulnerability reporting **once it has been enabled** for the
published repository (Security → Report a vulnerability). The repository is still
being prepared; this document does not claim that channel is already available.
If the private-reporting option is absent, withhold sensitive details until a
private channel is established. Do not post a vulnerability as a public fallback.

Provide a minimal synthetic reproduction, affected revision/platform and impact.
Never attach a real user database, signing key or password. No response-time SLA
or long-term supported release series is currently promised.

Jax does not encrypt SQLite contents at rest. Experimental ADB developer Sync and
local backup tools have explicit access and destructive-operation boundaries;
read [TOOLS](docs/TOOLS.md) before use.
