# LLVM Windows DLL reproduction

Manual GitHub Actions workflow using standard `windows-2022` runners.
Compares pinned LLVM trunk and PR #221961 using MSVC and clang-cl.
Builds only LLVMSupport first to separate LLVM DLL annotation failures from
clang-tidy plugin failures. A successful Support build is not a plugin test.

Compiler versions, source SHA, configure arguments, verbose build logs,
CMake cache, and compilation database are uploaded even after failures.
No upstream source modifications are applied. Jobs time out after 45 minutes.

## Results (2026-09-09)

Pinned sources:
- trunk: `f796b25647e378a02482ef383f2db45804d8fb72`
- PR #221961: `50b42f202c13ad44b29d3074e051d6c76498e087`

[Support matrix](https://github.com/zeyi2/llvm-testing/actions/runs/34333356395):
- MSVC 19.44.35228.0: LLVMSupport passed on both sources.
- clang-cl 20.1.8: both sources fail at APInt.h:153:
  `attribute 'dllexport' cannot be applied to a deleted function`.
  The deleted three-argument constructor is still annotated with LLVM_ABI.

[MSVC Core build](https://github.com/zeyi2/llvm-testing/actions/runs/34333791439):
- Both sources fail linking llvm-min-tblgen.exe with LNK2019/LNK1120:
  SubtargetFeatures(StringRef), referenced by a default constructor closure
  in TargetFeaturesEmitter.cpp.obj.
- This prevents reaching the full Core build. It does not reproduce the
  separately reported MSVC duplicate DLL-interface member annotation error.

All five relevant CMake switches were ON in the saved cache:
LLVM_BUILD_LLVM_DYLIB_VIS, LLVM_LINK_LLVM_DYLIB, CLANG_LINK_CLANG_DYLIB,
LLVM_ENABLE_PLUGINS, and CLANG_PLUGIN_SUPPORT.
No plugin loading tests have run on Windows yet.

To reproduce another target, dispatch the workflow with `target` set to the
Ninja target and `compilers` set to e.g. `["cl"]` or `["clang-cl"]`.
