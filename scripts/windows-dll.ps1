$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $false
New-Item -ItemType Directory -Force logs | Out-Null
$vswhere = "${env:ProgramFiles(x86)}/Microsoft Visual Studio/Installer/vswhere.exe"
$vs = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (!$vs) { throw "Visual Studio C++ tools not found" }
Import-Module "$vs/Common7/Tools/Microsoft.VisualStudio.DevShell.dll"
Enter-VsDevShell -VsInstallPath $vs -SkipAutomaticLocation -DevCmdArguments '-arch=x64 -host_arch=x64'
$compiler = $env:REPRO_COMPILER
$target = $env:REPRO_TARGET
if (!$target) { $target = "LLVMSupport" }
if ($compiler -eq 'clang-cl') {
  $env:PATH = "C:/Program Files/LLVM/bin;$env:PATH"
}
& $compiler /? 2>&1 | Select-Object -First 8 | Out-File logs/compiler.txt
& git -C llvm-project rev-parse HEAD | Out-File logs/revision.txt
& cmake --version | Out-File logs/tools.txt
& ninja --version | Out-File logs/tools.txt -Append
$argsCmake = @(
  '-S', 'llvm-project/llvm', '-B', 'build', '-G', 'Ninja',
  "-DCMAKE_C_COMPILER=$compiler", "-DCMAKE_CXX_COMPILER=$compiler",
  '-DCMAKE_BUILD_TYPE=Release', '-DCMAKE_EXPORT_COMPILE_COMMANDS=ON',
  '-DLLVM_ENABLE_PROJECTS=clang;clang-tools-extra', '-DLLVM_TARGETS_TO_BUILD=X86',
  '-DLLVM_ENABLE_ASSERTIONS=ON', '-DLLVM_INCLUDE_BENCHMARKS=OFF',
  '-DLLVM_BUILD_LLVM_DYLIB_VIS=ON', '-DLLVM_BUILD_LLVM_DYLIB=ON',
  '-DLLVM_LINK_LLVM_DYLIB=ON', '-DCLANG_LINK_CLANG_DYLIB=ON',
  '-DLLVM_ENABLE_PLUGINS=ON', '-DCLANG_PLUGIN_SUPPORT=ON'
)
$argsCmake | Out-File logs/configure-arguments.txt
& cmake @argsCmake 2>&1 | Tee-Object logs/configure.txt
if ($LASTEXITCODE -ne 0) { throw "CMake failed: $LASTEXITCODE" }
& ninja -C build -n $target 2>&1 | Tee-Object logs/dry-run.txt
if ($LASTEXITCODE -ne 0) { throw "Ninja dry run failed" }
& ninja -C build -j 3 -k 8 -v $target 2>&1 | Tee-Object logs/build.txt
if ($LASTEXITCODE -ne 0) { throw "${target} failed: $LASTEXITCODE" }
