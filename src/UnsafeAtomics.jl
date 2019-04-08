
# This file is inspired from the work in base/atomics.jl, which is part of Julia. License is MIT: http://julialang.org/license

module UnsafeAtomics

using Core.Intrinsics: llvmcall

import Base: unsafe_convert
import Base.Threads: AtomicTypes, FloatTypes, IntTypes, llvmtypes, inttype,
    opnames, atomictypes, Atomic, atomic_cas!, @threads

export
    unsafe_atomic_cas!,
    unsafe_atomic_xchg!,
    unsafe_atomic_add!, unsafe_atomic_sub!,
    unsafe_atomic_and!, unsafe_atomic_nand!, unsafe_atomic_or!, unsafe_atomic_xor!,
    unsafe_atomic_max!, unsafe_atomic_min!

function unsafe_atomic_cas! end

function unsafe_atomic_xchg! end

function unsafe_atomic_add! end

function unsafe_atomic_sub! end

function unsafe_atomic_and! end

function unsafe_atomic_nand! end

function unsafe_atomic_or! end

function unsafe_atomic_xor! end

function unsafe_atomic_max! end

function unsafe_atomic_min! end


# All atomic operations have acquire and/or release semantics, depending on
# whether the load or store values. Most of the time, this is what one wants
# anyway, and it's only moderately expensive on most hardware.
for typ in atomictypes
    lt = llvmtypes[typ]
    ilt = llvmtypes[inttype(typ)]
    rt = VersionNumber(Base.libllvm_version) >= v"3.6" ? "$lt, $lt*" : "$lt*"
    irt = VersionNumber(Base.libllvm_version) >= v"3.6" ? "$ilt, $ilt*" : "$ilt*"
    # Note: unsafe_atomic_cas! succeeded (i.e. it stored "new") if and only if the result is "cmp"
    if VersionNumber(Base.libllvm_version) >= v"3.5"
        if typ <: Integer
            @eval unsafe_atomic_cas!(x::Ptr{$typ}, cmp::$typ, new::$typ) =
                llvmcall($"""
                         %rs = cmpxchg $lt* %0, $lt %1, $lt %2 acq_rel acquire
                         %rv = extractvalue { $lt, i1 } %rs, 0
                         ret $lt %rv
                         """, $typ, Tuple{Ptr{$typ},$typ,$typ},
                         x, cmp, new)
        else
            @eval unsafe_atomic_cas!(x::Ptr{$typ}, cmp::$typ, new::$typ) =
                llvmcall($"""
                         %iptr = bitcast $lt* %0 to $ilt*
                         %icmp = bitcast $lt %1 to $ilt
                         %inew = bitcast $lt %2 to $ilt
                         %irs = cmpxchg $ilt* %iptr, $ilt %icmp, $ilt %inew acq_rel acquire
                         %irv = extractvalue { $ilt, i1 } %irs, 0
                         %rv = bitcast $ilt %irv to $lt
                         ret $lt %rv
                         """, $typ, Tuple{Ptr{$typ},$typ,$typ},
                         x, cmp, new)
        end
    else
        if typ <: Integer
            @eval unsafe_atomic_cas!(x::Ptr{$typ}, cmp::$typ, new::$typ) =
                llvmcall($"""
                         %rv = cmpxchg $lt* %0, $lt %1, $lt %2 acq_rel
                         ret $lt %rv
                         """, $typ, Tuple{Ptr{$typ},$typ,$typ},
                         x, cmp, new)
        else
            @eval unsafe_atomic_cas!(x::Ptr{$typ}, cmp::$typ, new::$typ) =
                llvmcall($"""
                         %iptr = bitcast $lt* %0 to $ilt*
                         %icmp = bitcast $lt %1 to $ilt
                         %inew = bitcast $lt %2 to $ilt
                         %irv = cmpxchg $ilt* %iptr, $ilt %icmp, $ilt %inew acq_rel
                         %rv = bitcast $ilt %irv to $lt
                         ret $lt %rv
                         """, $typ, Tuple{Ptr{$typ},$typ,$typ},
                         x, cmp, new)
        end
    end
    for rmwop in [:xchg, :add, :sub, :and, :nand, :or, :xor, :max, :min]
        rmw = string(rmwop)
        fn = Symbol("unsafe_atomic_", rmw, "!")
        if (rmw == "max" || rmw == "min") && typ <: Unsigned
            # LLVM distinguishes signedness in the operation, not the integer type.
            rmw = "u" * rmw
        end
        if typ <: Integer
            @eval $fn(x::Ptr{$typ}, v::$typ) =
                llvmcall($"""
                         %rv = atomicrmw $rmw $lt* %0, $lt %1 acq_rel
                         ret $lt %rv
                         """, $typ, Tuple{Ptr{$typ}, $typ},
                         x, v)
        else
            rmwop == :xchg || continue
            @eval $fn(x::Ptr{$typ}, v::$typ) =
                llvmcall($"""
                         %iptr = bitcast $lt* %0 to $ilt*
                         %ival = bitcast $lt %1 to $ilt
                         %irv = atomicrmw $rmw $ilt* %iptr, $ilt %ival acq_rel
                         %rv = bitcast $ilt %irv to $lt
                         ret $lt %rv
                         """, $typ, Tuple{Ptr{$typ}, $typ},
                         x, v)
        end
    end
end

#unsafe_atomic_cas!{T<:AtomicTypes}(x::T, cmp::T, new::T) = unsafe_atomic_cas!(convert(Ptr{T}, pointer_from_objref(x)), cmp, new)
unsafe_atomic_cas!{T<:AtomicTypes}(x::Array{T}, idx::Integer, cmp::T, new::T) = unsafe_atomic_cas!(pointer(x, idx), cmp, new)

for op in [:xchg, :add, :sub, :and, :nand, :or, :xor, :max, :min]
    fn = Symbol("unsafe_atomic_", string(op), "!")
    #@eval $fn{T<:AtomicTypes}(x::T, val::T) = $fn(convert(Ptr{T}, pointer_from_objref(x)), val)
    @eval $fn{T<:AtomicTypes}(x::Array{T}, idx::Integer, val::T) = $fn(pointer(x, idx), val)
end

#=
for op in [:+, :-, :max, :min]
    opname = get(opnames, op, op)
    @eval function $(Symbol("unsafe_atomic_", opname, "!")){T<:FloatTypes}(var::T, val::T)
        IT = inttype(T)
        old = var
        while true
            new = $op(old, val)
            cmp = old
            old = unsafe_atomic_cas!(var, cmp, new)
            reinterpret(IT, old) == reinterpret(IT, cmp) && return new
            # Temporary solution before we have gc transition support in codegen.
            ccall(:jl_gc_safepoint, Void, ())
        end
    end
end
=#

end
