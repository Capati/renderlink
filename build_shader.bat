@echo off
setlocal enabledelayedexpansion

:: Check if slangc is available
where slangc.exe >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    if "%VULKAN_SDK%" == "" (
        echo slangc.exe not found in PATH and VULKAN_SDK not set. Skipping shader compilation.
        goto :skip_shaders
    )
    set "SLANGC=%VULKAN_SDK%\Bin\slangc.exe"
    if not exist "!SLANGC!" (
        echo slangc.exe not found. Skipping shader compilation.
        goto :skip_shaders
    )
) else (
    set "SLANGC=slangc.exe"
)

:: Check if shader file is provided as an argument
if "%~1"=="" (
    echo Usage: %~nx0 ^<relative_path_to_shader.slang^>
    goto :skip_shaders
)

:: Extract shader directory and name
set "SHADER_FILE=%~1"
set "SHADER_DIR=%~dp1"
set "SHADER_NAME=%~n1"

:: Create output directories in the shader's directory
for %%T in (GLSL SPIRV DXIL MSL WGSL) do (
    if not exist "%SHADER_DIR%\%%T" mkdir "%SHADER_DIR%\%%T"
)

set "SHADER_ERROR=false"

:: Compile to GLSL (vertex)
call "!SLANGC!" "%SHADER_FILE%" ^
    -entry vs_main ^
    -stage vertex ^
    -target glsl ^
    -profile glsl_450 ^
    -o "%SHADER_DIR%GLSL\%SHADER_NAME%.vert"
if errorlevel 1 (
    echo Failed to compile vertex shader to GLSL
    set "SHADER_ERROR=true"
)

:: Compile to GLSL (fragment)
call "!SLANGC!" "%SHADER_FILE%" ^
    -entry fs_main ^
    -stage fragment ^
    -target glsl ^
    -profile glsl_450 ^
    -o "%SHADER_DIR%GLSL\%SHADER_NAME%.frag"
if errorlevel 1 (
    echo Failed to compile fragment shader to GLSL
    set "SHADER_ERROR=true"
)

:: Compile to SPIR-V (vertex)
call "!SLANGC!" "%SHADER_FILE%" ^
    -entry vs_main ^
    -stage vertex ^
    -target spirv ^
    -o "%SHADER_DIR%SPIRV\%SHADER_NAME%.vert.spv"
if errorlevel 1 (
    echo Failed to compile vertex shader to SPIR-V
    set "SHADER_ERROR=true"
)

:: Compile to SPIR-V (fragment)
call "!SLANGC!" "%SHADER_FILE%" ^
    -entry fs_main ^
    -stage fragment ^
    -target spirv ^
    -o "%SHADER_DIR%SPIRV\%SHADER_NAME%.frag.spv"
if errorlevel 1 (
    echo Failed to compile fragment shader to SPIR-V
    set "SHADER_ERROR=true"
)

:: Compile to DXIL (vertex)
call "!SLANGC!" "%SHADER_FILE%" ^
    -entry vs_main ^
    -stage vertex ^
    -target dxil ^
    -profile sm_6_0 ^
    -o "%SHADER_DIR%DXIL\%SHADER_NAME%.vert.dxil"
if errorlevel 1 (
    echo Failed to compile vertex shader to DXIL
    set "SHADER_ERROR=true"
)

:: Compile to DXIL (fragment)
call "!SLANGC!" "%SHADER_FILE%" ^
    -entry fs_main ^
    -stage fragment ^
    -target dxil ^
    -profile sm_6_0 ^
    -o "%SHADER_DIR%DXIL\%SHADER_NAME%.frag.dxil"
if errorlevel 1 (
    echo Failed to compile fragment shader to DXIL
    set "SHADER_ERROR=true"
)

:: Compile to MSL (vertex)
call "!SLANGC!" "%SHADER_FILE%" ^
    -entry vs_main ^
    -stage vertex ^
    -target metal ^
    -fvk-b-shift 0 0 ^
    -o "%SHADER_DIR%MSL\%SHADER_NAME%.vert.metal"
if errorlevel 1 (
    echo Failed to compile vertex shader to MSL
    set "SHADER_ERROR=true"
)

:: Compile to MSL (fragment)
call "!SLANGC!" "%SHADER_FILE%" ^
    -entry fs_main ^
    -stage fragment ^
    -target metal ^
    -fvk-b-shift 0 0 ^
    -o "%SHADER_DIR%MSL\%SHADER_NAME%.frag.metal"
if errorlevel 1 (
    echo Failed to compile fragment shader to MSL
    set "SHADER_ERROR=true"
)

:: Compile to WGSL (vertex)
call "!SLANGC!" "%SHADER_FILE%" ^
    -entry vs_main ^
    -stage vertex ^
    -target wgsl ^
    -o "%SHADER_DIR%WGSL\%SHADER_NAME%.vert.wgsl"
if errorlevel 1 (
    echo Failed to compile vertex shader to WGSL
    set "SHADER_ERROR=true"
)

:: Compile to WGSL (fragment)
call "!SLANGC!" "%SHADER_FILE%" ^
    -entry fs_main ^
    -stage fragment ^
    -target wgsl ^
    -o "%SHADER_DIR%WGSL\%SHADER_NAME%.frag.wgsl"
if errorlevel 1 (
    echo Failed to compile fragment shader to WGSL
    set "SHADER_ERROR=true"
)

if "!SHADER_ERROR!"=="true" (
    echo Some shader compilations failed
)

:skip_shaders
endlocal
