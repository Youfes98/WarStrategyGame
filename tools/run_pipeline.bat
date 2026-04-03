@echo off
echo === War Strategy Game — Data Pipeline ===
echo.

:: Find Python — try common locations
set PYTHON=
where python >nul 2>&1 && set PYTHON=python
if "%PYTHON%"=="" where python3 >nul 2>&1 && set PYTHON=python3
if "%PYTHON%"=="" (
    for %%P in (
        "%LOCALAPPDATA%\Python\pythoncore-3.14-64\python.exe"
        "%LOCALAPPDATA%\Programs\Python\Python314\python.exe"
        "%LOCALAPPDATA%\Programs\Python\Python313\python.exe"
        "%LOCALAPPDATA%\Programs\Python\Python312\python.exe"
        "%LOCALAPPDATA%\Programs\Python\Python311\python.exe"
        "C:\Python314\python.exe"
        "C:\Python312\python.exe"
    ) do (
        if exist %%P set PYTHON=%%P
    )
)
if "%PYTHON%"=="" (
    echo ERROR: Python not found. Install from https://python.org
    pause & exit /b 1
)
echo Using Python: %PYTHON%
echo.

echo Step 1: Fetching country data...
%PYTHON% fetch_country_data.py
if errorlevel 1 goto error

echo.
echo Step 2: Building map polygons + provinces.png...
%PYTHON% geojson_to_godot.py
if errorlevel 1 goto error

echo.
echo === Pipeline complete! Open the project in Godot 4. ===
pause
exit /b 0

:error
echo.
echo ERROR: Pipeline failed. Check output above.
pause
exit /b 1
