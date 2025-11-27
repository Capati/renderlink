@echo off
setlocal enabledelayedexpansion

:: Set default values
set RELEASE_MODE=false
set BUILD_TARGET=%1
set ERROR_OCCURRED=false
set RUN_AFTER_BUILD=false
set CLEAN_BUILD=false
set WEB_BUILD=false
set COMPILE_SHADERS=false
set ADDITIONAL_ARGS=

:: Check for arguments
set ARG_COUNTER=0
for %%i in (%*) do (
	if !ARG_COUNTER! equ 0 (
		rem Skip the first argument
	) else (
		if /i "%%i"=="release" (
			set RELEASE_MODE=true
		) else if /i "%%i"=="run" (
			set RUN_AFTER_BUILD=true
		) else if /i "%%i"=="clean" (
			set CLEAN_BUILD=true
		) else if /i "%%i"=="web" (
			set WEB_BUILD=true
		) else if /i "%%i"=="shaders" (
			set COMPILE_SHADERS=true
		) else (
			set "ADDITIONAL_ARGS=!ADDITIONAL_ARGS! %%i"
		)
	)
	set /a ARG_COUNTER+=1
)

:: Set mode string
if "%RELEASE_MODE%"=="true" (
	set MODE=RELEASE
) else (
	set MODE=DEBUG
)

:: Set build arguments based on target and mode
if "%WEB_BUILD%"=="true" (
	:: Web build arguments
	if "%RELEASE_MODE%"=="true" (
		set ARGS=-o:size -disable-assert -no-bounds-check
	) else (
		set ARGS=-debug
	)
) else (
	:: Native build arguments
	if "%RELEASE_MODE%"=="true" (
		set ARGS=-o:speed -disable-assert -no-bounds-check
	) else (
		set ARGS=-debug
	)
)

set OUT=.\build
set OUT_FLAG=-out:%OUT%

:: Check if a build target was provided
if "%BUILD_TARGET%"=="" (
	echo [BUILD] --- Error: Please provide a folder name to build
	echo [BUILD] --- Usage: build.bat folder_name [release] [run] [clean] [web] [shaders]
	echo [BUILD] --- Options:
	echo [BUILD] ---   release  : Build in release mode
	echo [BUILD] ---   run      : Run the executable after building
	echo [BUILD] ---   clean    : Clean build artifacts before building
	echo [BUILD] ---   web      : Build for WebAssembly
	echo [BUILD] ---   shaders  : Force recompile shader
	exit /b 1
)

for %%i in ("%BUILD_TARGET:\=" "%") do set TARGET_NAME=%%~ni

:: Clean build if requested
if "%CLEAN_BUILD%"=="true" (
	echo [BUILD] --- Cleaning artifacts...
	if exist "%OUT%\*.exe" del /F /Q %OUT%\*.exe
	if exist "%OUT%\*.pdb" del /F /Q %OUT%\*.pdb
	if exist "%OUT%\*.wasm" del /F /Q %OUT%\*.wasm
	if exist "%OUT%\gpu.js" del /F /Q %OUT%\gpu.js
	if exist "%OUT%\odin.js" del /F /Q %OUT%\odin.js
	if exist "%OUT%\.shader_hash" del /F /Q %OUT%\.shader_hash
)

set INITIAL_MEMORY_PAGES=2000
set MAX_MEMORY_PAGES=65536
set PAGE_SIZE=65536
set /a INITIAL_MEMORY_BYTES=%INITIAL_MEMORY_PAGES% * %PAGE_SIZE%
set /a MAX_MEMORY_BYTES=%MAX_MEMORY_PAGES% * %PAGE_SIZE%

:: Get and set ODIN_ROOT environment variable
for /f "delims=" %%i in ('odin.exe root') do set "ODIN_ROOT=%%i"
set "ODIN_ROOT=%ODIN_ROOT:"=%"
if "%ODIN_ROOT:~-1%"=="\" set "ODIN_ROOT=%ODIN_ROOT:~0,-1%"
set ODIN_ROOT=%ODIN_ROOT%

:: Handle web build
if "%WEB_BUILD%"=="true" (
	echo [BUILD] --- Building '%TARGET_NAME%' for web in %MODE% mode...
	call odin build .\%BUILD_TARGET% ^
		%OUT_FLAG%\app.wasm ^
		%ARGS% ^
		-target:js_wasm32 ^
		-extra-linker-flags:"--export-table --import-memory --initial-memory=!INITIAL_MEMORY_BYTES! --max-memory=!MAX_MEMORY_BYTES!"
	if errorlevel 1 (
		echo [BUILD] --- Error building '%TARGET_NAME%' for web
		set ERROR_OCCURRED=true
	) else (
		:: Build gpu.js
		pushd ..\wasm
		call tsc
		popd
		copy "..\wasm\odin.js" "%OUT%\odin.js" >nul
		copy "..\wasm\gpu.js" "%OUT%\gpu.js" >nul
		echo [BUILD] --- Web build completed successfully.
	)
) else (
	:: Build the target (regular build)
	echo [BUILD] --- Building '%TARGET_NAME%' in %MODE% mode...
	call odin build .\%BUILD_TARGET% %ARGS% %ADDITIONAL_ARGS% %OUT_FLAG%\%TARGET_NAME%.exe
	if errorlevel 1 (
		echo [BUILD] --- Error building '%TARGET_NAME%'
		set ERROR_OCCURRED=true
	)
)

:: Check if build was successful
if "%ERROR_OCCURRED%"=="true" (
	echo [BUILD] --- Build process failed.
	exit /b 1
)

echo [BUILD] --- Build process completed successfully.

:: Hash file to track shader modifications
set "HASH_FILE=%OUT%\.shader_hash"

:: Look for shader.slang in the build target directory
set "SHADER_FILE=%BUILD_TARGET%\%BUILD_TARGET%.slang"
if not exist "%SHADER_FILE%" (
	goto :skip_shaders
)

:: Calculate current hash (size + timestamp)
for %%f in ("%SHADER_FILE%") do set "CURRENT_HASH=%%~zf%%~tf"

:: Load stored hash
set "STORED_HASH="
if exist "%HASH_FILE%" (
	set /p STORED_HASH=<"%HASH_FILE%"
)

:: Determine if compilation is needed
set "NEEDS_COMPILE=false"

if "%COMPILE_SHADERS%"=="true" (
	set "NEEDS_COMPILE=true"
) else if "!STORED_HASH!"=="" (
	set "NEEDS_COMPILE=true"
) else if not "!CURRENT_HASH!"=="!STORED_HASH!" (
	set "NEEDS_COMPILE=true"
)

if "!NEEDS_COMPILE!"=="true" (
	:: Check if slangc is available
	where slangc.exe >nul 2>&1
	if %ERRORLEVEL% NEQ 0 (
		if "%VULKAN_SDK%" == "" (
			echo [SHADERS] --- Warning: slangc.exe not found in PATH and VULKAN_SDK not set. Skipping shader compilation.
			goto :skip_shaders
		)
		set "SLANGC=%VULKAN_SDK%\Bin\slangc.exe"
		if not exist "!SLANGC!" (
			echo [SHADERS] --- Warning: slangc.exe not found. Skipping shader compilation.
			goto :skip_shaders
		)
	) else (
		set "SLANGC=slangc.exe"
	)

	:: Create shader output directories
	if not exist "%OUT%\shaders\GLSL" mkdir "%OUT%\shaders\GLSL"
	if not exist "%OUT%\shaders\SPIRV" mkdir "%OUT%\shaders\SPIRV"
	if not exist "%OUT%\shaders\DXIL" mkdir "%OUT%\shaders\DXIL"
	if not exist "%OUT%\shaders\MSL" mkdir "%OUT%\shaders\MSL"
	if not exist "%OUT%\shaders\WGSL" mkdir "%OUT%\shaders\compiled\WGSL"

	echo [SHADERS] --- Compiling %BUILD_TARGET%.slang...

	set "SHADER_ERROR=false"

	:: Compile to GLSL (vertex)
	call "!SLANGC!" "%SHADER_FILE%" ^
		-entry vs_main ^
		-stage vertex ^
		-target glsl ^
		-profile glsl_450 ^
		-o "%OUT%\shaders\GLSL\%BUILD_TARGET%.vert"
	if errorlevel 1 (
		echo [SHADERS] --- Error: Failed to compile vertex shader to GLSL
		set "SHADER_ERROR=true"
	)

	:: Compile to GLSL (fragment)
	call "!SLANGC!" "%SHADER_FILE%" ^
		-entry fs_main ^
		-stage fragment ^
		-target glsl ^
		-profile glsl_450 ^
		-o "%OUT%\shaders\GLSL\%BUILD_TARGET%.frag"
	if errorlevel 1 (
		echo [SHADERS] --- Error: Failed to compile fragment shader to GLSL
		set "SHADER_ERROR=true"
	)

	rem :: Compile to SPIR-V (vertex)
	rem call "!SLANGC!" "%SHADER_FILE%" ^
	rem 	-entry vs_main ^
	rem 	-stage vertex ^
	rem 	-target spirv ^
	rem 	-o "%OUT%\shaders\SPIRV\%BUILD_TARGET%.vert.spv"

	rem if errorlevel 1 (
	rem 	echo [SHADERS] --- Error: Failed to compile vertex shader to SPIR-V
	rem 	set "SHADER_ERROR=true"
	rem )

	rem :: Compile to SPIR-V (fragment)
	rem call "!SLANGC!" "%SHADER_FILE%" ^
	rem 	-entry fs_main ^
	rem 	-stage fragment ^
	rem 	-target spirv ^
	rem 	-o "%OUT%\shaders\SPIRV\%BUILD_TARGET%.frag.spv"

	rem if errorlevel 1 (
	rem 	echo [SHADERS] --- Error: Failed to compile fragment shader to SPIR-V
	rem 	set "SHADER_ERROR=true"
	rem )

	rem :: Compile to DXIL (vertex)
	rem call "!SLANGC!" "%SHADER_FILE%" ^
	rem 	-entry vs_main ^
	rem 	-stage vertex ^
	rem 	-target dxil ^
	rem 	-profile sm_6_0 ^
	rem 	-o "%OUT%\shaders\DXIL\%BUILD_TARGET%.vert.dxil"

	rem if errorlevel 1 (
	rem 	echo [SHADERS] --- Error: Failed to compile vertex shader to DXIL
	rem 	set "SHADER_ERROR=true"
	rem )

	rem :: Compile to DXIL (fragment)
	rem call "!SLANGC!" "%SHADER_FILE%" ^
	rem 	-entry fs_main ^
	rem 	-stage fragment ^
	rem 	-target dxil ^
	rem 	-profile sm_6_0 ^
	rem 	-o "%OUT%\shaders\DXIL\%BUILD_TARGET%.frag.dxil"

	rem if errorlevel 1 (
	rem 	echo [SHADERS] --- Error: Failed to compile fragment shader to DXIL
	rem 	set "SHADER_ERROR=true"
	rem )

	rem :: Compile to MSL (vertex)
	rem call "!SLANGC!" "%SHADER_FILE%" ^
	rem 	-entry vs_main ^
	rem 	-stage vertex ^
	rem 	-target metal ^
	rem 	-fvk-b-shift 0 0 ^
	rem 	-o "%OUT%\shaders\MSL\%BUILD_TARGET%.vert.metal"

	rem if errorlevel 1 (
	rem 	echo [SHADERS] --- Error: Failed to compile vertex shader to MSL
	rem 	set "SHADER_ERROR=true"
	rem )

	rem :: Compile to MSL (fragment)
	rem call "!SLANGC!" "%SHADER_FILE%" ^
	rem 	-entry fs_main ^
	rem 	-stage fragment ^
	rem 	-target metal ^
	rem 	-fvk-b-shift 0 0 ^
	rem 	-o "%OUT%\shaders\MSL\%BUILD_TARGET%.frag.metal"

	rem if errorlevel 1 (
	rem 	echo [SHADERS] --- Error: Failed to compile fragment shader to MSL
	rem 	set "SHADER_ERROR=true"
	rem )

	:: Compile to WGSL (vertex)
	call "!SLANGC!" "%SHADER_FILE%" ^
		-entry vs_main ^
		-stage vertex ^
		-target wgsl ^
		-o "%OUT%\shaders\WGSL\%BUILD_TARGET%.vert.wgsl"
	if errorlevel 1 (
		echo [SHADERS] --- Error: Failed to compile vertex shader to WGSL
		set "SHADER_ERROR=true"
	)
	:: Compile to WGSL (fragment)
	call "!SLANGC!" "%SHADER_FILE%" ^
		-entry fs_main ^
		-stage fragment ^
		-target wgsl ^
		-o "%OUT%\shaders\WGSL\%BUILD_TARGET%.frag.wgsl"
	if errorlevel 1 (
		echo [SHADERS] --- Error: Failed to compile fragment shader to WGSL
		set "SHADER_ERROR=true"
	)

	if "!SHADER_ERROR!"=="true" (
		echo [SHADERS] --- Warning: Some shader compilations failed
	) else (
		:: Update hash file only on success
		echo !CURRENT_HASH!>"%HASH_FILE%"
	)
) else (
	echo [SHADERS] --- Shader is up-to-date
)

:skip_shaders

:: Run after build if requested
if "%RUN_AFTER_BUILD%"=="true" (
	if "%WEB_BUILD%"=="true" (
		echo [BUILD] --- Note: Cannot automatically run web builds. Please open web/index.html in a browser.
	) else (
		echo [BUILD] --- Running %TARGET_NAME%...
		pushd build
		%TARGET_NAME%.exe
		popd
	)
)

exit /b 0
