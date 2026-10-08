@echo off
cd /d "%~dp0"
echo.
echo === Merging Your Work Into Main ===
echo.
git config user.email "evan.fair@gmail.com"
git config user.name "Evan"
echo.
echo Step 1: Getting the latest main...
git checkout main
git pull origin main
echo.
echo Step 2: Merging your branch into main...
git merge evan-branch
if errorlevel 1 (
  echo.
  echo MERGE CONFLICT! Fix the conflicted files in VS Code, then run:
  echo   git add .  ^&^&  git commit -m "resolved merge conflict"  ^&^&  git push origin main
  echo.
  pause
  exit /b 1
)
echo.
echo Step 3: Uploading the updated main to GitHub...
git push origin main
echo.
echo =====================================================
echo  DONE! Main is now updated with your latest work.
echo  Tell Jobson to run their start_day.bat to get
echo  your changes on their computer.
echo =====================================================
echo.
pause
