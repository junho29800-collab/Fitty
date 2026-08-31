# Fitty C++ solver tests

Plain C++ (no XCTest, no Apple frameworks). Run on Linux or macOS with g++.

```
g++ -std=c++17 -O2 -IFitty/Physics \
    Fitty/Physics/ClothSolver.cpp \
    Tests/ClothSolverTests.cpp \
    -o /tmp/cloth_tests
/tmp/cloth_tests
```

From the repo root:

```
g++ -std=c++17 -O2 -IFitty/Physics Fitty/Physics/ClothSolver.cpp Tests/ClothSolverTests.cpp -o /tmp/cloth_tests && /tmp/cloth_tests
```

Expected: **20 passed, 0 failed**.
