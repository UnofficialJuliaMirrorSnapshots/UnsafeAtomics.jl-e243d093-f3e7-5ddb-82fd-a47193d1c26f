# This file is inspired from test/threads.jl which is part of Julia. License is MIT: http://julialang.org/license

using Base.Test
using Base.Threads
using UnsafeAtomics

# parallel loop with parallel atomic addition
function threaded_loop(a, r, x)
    @threads for i in r
        a[i] = 1 + unsafe_atomic_add!(x, 1, 1)
    end
end

function test_threaded_loop_and_atomic_add()
    x = zeros(Int, 1)
    a = zeros(Int,10000)
    threaded_loop(a,1:10000,x)
    found = zeros(Bool,10000)
    was_inorder = true
    for i=1:length(a)
        was_inorder &= a[i]==i
        found[a[i]] = true
    end
    @test x[1] == 10000
    # Next test checks that all loop iterations ran,
    # and were unique (via pigeon-hole principle).
    @test findfirst(found,false) == 0
    if was_inorder
        println(STDERR, "Warning: threaded loop executed in order")
    end
end

test_threaded_loop_and_atomic_add()

# Helper for test_threaded_atomic_minmax that verifies sequential consistency.
function check_minmax_consistency{T}(old::Array{T,1}, m::T, start::T, o::Base.Ordering)
    for v in old
        if v != start
            # Check that atomic op that installed v reported consistent old value.
            @test Base.lt(o, old[v-m+1], v)
        end
    end
end

function test_threaded_atomic_minmax{T}(m::T,n::T)
    mid = m + (n-m)>>1
    x = [mid]
    y = [mid]
    oldx = Array{T}(n-m+1)
    oldy = Array{T}(n-m+1)
    @threads for i = m:n
        oldx[i-m+1] = unsafe_atomic_min!(x, 1, T(i))
        oldy[i-m+1] = unsafe_atomic_max!(y, 1, T(i))
    end
    @test x[1] == m
    @test y[1] == n
    check_minmax_consistency(oldy,m,mid,Base.Forward)
    check_minmax_consistency(oldx,m,mid,Base.Reverse)
end

# The ranges below verify that the correct signed/unsigned comparison is used.
test_threaded_atomic_minmax(Int16(-5000),Int16(5000))
test_threaded_atomic_minmax(UInt16(27000),UInt16(37000))

# Test atomic_cas! and atomic_xchg!
function test_atomic_cas!{T}(var::Array{T}, range::StepRange{Int,Int})
    for i in range
        while true
            old = unsafe_atomic_cas!(var, 1, T(i-1), T(i))
            old == T(i-1) && break
            # Temporary solution before we have gc transition support in codegen.
            ccall(:jl_gc_safepoint, Void, ())
        end
    end
end
for T in (Int32, Int64, Float32, Float64)
    var = zeros(T, 1)
    nloops = 1000
    di = nthreads()
    @threads for i in 1:di
        test_atomic_cas!(var, i:di:nloops)
    end
    @test var[1] === T(nloops)
end

function test_atomic_xchg!{T}(var::Array{T}, i::Int, accum::Array{Int})
    old = unsafe_atomic_xchg!(var, 1, T(i))
    unsafe_atomic_add!(accum, 1, Int(old))
end

for T in (Int32, Int64) #(Int32, Int64, Float32, Float64)
    accum = zeros(Int, 1)
    var = zeros(T, 1)
    nloops = 1000
    @threads for i in 1:nloops
        test_atomic_xchg!(var, i, accum)
    end
    @test accum[1] + Int(var[1]) === sum(0:nloops)
end

function test_atomic_float{T}(varadd::Array{T}, varmax::Array{T}, varmin::Array{T}, i::Int)
    unsafe_atomic_add!(varadd, 1, T(i))
    unsafe_atomic_max!(varmax, 1, T(i))
    unsafe_atomic_min!(varmin, 1, T(i))
end
for T in (Int32, Int64) #(Int32, Int64, Float32, Float64)
    varadd = zeros(T, 1)
    varmax = zeros(T, 1)
    varmin = zeros(T, 1)
    nloops = 1000
    @threads for i in 1:nloops
        test_atomic_float(varadd, varmax, varmin, i)
    end
    @test varadd[1] === T(sum(1:nloops))
    @test varmax[1] === T(maximum(1:nloops))
    @test varmin[1] === T(0)
end
