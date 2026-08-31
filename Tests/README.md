# Fitty C++ solver tests

Plain C++ (no XCTest, no Apple frameworks). Run on Linux or macOS with g++.

From the repo root:

```
g++ -std=c++17 -O2 -IFitty/Physics \
    Fitty/Physics/ClothSolver.cpp \
    Tests/ClothSolverTests.cpp \
    -o /tmp/cloth_tests
/tmp/cloth_tests
```

Last run (Debian, g++ 14.2, 2026-08-31 NZST): **51 passed, 0 failed**.

These tests are **not** in the iOS target.
