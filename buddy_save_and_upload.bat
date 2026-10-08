@echo off
cd /d "%~dp0"
echo.
echo === Saving and Uploading Your Work ===
echo.
git config user.email "BUDDY_EMAIL_HERE@gmail.com"
git config user.name "BUDDY_NAME_HERE"
git checkout JobsonBranch 2>nul || git checkout -b JobsonBranch
echo.
echo What did you work on today?
set /p MSG="Describe your changes: "
echo.
echo Saving your work...
git add .
git commit -m "%MSG%"
echo.
echo Uploading to GitHub...
git push -u origin JobsonBranch
echo.
echo =====================================================
echo  YOUR WORK IS SAVED! When you are both ready, run
echo  your merge_to_main.bat to combine it into main,
echo  then tell Evan to run their start_day.bat.
echo =====================================================
echo.
pause
