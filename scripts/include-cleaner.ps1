$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $false
New-Item -ItemType Directory -Force logs | Out-Null
$root = $PWD.Path
$fixed = $env:APPLY_FIX -eq 'true'

$vswhere = "${env:ProgramFiles(x86)}/Microsoft Visual Studio/Installer/vswhere.exe"
$vs = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (!$vs) { throw "Visual Studio C++ tools not found" }
Import-Module "$vs/Common7/Tools/Microsoft.VisualStudio.DevShell.dll"
Enter-VsDevShell -VsInstallPath $vs -SkipAutomaticLocation -DevCmdArguments '-arch=x64 -host_arch=x64'

# The test is applied in both variants so the unpatched run shows it failing.
& git -C llvm-project apply --verbose "$root/patches/include-cleaner/test.patch"
if ($LASTEXITCODE -ne 0) { throw "Applying test.patch failed" }
if ($fixed) {
  & git -C llvm-project apply --verbose "$root/patches/include-cleaner/fix.patch"
  if ($LASTEXITCODE -ne 0) { throw "Applying fix.patch failed" }
}
& git -C llvm-project rev-parse HEAD | Out-File logs/revision.txt
& git -C llvm-project diff | Out-File logs/applied.diff
& cl 2>&1 | Select-Object -First 2 | Out-File logs/compiler.txt

$argsCmake = @(
  '-S', 'llvm-project/llvm', '-B', 'build', '-G', 'Ninja',
  '-DCMAKE_C_COMPILER=cl', '-DCMAKE_CXX_COMPILER=cl',
  '-DCMAKE_BUILD_TYPE=Release', '-DLLVM_ENABLE_ASSERTIONS=ON',
  '-DLLVM_ENABLE_PROJECTS=clang;clang-tools-extra', '-DLLVM_TARGETS_TO_BUILD=X86',
  '-DLLVM_INCLUDE_BENCHMARKS=OFF', '-DLLVM_INCLUDE_EXAMPLES=OFF',
  '-DLLVM_PARALLEL_LINK_JOBS=2'
)
& cmake @argsCmake 2>&1 | Tee-Object logs/configure.txt
if ($LASTEXITCODE -ne 0) { throw "CMake failed: $LASTEXITCODE" }
& ninja -C build -j 4 clang-tidy ClangTidyTests 2>&1 | Tee-Object logs/build.txt
if ($LASTEXITCODE -ne 0) { throw "Build failed: $LASTEXITCODE" }

$tests = Get-ChildItem build -Recurse -Filter ClangTidyTests.exe | Select-Object -First 1
if (!$tests) { throw "ClangTidyTests.exe not found" }
& $tests.FullName --gtest_filter='IncludeCleanerCheckTest.*' "--gtest_output=xml:$root/logs/gtest.xml" 2>&1 | Tee-Object logs/gtest.txt
$xml = [xml](Get-Content logs/gtest.xml)
$newTest = $xml.SelectSingleNode("//testcase[@name='SuppressUnusedIncludesForwardSlashPattern']")
if (!$newTest) { throw "SuppressUnusedIncludesForwardSlashPattern did not run" }
$newTestPassed = $null -eq $newTest.SelectSingleNode('failure')
$otherFailures = $xml.SelectNodes("//testcase[failure and @name!='SuppressUnusedIncludesForwardSlashPattern']").Count

# Reproducer from llvm/llvm-project#237692.
$repro = "$root/repro"
New-Item -ItemType Directory -Force $repro | Out-Null
Set-Content "$repro/.clang-tidy" @'
Checks: '-*,misc-include-cleaner'
CheckOptions:
  misc-include-cleaner.IgnoreHeaders: '.*/vendored\.h'
'@
Set-Content "$repro/vendored.h" "#pragma once"
Set-Content "$repro/main.cpp" "#include `"vendored.h`"`n`nint main() { return 0; }"
Push-Location $repro
$reproOutput = & "$root/build/bin/clang-tidy.exe" main.cpp -- 2>&1 | Out-String
$reproExit = $LASTEXITCODE
Pop-Location
# Tee-Object creates no file for empty output, which is the expected result
# with the fix, so always write the log explicitly.
Set-Content logs/repro.txt "exit code: $reproExit`n$reproOutput"
Get-Content logs/repro.txt
$warned = $reproOutput -match 'not used directly'

$summary = @"
## $(if ($fixed) { 'patched' } else { 'unpatched' })

| Check | Result | Expected |
| --- | --- | --- |
| SuppressUnusedIncludesForwardSlashPattern passed | $newTestPassed | $fixed |
| Other IncludeCleanerCheckTest failures | $otherFailures | 0 |
| Reproducer warns about vendored.h | $warned | $(-not $fixed) |
"@
$summary | Tee-Object logs/summary.md
if ($env:GITHUB_STEP_SUMMARY) { $summary | Out-File -Append $env:GITHUB_STEP_SUMMARY }

if ($newTestPassed -ne $fixed -or $warned -eq $fixed -or $otherFailures -ne 0) {
  throw "Results do not match expectations for this variant"
}
