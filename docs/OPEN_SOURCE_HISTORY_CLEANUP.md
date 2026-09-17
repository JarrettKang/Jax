# Open-source history cleanup

The single authorized combined cleanup has been executed. It retained 160
historical commits, their messages, dates and parent topology, while removing
private recovery evidence and sanitizing known personal paths, device identifiers
and private rollout evidence. Mixed documents were sanitized per historical blob
version; old versions were not replaced wholesale with current documentation.

Author and committer are Jarrett <212651844+JarrettKang@users.noreply.github.com>.
Jarrett leads product design, requirements, architecture, iteration, testing and
maintenance, with extensive AI-assisted development using OpenAI Codex. A later
README should explain that attribution transparently.

The cleaned historical base is cab33a7d1d1f604aea9aa002b4ceb91c811bc031. It remained
frozen during verification. One normal RC consolidation commit brings the count
to 161; no second rewrite, squash, author rewrite or privacy-rule change occurred.
Resolve the consolidation hash from the current candidate HEAD or its public
commit subject, Prepare release candidate for public source.

The approved RC source, tests, safety tooling and public documentation are included.
Private audit logs, databases, backups, screenshots and transformation mappings
are excluded. Historical privacy/topology verification and final scans are retained
outside the public repository. Generic ignore/safety references to private output
locations are not private file contents.

See RELEASE_CANDIDATE.md for the verified test/build matrix, three-layer Android
database evidence, and Known automated test harness limitation. The database
blocker was released; the Flutter protocol limitation remains documented.

No remote, publication or GitHub push occurred. License, package identity,
production signing, README, screenshots and CI remain Phase 5 decisions.
