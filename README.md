# LLVM Windows DLL reproduction

Manual GitHub Actions workflow using standard `windows-2022` runners.
Compares pinned LLVM trunk and PR #221961 using MSVC and clang-cl.
Builds only LLVMSupport first to separate LLVM DLL annotation failures from
clang-tidy plugin failures. A successful Support build is not a plugin test.

Compiler versions, source SHA, configure arguments, verbose build logs,
CMake cache, and compilation database are uploaded even after failures.
No upstream source modifications are applied. Jobs time out after 45 minutes.
