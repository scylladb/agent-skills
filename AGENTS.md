# AGENTS.md

Guidance to AI coding agents that create or edit skills in this repository. Human contributors should read [CONTRIBUTING.md](CONTRIBUTING.md) too.

Skills follow the [Agent Skills specification](https://agentskills.io/specification). This file adds the conventions specific to this repository.

## Repository layout

```
skills/
  scylladb/               # parent skill: overview and map of the other skills
    SKILL.md
  scylladb-<topic>/
    SKILL.md              # required: frontmatter + instructions
    references/           # optional: detail loaded on demand
      <topic>.md
    scripts/              # optional: executable helpers the skill runs
.claude-plugin/           # Claude Code plugin + marketplace manifests
.cursor-plugin/           # Cursor plugin + marketplace manifests
tests/validate-skills.sh  # local validation
.github/                  # CI validation of changed skills
```

`skills/` is the only source of skill content. Both plugin manifests point at `./skills/`, so never copy skill files anywhere else.

## Naming

- Directory name: `scylladb-<topic>`, kebab-case. Example: `scylladb-vector-search`. The one exception is the parent skill, `scylladb` (see "The parent skill" below).
- The frontmatter `name` must equal the directory name exactly.
- `name`: 1-64 characters, lowercase letters, digits, and single hyphens. No leading, trailing, or double hyphens.
- The skill file is always `SKILL.md` (uppercase).
- Reference files: kebab-case `.md`, named after the topic. In skills that group references (see `scylladb-data-modeling`), prefix with the group: `antipattern-hot-partitions.md`, `pattern-bucketing.md`.

## Frontmatter

Use only `name` and `description`. Do not add other fields unless the specification defines them and there is a clear reason.

```yaml
---
name: scylladb-<topic>
description: <What the skill does, one sentence>. Use this skill when <the situations where the agent should load it>. Triggers on "<phrase>", "<phrase>", "<phrase>".
---
```

The description is the only part of the skill the agent sees before it decides to load the skill. Write it so that the agent loads the skill at the right time:

- Start with what the skill does, then say when to use it.
- End with a `Triggers on "..."` list of the words a user will actually type: product names, config keys, error messages, CQL keywords.
- Keep the prose part longer than the trigger list. The validator flags descriptions that are mostly keywords.
- Maximum 1024 characters.
- Add one sentence before `Triggers on` that sends the closest adjacent topic to the correct skill, for example "CQL schema design goes to scylladb-data-modeling." Keep skill names out of the trigger list (see "Cross-skill boundaries" below).

## SKILL.md body

Keep SKILL.md short. Its job is to give the agent the most important rules and tell it which reference to read next.

- **Target: under 150 lines.** The validator warns at 500 lines or 5,000 tokens, but every current skill is under 120 lines. Move detail into `references/`.
- Use this outline. Rename or drop sections when they do not fit, but keep the order:

```markdown
# <Skill Title>

If the task goes beyond this skill, use the parent `scylladb` skill for a ScyllaDB overview and the list of other ScyllaDB skills. If it is not installed, fetch it from `https://raw.githubusercontent.com/scylladb/agent-skills/main/skills/scylladb/SKILL.md`.

<1-3 sentences: what this covers and the single most important fact.>

## When to Use This Skill

- <Concrete situation>
- <Concrete situation>

<Which sibling skill to use instead for adjacent topics.>

## <Core rules / key principle / setup steps>

<The few rules the agent must follow even if it reads nothing else.>

## Quick Reference

- [<reference-name>](references/<reference-name>.md) — <What it covers>. Consult when <situation>.
```

- In the Quick Reference, every link has a "Consult when ..." clause. That clause is what tells the agent to open the file, so make it specific.
- Copy the parent pointer line exactly as shown. It is conditional on purpose: an unconditional "use the parent first" line makes the agent load or fetch the parent on every use of the child.

## The parent skill

`skills/scylladb/SKILL.md` is the entry point: a short ScyllaDB overview and a map of the other skills. It does not follow the outline above. Do not edit it unless a skill, API, feature, or tool is added, renamed, or removed. Then change only the affected entry in "How to Run ScyllaDB", "APIs", "Features", or "Tools", in "Choosing the Right Skill", and the `description`. Do not move content from a child skill into the parent.

## References

- Put references in `references/` only. Put executable helper scripts in `scripts/` ([Agent Skills specification](https://agentskills.io/specification)). Do not create other directories (`docs/`, `examples/`, and so on) or extra files at the skill root such as `README.md`.
- Link every reference file and every script from SKILL.md. The validator flags unreachable files as orphans.
- Link one level deep: SKILL.md links to references. A reference may point to another reference in the same skill, but do not build chains the agent must follow to find basic information.
- Keep each reference focused on one topic. Aim for 50-150 lines. Add a short table of contents at the top of files longer than that.
- Use relative links (`references/filtering.md`), never absolute GitHub URLs.

## Writing style

Write for an AI agent that already knows general databases, Cassandra, and DynamoDB. It does not know what is specific to ScyllaDB.

- **Include only what the agent would get wrong without the skill.** Focus on where ScyllaDB differs from Cassandra, DynamoDB, Aerospike or SQL, on defaults that changed between versions, and on mistakes that cause production problems.
- **Use the imperative.** "Use `TokenAwarePolicy`", not "You should consider using `TokenAwarePolicy`".
- **Be specific.** Give the exact config key, CQL statement, driver option, or version number. "Set `alternator_write_isolation: only_rmw_uses_lwt`" is better than "configure write isolation appropriately".
- **Show wrong and right.** For anti-patterns, give the incorrect example, then the correct one, then when the rule does not apply. `scylladb-data-modeling/references/` shows the format.
- **Make examples runnable.** CQL, YAML, and driver code must be correct and complete enough to copy. Mark placeholders clearly (`<cluster-id>`, `YOUR_PASSWORD`).
- **State version requirements.** When behavior depends on a ScyllaDB, driver, or Operator version, say which version. Example: "As of ScyllaDB 2025.4, `WITH replication` is optional."
- **Link to the ScyllaDB docs wherever you can instead of copying them.** Copied docs go out of date. Summarize the rule the agent needs in one sentence and link to the source, inline, where the rule appears. A list of links at the end of the file does not replace this: if the body restates a docs page, it is still a copy. When you read the docs to check facts, use them to verify and to link to, not as text to rewrite.
- **Link to the Markdown version of a docs page, not the HTML page.** Every page on `*.docs.scylladb.com` is also served as Markdown. Replace `.html` with `.md`, and use `index.md` for a directory URL. Check each link with `curl -sI <url>` before you commit.

  | Wrong | Right |
  | --- | --- |
  | `https://docs.scylladb.com/manual/stable/architecture/tablets.html` | `https://docs.scylladb.com/manual/stable/architecture/tablets.md` |
  | `https://cloud.docs.scylladb.com/stable/api-docs/` | `https://cloud.docs.scylladb.com/stable/api-docs/index.md` |

## Cross-skill boundaries

Skills must not contradict each other or duplicate the same content.

- Before adding content, check whether another skill in `skills/` already covers it. If it does, link to that skill by name instead of repeating the content.
- When a topic is near another skill's scope, state the boundary in two places: one sentence in the `description` ("X goes to `<skill>`", see "Frontmatter" above), and in "When to Use This Skill". Example from `scylladb-alternator`: "For schema design guidance ... defer to the `scylladb-data-modeling` skill."
- If you change a fact (a default, a version, a recommended driver) in one skill, search all of `skills/` for the same fact and update every occurrence.

## Safety

- Never put real credentials, hostnames, cluster IDs, or customer data in examples.
- For destructive operations (`DROP`, `TRUNCATE`, deleting clusters, scaling down), tell the agent to get explicit confirmation from the user first.
- Do not tell the agent to disable authentication, TLS, or other security settings except for clearly labeled local testing and when explicitly asked.

## Adding a new skill

1. Create `skills/scylladb-<topic>/SKILL.md` with the frontmatter and outline above, including the parent pointer line and a boundary sentence in the description.
2. Add `references/` files as needed and link each one from SKILL.md.
3. Update the parent skill `skills/scylladb/SKILL.md`:
   - add a row to the "Choosing the Right Skill" table
   - add the new topic to the parent `description`; name the skill there only if its topic overlaps with general ScyllaDB tasks
4. Update `README.md`:
   - add a row to the **Skills** table
   - add a `npx skills add scylladb/agent-skills --skill scylladb-<topic>` line under **Install specific skills**
5. If the new skill changes the scope of the bundle, update the `description` and `keywords` in `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `.cursor-plugin/plugin.json`, and `.cursor-plugin/marketplace.json`.
6. Run the validator (see below) and fix all errors and warnings.

## Editing an existing skill

- Keep the existing outline and tone of that skill.
- If you rename or delete a reference file, update every link to it.
- If you rename or remove a skill, update the parent skill's "Choosing the Right Skill" table and `description`, the README, and the plugin manifests.
- If you change the `description`, keep the existing trigger phrases unless they are wrong. Removing a trigger can stop the skill from loading for users who rely on it.
- If the change affects the summary in the README **Skills** table, update the table.

## Validation

CI runs [skill-validator](https://github.com/agent-ecosystem/skill-validator) in strict mode on every skill changed in a pull request. Warnings fail the build. Run it locally before you finish:

```sh
./tests/validate-skills.sh                         # all skills
./tests/validate-skills.sh skills/scylladb-<topic>/ # one skill
```

It checks the frontmatter, the name/directory match, broken internal links, orphan files, unclosed code fences, keyword-stuffed descriptions, and size limits. If `skill-validator` is not installed, tell the user to install it (`go install github.com/agent-ecosystem/skill-validator/cmd/skill-validator@latest`). Do not skip validation.

Before you finish, check every paragraph of new or changed content: if a docs page already says it, replace it with a one-sentence summary and an inline link. Keep only what the docs leave out or what the agent would get wrong: version history of defaults, limits documented only in the config reference or source, differences from Cassandra or DynamoDB, and wrong/right examples.

The validator cannot check that the content is correct. Verify version numbers, defaults, and config keys against the ScyllaDB documentation or a running cluster.
