# Contributing

The rules for how a skill must be written are in [AGENTS.md](AGENTS.md).

## What makes a good skill contribution

A skill is worth adding when it teaches an agent something it would otherwise get wrong. Good candidates:

- Behavior where ScyllaDB differs from Cassandra, DynamoDB, or SQL databases
- Defaults or recommendations that changed in a recent ScyllaDB, driver, or Operator version
- Mistakes that cause production incidents: hot partitions, unpaged queries, wrong driver settings
- ScyllaDB-specific tools and APIs: ScyllaDB Cloud, Alternator, the Operator, Vector Search

Content that is already in general CQL tutorials, or that the agent can get from the ScyllaDB docs in one lookup, usually does not need a skill. Link to the docs instead.

For a new skill or a large change, open an issue first to agree on the scope.

## Workflow

1. Fork the repository and create a branch.
2. Make your changes under `skills/`. For a new skill, follow the "Adding a new skill" checklist in [AGENTS.md](AGENTS.md#adding-a-new-skill).
3. Install the validator (requires [Go](https://go.dev/doc/install)):

   ```sh
   go install github.com/agent-ecosystem/skill-validator/cmd/skill-validator@latest
   ```

4. Validate your changes. CI runs the same check in strict mode, so warnings fail the build:

   ```sh
   ./tests/validate-skills.sh skills/scylladb-<topic>/
   ```

5. Test the skill in an agent. Install it locally (see [Manual install](README.md#manual-install)), then ask the agent a few questions that should trigger it and a few that should not. Check that it loads the skill when it should and follows the instructions.
6. Open a pull request.

## Pull request checklist

Include this in your PR description:

- [ ] `./tests/validate-skills.sh` passes with no warnings
- [ ] CQL, YAML, and code examples were run or checked against the docs
- [ ] Links to the ScyllaDB docs use the `.md` URL, not `.html`, and resolve
- [ ] Version-specific behavior states the version
- [ ] No credentials, real hostnames, or customer data in examples
- [ ] README **Skills** table and install commands updated (new or renamed skills)
- [ ] Plugin manifests updated if the bundle's scope changed
- [ ] Tested in at least one agent; list which one and the prompts you used

## Validation in CI

`.github/workflows/validate-skills.yml` runs on pull requests that change `skills/**`. It validates only the skills that the PR changes. `tests/validate-skills.sh` (local) and `.github/scripts/validate-skills.sh` (CI) must stay in sync. If you change one, change the other.
