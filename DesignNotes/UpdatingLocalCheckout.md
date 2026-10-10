# Updating a checkout with copied branch files

Git can refuse a pull when a checkout has modified tracked files or untracked
copies of files that the incoming commits now track. The viewer/threat-analysis
merge tracks `LevelViewer.md`, both viewer scripts, `ThreatAndCost.md`, the cost
table, the analysis scripts and their UIDs, and the threat-analysis test scene.

Close Godot before updating so it does not regenerate UIDs during the operation.
From the repository directory in PowerShell, preserve tracked edits and
untracked files first:

```powershell
git stash push --include-untracked -m "Before merged viewer and gauntlet update"
git switch main
git pull --ff-only origin main
git status --short
git stash list
```

Run the commands in order; stop if one fails. The stash remains a backup after
the pull. Leave it in place while checking the updated game. Reapplying it
immediately can reintroduce older code or collide with newly tracked copies.
Any additional local work can be compared and restored selectively afterward.
Do not discard the stash until that work has been accounted for.

If `--ff-only` refuses because local `main` has its own commits, preserve them
and reconcile the branches instead of resetting or deleting files. The update
procedure does not discard local commits or ignored files.
