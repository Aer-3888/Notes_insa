# Contributing to Campus INSA

Thanks for helping improve Campus INSA. Codeberg is the project's source of
truth for issues, pull requests, branches, and tags.

## Before you start

Read the [README](README.md), search the existing Codeberg issues, and avoid
opening a duplicate. Discuss a change before doing substantial work when its
scope is unclear.

### Creating and attributing issues

Create issues on [Codeberg](https://codeberg.org/AerLight/Notes_insa/issues).
Use one issue for one outcome and give it a concise, searchable title.

- For a bug, include the app version, device and platform, steps to reproduce,
  expected behaviour, actual behaviour, and any useful logs or screenshots.
- For a feature, explain the problem, the intended result, and clear acceptance
  criteria.
- Do not include credentials, student data, grades, or other personal data.
- The issue author is credited automatically. If someone else reports or
  contributes the work, acknowledge them in the issue or pull request.
- Ask to be assigned in a comment before starting work on an unassigned issue.
  Do not take over work already assigned to someone else without agreement.

## Branches and commits

Start from an up-to-date `main` branch and create one branch per issue:

```bash
git switch main
git pull origin main
git switch -c feature/12-documentation
```

Use lowercase, hyphen-separated branch names in this format:

```text
<type>/<issue-number>-<short-description>
```

Use `feature`, `fix`, `docs`, `refactor`, `test`, `chore`, or `ci` as the type.
For example, `fix/42-cas-timeout` and `docs/12-contributing-guide`.

Write focused commits using the Conventional Commits style:

```text
<type>(<scope>): <imperative summary>
```

Examples:

```text
feat(schedule): add month view filters
fix(auth): handle expired CAS session
docs(contributing): document Codeberg workflow
```

Keep the summary short, use the imperative mood, and do not end it with a
period. Add `Closes #12` to the pull request description when the change
resolves an issue.

## Pull requests and merges

Open pull requests on Codeberg with `main` as the target branch. A pull request
must cover one issue or coherent change, explain what changed, list validation
performed, and link the related issue.

Before requesting review:

- Rebase or merge the latest `main` when needed and resolve conflicts locally.
- Run the relevant checks, at minimum `flutter analyze --fatal-infos` and
  `flutter test` for Flutter changes.
- Keep generated files, credentials, signing keys, and personal data out of
  commits.

Do not push directly to `main` or force-push a shared branch. A maintainer must
approve the pull request and required GitHub Actions checks must pass before it
is merged. Use squash merge for a small, single-purpose pull request. Preserve
separate commits only when each one is meaningful on its own.

## Codeberg and GitHub

Codeberg is where development happens. Push branches, create issues, review
and merge pull requests, and create release tags there.

GitHub is a mirror used for GitHub Actions and published Android releases. The
mirror carries Codeberg branches and tags to GitHub, where workflows run. Do
not open or merge pull requests on GitHub and do not push branches or tags
there directly. Mirror updates can overwrite GitHub-only state, including tags.

After a Codeberg merge or tag push, wait for the mirror to update before
checking the corresponding GitHub Actions run or release.
