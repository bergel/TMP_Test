#! /usr/bin/env julia

# On the primary process, activate and build the project,
# optionally updating the package Manifest.toml prior to build.
import Pkg

pkg = isempty(ARGS) ? "RAICode" : ARGS[1]

Pkg.activate(@__DIR__)

const n = Threads.nthreads()

function foo(x)
    println("hello")
end

function run_pkg_build(pkg)
    try
        @async 1 + 2
        x = false
        true || x
        println(Threads.nthreads())

	@info `$(Base.julia_cmd()) -e "using Pkg; Pkg.build(\"$(pkg)\")"`
        run(`$(Base.julia_cmd()) -e "using Pkg; Pkg.build(\"$(pkg)\")"`)
        return 0
    catch e
        if isa(e, Base.ProcessFailedException)
            return e.procs[1].exitcode
        else
            rethrow()
        end
    end
end

tries = 2
exit_code = 0
for i = 1:tries
    global exit_code = run_pkg_build(pkg)
    if exit_code == 0
        break
    elseif exit_code == 139
        @error "Pkg.build resulted in segfault..."
        continue
    else
        Sys.exit(exit_code)
    end
end
if exit_code != 0
    Sys.exit(exit_code)
end

# Defaults for all test jobs.
# Individual test jobs should override these values by setting ENV variables in `Makefile`.
const DEFAULT_DASSERT_LEVEL = "2"
# Use a worker to get retry-ability and higher resilience to segfaults.
const DEFAULT_TEST_WORKERS = "1"
const DEFAULT_TEST_WORKER_THREADS = "2,2"
# We do not want any of our tests to take longer than this,
# so we automatically cancel and mark as failed any tests that take longer.
# Note: some old testitems set themselves a longer `timeout`, but that is an anti-pattern.
# We allow this to be overridden in `Makefile` so the recovery mode jobs can customise this.
const DEFAULT_TESTITEM_TIMEOUT = string(30*60)  # 30 mins

if !haskey(ENV, "DASSERT_LEVEL")
    ENV["DASSERT_LEVEL"] = DEFAULT_DASSERT_LEVEL
end
println("Running tests with DASSERT_LEVEL=$(get(ENV, "DASSERT_LEVEL", "<not set>"))")
if !haskey(ENV, "DASSERT_LEVEL") || parse(Int, ENV["DASSERT_LEVEL"]) < parse(Int, DEFAULT_DASSERT_LEVEL)
    @warn("Running tests with DASSERT_LEVEL < $DEFAULT_DASSERT_LEVEL is not recommended. Set higher level if possible, e.g. `DASSERT_LEVEL=$DEFAULT_DASSERT_LEVEL`")
end

nworkers = parse(Int, get(ENV, "RAI_TEST_WORKERS", DEFAULT_TEST_WORKERS))
println("Running tests with $nworkers workers")
if nworkers == 0
    @warn("Running tests without workers is not recommended. Set workers if possible, e.g. `RAI_TEST_WORKERS=$DEFAULT_TEST_WORKERS`")
end

nthreads = get(ENV, "RAI_TEST_WORKER_THREADS", DEFAULT_TEST_WORKER_THREADS)
println("Running tests with $nthreads threads per workers")
if !in(',', nthreads)
    @warn("Running tests without interactive threads is not recommended. Set interactive threads if possible, e.g. `RAI_TEST_WORKER_THREADS=$nthreads,2`")
end

testitem_timeout = parse(Int, get(ENV, "RAI_TESTITEM_TIMEOUT", DEFAULT_TESTITEM_TIMEOUT))
println("Running tests with default timeout of $testitem_timeout seconds")
if testitem_timeout > parse(Int, DEFAULT_TESTITEM_TIMEOUT)
    @warn("Running tests without a timeout greater than $DEFAULT_TESTITEM_TIMEOUT seconds is not recommended.")
end

withenv(
    "RETESTITEMS_NWORKERS" => nworkers,
    "RETESTITEMS_NWORKER_THREADS" => nthreads,
    "RETESTITEMS_TESTITEM_TIMEOUT" => testitem_timeout,
    # Replace workers if memory usage exceeds 90%.
    # Disabled on MacOS where memory consumption is not being reported correctly:
    # https://github.com/JuliaTesting/ReTestItems.jl/issues/113
    "RETESTITEMS_MEMORY_THRESHOLD" => Sys.isapple() ? 1.0 : 0.9,
    "RETESTITEMS_RETRIES" => 1, # retry test failures once
    "RETESTITEMS_REPORT" => true,
    # error if `runtests` points to non-existent files, as that might mean tests are accidentally
    # not being run e.g. typo in file name or files got moved without updating `runtests`
    "RETESTITEMS_VALIDATE_PATHS" => true,
) do
    @showtime Pkg.test(pkg; coverage=true)
end

# Process the line coverage information that running the preceding tests generated
# and write the crunched line coverage data to disk.
using Coverage
using Logging
dir = pkg == "RAICode" ? "src" : "packages/$pkg"
Logging.with_logger(Logging.ConsoleLogger(stderr, Logging.Warn)) do
    try
        coverage = Coverage.process_folder(dir)
        LCOV.writefile("lcov.info", coverage)
    catch e
        if e isa BoundsError
            # we've seen some cases of a mysterious BoundsError when processing coverage
            # try to show the coverage file to see what's going on and don't
            # fail the build
            @warn "Coverage processing failed with BoundsError, trying to show bad coverage file"
            for (root, _, files) in walkdir(dir)
                for file in files
                    endswith(file, ".cov") || continue
                    for (i, line) in enumerate(eachline(joinpath(root, file)))
                        if length(line) < 9
                            @warn "line $i in $file is too short: $(repr(line))"
                            break
                        end
                    end
                end
            end
        end
    end
end
