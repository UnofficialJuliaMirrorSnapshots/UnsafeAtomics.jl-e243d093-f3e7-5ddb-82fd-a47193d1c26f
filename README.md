# UnsafeAtomics

[![Build Status](https://travis-ci.org/jpfairbanks/UnsafeAtomics.jl.svg?branch=master)](https://travis-ci.org/jpfairbanks/UnsafeAtomics.jl)

[![Coverage Status](https://coveralls.io/repos/jpfairbanks/UnsafeAtomics.jl/badge.svg?branch=master&service=github)](https://coveralls.io/github/jpfairbanks/UnsafeAtomics.jl?branch=master)

[![codecov.io](http://codecov.io/github/jpfairbanks/UnsafeAtomics.jl/coverage.svg?branch=master)](http://codecov.io/github/jpfairbanks/UnsafeAtomics.jl?branch=master)

This package implements atomic operations for the Julia AtomicTypes(
`Float16,Float32,Float64,Int128,Int16,Int32,Int64,Int8,UInt128,UInt16,UInt32,UInt64,UInt8`)
without requiring to wrap them in a `Atomic` type. This allows atomic
operations to be operated on a `Vector` without the extra indirection of a
`Vector{Atomic}`.

`UnsafeAtomics` currently supports only operations on values that are in an `Array{T:<AtomicTypes}`.

## Getting Started

```bash
export JULIA_NUM_THREADS=8
julia -e 'Pkg.clone("git@github.com:jpfairbanks/UnsafeAtomics.jl.git")'
```

## Usage

```julia
n = 10
a = ones(Int64, n)
# this will ensure correctness
@threads for i in 1:1000n
       unsafe_atomic_add!(a, mod(div(i,n), n)+1, 1)
end
b = ones(Int64, n)
# this will give nondeterministic output
@threads for i in 1:1000n
       b[mod(div(i,n), n)+1] += 1
end
# if concurrently executed JULIA_NUM_THREADS > 1
# a != b
```
