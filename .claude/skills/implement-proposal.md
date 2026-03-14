# Implement Proposal

Implements an approved proposal from the nanoclaw-config repo.

## Steps

1. Read the proposal file specified by the user
2. Confirm you understand the change being requested
3. Check out a new git branch: `git checkout -b improvement/YYYY-MM-DD-description`
4. Make only the change described — nothing else
5. Show a diff: `git diff`
6. Stage and commit: `git add -p` then `git commit -m "feat: description"`
7. Push the branch: `git push origin improvement/YYYY-MM-DD-description`
8. Report back with the branch name and a plain-english summary of what changed

Do NOT merge to main. Do NOT make changes beyond the proposal scope.
