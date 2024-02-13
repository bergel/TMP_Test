function f()
    @async 1 + 2
end


const n = 1 + Threads.nthreads()