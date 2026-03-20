@echo off
call "C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\VC\Auxiliary\Build\vcvarsall.bat" x64
set CMAKE_GENERATOR=Ninja
"C:\flutter_sdk\flutter\bin\flutter.bat" build windows --release
