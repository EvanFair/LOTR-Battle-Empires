# LOTR Battle Empires — Git Workflow Cheat Sheet

Each person works on their **own branch** and merges into `main` when ready:

| Person | Branch         | Scripts                    |
|--------|----------------|----------------------------|
| Evan   | `evan-branch`  | `evan_*.bat`               |
| Jobson | `JobsonBranch` | `buddy_*.bat`              |

## Daily routine (double-click the scripts)

1. **`*_start_day.bat`** — pulls the latest `main` and switches you to your branch with it merged in.
2. Code.
3. **`*_save_and_upload.bat`** — asks what you worked on, commits, and pushes your branch.
4. **`*_merge_to_main.bat`** — when you're both ready, merges your branch into `main` and pushes it. The other person then runs their `start_day` script to get the changes.

> **Golden rule:** always run `start_day` before you start coding. It prevents most merge conflicts.

## Doing it by hand

```bash
git checkout main && git pull origin main
git checkout evan-branch && git merge main
# ...code...
git add . && git commit -m "describe what you did"
git push origin evan-branch
```

## If Git asks for a password

GitHub doesn't accept your normal password on the command line. Easiest fix:

```bash
gh auth login
```

Pick `GitHub.com` → `HTTPS` → log in with web browser. Or create a Personal Access Token (GitHub → Settings → Developer settings → Personal access tokens) with `repo` access and paste it when asked for a password.

## Merge conflicts

If you both edit the same lines, Git stops and marks the conflict.

1. Open the file in VS Code.
2. Pick **Accept Current**, **Accept Incoming**, or **Accept Both**.
3. Save, then `git add .`, `git commit -m "resolved merge conflict"`, and push.

## Big game files

Large binary assets (textures, models, audio over ~50 MB) bloat the repo. If you start adding them, set up [Git LFS](https://git-lfs.com/) first: `git lfs install` then `git lfs track "*.psd"` (etc.).
