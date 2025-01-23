import Lake
open Lake DSL

def libcpp : String :=
  if System.Platform.isWindows then "libstdc++-6.dll"
  else if System.Platform.isOSX then "libc++.dylib"
  else "libstdc++.so.6"

package cvc5 {
  precompileModules := true
  moreGlobalServerArgs := #[s!"--load-dynlib={libcpp}"]
  extraDepTargets := #[`libcvc5]
  -- TODO: make this cross-platform, see https://github.com/ufmg-smite/lean-smt/issues/118
  moreLinkArgs := #["/usr/lib/x86_64-linux-gnu/libstdc++.so.6"]
}

@[default_target]
lean_lib cvc5 {
  moreLeanArgs := #[s!"--load-dynlib={libcpp}"]
}

@[test_driver]
lean_lib cvc5Test {
  globs := #[Glob.submodules `Cvc5Test]
}

def Lake.unzip (file : FilePath) (dir : FilePath) : LogIO PUnit := do
  IO.FS.createDirAll dir
  proc (quiet := true) {
    cmd := "unzip"
    args := #["-d", dir.toString, file.toString]
  }

def cvc5.path := "././.lake/packages/cvc5/cvc5-Linux-x86_64-static"

target libcvc5 pkg : Unit := do
  if !(← (pkg.lakeDir / "cvc5-Linux-x86_64-static").pathExists) then
    let zipPath := s!"{cvc5.path}.zip"
    unzip zipPath pkg.lakeDir
  return pure ()

def Lake.compileStaticLib'
  (libFile : FilePath) (oFiles : Array FilePath)
  (ar : FilePath := "ar")
: LogIO Unit := do
  createParentDirs libFile
  proc {
    cmd := ar.toString
    args := #["csqL", libFile.toString] ++ oFiles.map toString
  }

/-- Build a static library from object file jobs using the `ar` packaged with Lean. -/
def Lake.buildStaticLib'
  (libFile : FilePath) (oFileJobs : Array (BuildJob FilePath))
: SpawnM (BuildJob FilePath) :=
  buildFileAfterDepArray libFile oFileJobs fun oFiles => do
    compileStaticLib' libFile oFiles (← getLeanAr)

target ffiO pkg : FilePath := do
  let oFile := pkg.buildDir / "ffi" / "ffi.o"
  let srcJob ← inputBinFile <| pkg.dir / "ffi" / "ffi.cpp"
  let flags := #[
    "-std=c++17",
    "-I", (← getLeanIncludeDir).toString,
    "-I", (pkg.lakeDir / "cvc5-Linux-x86_64-static" / "include").toString,
    "-fPIC"
  ]
  buildO oFile srcJob flags

extern_lib libffi pkg := do
  let name := nameToStaticLib "ffi"
  let libFile := pkg.nativeLibDir / name
  let ffiO ← fetch (pkg.target ``ffiO)
  let staticLibPath (lib : String) :=
    pkg.lakeDir / "cvc5-Linux-x86_64-static" / "lib" / nameToStaticLib lib
  let libcadical := pure (staticLibPath "cadical")
  let libcvc5 := pure (staticLibPath "cvc5")
  let libcvc5parser := pure (staticLibPath "cvc5parser")
  let libgmp := pure (staticLibPath "gmp")
  let libgmpxx := pure (staticLibPath "gmpxx")
  let libpicpoly := pure (staticLibPath "picpoly")
  let libpicpolyxx := pure (staticLibPath "picpolyxx")
  let mut libs := #[ffiO, libcadical, libcvc5, libcvc5parser, libpicpoly, libpicpolyxx]
  if System.Platform.isOSX then libs := libs ++ #[libgmp, libgmpxx]
  buildStaticLib' libFile libs
