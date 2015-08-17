module ColorVectorSpace

using ColorTypes, FixedPointNumbers, Compat, Base.Cartesian

import Base: ==, +, -, *, /, .+, .-, .*, ./, ^, <
import Base: abs, abs2, clamp, convert, copy, div, eps, isfinite, isinf,
    isnan, isless, length, one, promote_array_type, promote_rule, zero,
    trunc, floor, round, ceil, bswap,
    mod, rem, atan2, hypot

typealias TransparentRGB{C<:AbstractRGB,T}   Transparent{C,T,4}
typealias TransparentGray{C<:AbstractGray,T} Transparent{C,T,2}
typealias TransparentRGBFloat{C<:AbstractRGB,T<:FloatingPoint} Transparent{C,T,4}
typealias TransparentGrayFloat{C<:AbstractGray,T<:FloatingPoint} Transparent{C,T,2}
typealias TransparentRGBUfixed{C<:AbstractRGB,T<:FloatingPoint} Transparent{C,T,4}
typealias TransparentGrayUfixed{C<:AbstractGray,T<:FloatingPoint} Transparent{C,T,2}

typealias MathTypes Union(AbstractRGB,TransparentRGB,AbstractGray,TransparentRGB)

export sumsq

## Generic algorithms
for f in (:trunc, :floor, :round, :ceil, :eps, :bswap)
    @eval $f{T}(g::Gray{T}) = Gray{T}($f(gray(g)))
    @eval @vectorize_1arg Gray $f
end
eps{T}(::Type{Gray{T}}) = Gray(eps(T))
@vectorize_1arg AbstractGray isfinite
@vectorize_1arg AbstractGray isinf
@vectorize_1arg AbstractGray isnan
@vectorize_1arg AbstractGray abs
@vectorize_1arg AbstractGray abs2
for f in (:trunc, :floor, :round, :ceil)
    @eval $f{T<:Integer}(::Type{T}, g::Gray) = Gray{T}($f(T, gray(g)))
    @eval $f{T<:Integer,G<:Gray,Ti}(::Type{T}, A::SparseMatrixCSC{G,Ti}) = error("not defined") # fix ambiguity warning
    # Resolve ambiguities with Compat versions
    if VERSION < v"0.3.99"
        @eval $f{T<:Integer,G<:Gray}(::Type{T}, A::AbstractArray{G,1}) = [($f)(A[i]) for i = 1:length(A)]
        @eval $f{T<:Integer,G<:Gray}(::Type{T}, A::AbstractArray{G,2}) = [($f)(A[i,j]) for i = 1:size(A,1), j = 1:size(A,2)]
    end
    # The next resolve ambiguities with floatfuncs.jl definitions
    if VERSION < v"0.4.0-dev+3847"
        @eval $f{T<:Integer,G<:Gray}(::Type{T}, A::AbstractArray{G}) = reshape([($f)(A[i]) for i = 1:length(A)], size(A))
    end
end

for f in (:mod, :rem, :mod1)
    @eval $f(x::Gray, m::Gray) = Gray($f(gray(x), gray(m)))
end

# Return types for arithmetic operations
multype(a::Type,b::Type) = typeof(one(a)*one(b))
sumtype(a::Type,b::Type) = typeof(one(a)+one(b))
divtype(a::Type,b::Type) = typeof(one(a)/one(b))
powtype(a::Type,b::Type) = typeof(one(a)^one(b))
multype(a::Paint, b::Paint) = multype(typeof(a),typeof(b))
sumtype(a::Paint, b::Paint) = sumtype(typeof(a),typeof(b))
divtype(a::Paint, b::Paint) = divtype(typeof(a),typeof(b))
powtype(a::Paint, b::Paint) = powtype(typeof(a),typeof(b))

# Scalar binary RGB operations require the same RGB type for each element,
# otherwise we don't know which to return
color_rettype{A<:AbstractRGB,B<:AbstractRGB}(::Type{A}, ::Type{B}) = _color_rettype(basecolortype(A), basecolortype(B))
color_rettype{A<:AbstractGray,B<:AbstractGray}(::Type{A}, ::Type{B}) = _color_rettype(basecolortype(A), basecolortype(B))
color_rettype{A<:TransparentRGB,B<:TransparentRGB}(::Type{A}, ::Type{B}) = _color_rettype(basepainttype(A), basepainttype(B))
color_rettype{A<:TransparentGray,B<:TransparentGray}(::Type{A}, ::Type{B}) = _color_rettype(basepainttype(A), basepainttype(B))
_color_rettype{A<:Paint,B<:Paint}(::Type{A}, ::Type{B}) = error("binary operation with $A and $B, return type is ambiguous")
_color_rettype{C<:Paint}(::Type{C}, ::Type{C}) = C

color_rettype(c1::Paint, c2::Paint) = color_rettype(typeof(c1), typeof(c2))

## Math on Colors. These implementations encourage inlining and,
## for the case of Ufixed types, nearly halve the number of multiplications (for RGB)

# Scalar RGB
copy(c::AbstractRGB) = c
(*)(f::Real, c::AbstractRGB) = basecolortype(c){multype(typeof(f),eltype(c))}(f*red(c), f*green(c), f*blue(c))
(*)(f::Real, c::TransparentRGB) = basepainttype(c){multype(typeof(f),eltype(c))}(f*red(c), f*green(c), f*blue(c), f*alpha(c))
function (*){T<:Ufixed}(f::Real, c::AbstractRGB{T})
    fs = f*(1/reinterpret(one(T)))
    basecolortype(c){multype(typeof(f),T)}(fs*reinterpret(red(c)), fs*reinterpret(green(c)), fs*reinterpret(blue(c)))
end
function (*){T<:Ufixed}(f::Ufixed, c::AbstractRGB{T})
    fs = reinterpret(f)*(1/widen(reinterpret(one(T)))^2)
    basecolortype(c){multype(typeof(f),T)}(fs*reinterpret(red(c)), fs*reinterpret(green(c)), fs*reinterpret(blue(c)))
end
function (/){T<:Ufixed}(c::AbstractRGB{T}, f::Real)
    fs = (one(f)/reinterpret(one(T)))/f
    basecolortype(c){divtype(typeof(f),T)}(fs*reinterpret(red(c)), fs*reinterpret(green(c)), fs*reinterpret(blue(c)))
end
(+){S,T}(a::AbstractRGB{S}, b::AbstractRGB{T}) = color_rettype(a, b){sumtype(S,T)}(red(a)+red(b), green(a)+green(b), blue(a)+blue(b))
(-){S,T}(a::AbstractRGB{S}, b::AbstractRGB{T}) = color_rettype(a, b){sumtype(S,T)}(red(a)-red(b), green(a)-green(b), blue(a)-blue(b))
(+)(a::TransparentRGB, b::TransparentRGB) =
    color_rettype(a, b){sumtype(a,b)}(red(a)+red(b), green(a)+green(b), blue(a)+blue(b), alpha(a)+alpha(b))
(-)(a::TransparentRGB, b::TransparentRGB) =
    color_rettype(a, b){sumtype(a,b)}(red(a)-red(b), green(a)-green(b), blue(a)-blue(b), alpha(a)-alpha(b))
(*)(c::AbstractRGB, f::Real) = (*)(f, c)
(*)(c::TransparentRGB, f::Real) = (*)(f, c)
(.*)(f::Real, c::AbstractRGB) = (*)(f, c)
(.*)(f::Real, c::TransparentRGB) = (*)(f, c)
(.*)(c::AbstractRGB, f::Real) = (*)(f, c)
(.*)(c::TransparentRGB, f::Real) = (*)(f, c)
(/)(c::AbstractRGB, f::Real) = (one(f)/f)*c
(/)(c::TransparentRGB, f::Real) = (one(f)/f)*c
# (/)(c::AbstractRGB, f::Integer) = (one(eltype(c))/f)*c
# (/)(c::TransparentRGB, f::Integer) = (one(eltype(c))/f)*c
(./)(c::AbstractRGB, f::Real) = (/)(c, f)
(./)(c::TransparentRGB, f::Real) = (/)(c, f)

isfinite{T<:Ufixed}(c::Paint{T}) = true
isfinite{T<:FloatingPoint}(c::AbstractRGB{T}) = isfinite(red(c)) && isfinite(green(c)) && isfinite(blue(c))
isfinite(c::TransparentRGBFloat) = isfinite(red(c)) && isfinite(green(c)) && isfinite(blue(c)) && isfinite(alpha(c))
isnan{T<:Ufixed}(c::Paint{T}) = false
isnan{T<:FloatingPoint}(c::AbstractRGB{T}) = isnan(red(c)) || isnan(green(c)) || isnan(blue(c))
isnan(c::TransparentRGBFloat) = isnan(red(c)) || isnan(green(c)) || isnan(blue(c)) || isnan(alpha(c))
isinf{T<:Ufixed}(c::Paint{T}) = false
isinf{T<:FloatingPoint}(c::AbstractRGB{T}) = isinf(red(c)) || isinf(green(c)) || isinf(blue(c))
isinf(c::TransparentRGBFloat) = isinf(red(c)) || isinf(green(c)) || isinf(blue(c)) || isinf(alpha(c))
abs(c::AbstractRGB) = abs(red(c))+abs(green(c))+abs(blue(c)) # should this have a different name?
abs{T<:Ufixed}(c::AbstractRGB{T}) = float32(red(c))+float32(green(c))+float32(blue(c)) # should this have a different name?
sumsq(c::AbstractRGB) = red(c)^2+green(c)^2+blue(c)^2
sumsq{T<:Ufixed}(c::AbstractRGB{T}) = float32(red(c))^2+float32(green(c))^2+float32(blue(c))^2

one{C<:AbstractRGB}(::Type{C})     = C(1,1,1)
one{P<:TransparentRGB}(::Type{P})  = P(1,1,1,1)
zero{C<:AbstractRGB}(::Type{C})    = C(0,0,0)
zero{P<:TransparentRGB}(::Type{P}) = P(0,0,0,0)
one(p::Paint) = one(typeof(p))
zero(p::Paint) = zero(typeof(p))
typemin{C<:AbstractRGB}(::Type{C}) = zero(C)
typemax{C<:AbstractRGB}(::Type{C}) = one(C)

# Arrays
(+){CV<:AbstractRGB}(A::AbstractArray{CV}, b::AbstractRGB) = (.+)(A, b)
(+){CV<:AbstractRGB}(b::AbstractRGB, A::AbstractArray{CV}) = (.+)(b, A)
(-){CV<:AbstractRGB}(A::AbstractArray{CV}, b::AbstractRGB) = (.-)(A, b)
(-){CV<:AbstractRGB}(b::AbstractRGB, A::AbstractArray{CV}) = (.-)(b, A)
(*){T<:Number}(A::AbstractArray{T}, b::AbstractRGB) = A.*b
(*){T<:Number}(b::AbstractRGB, A::AbstractArray{T}) = A.*b
(.+){C<:AbstractRGB}(A::AbstractArray{C}, b::AbstractRGB) = plus(A, b)
(.+){C<:AbstractRGB}(b::AbstractRGB, A::AbstractArray{C}) = plus(b, A)
(.-){C<:AbstractRGB}(A::AbstractArray{C}, b::AbstractRGB) = minus(A, b)
(.-){C<:AbstractRGB}(b::AbstractRGB, A::AbstractArray{C}) = minus(b, A)
(.*){T<:Number}(A::AbstractArray{T}, b::AbstractRGB) = mul(A, b)
(.*){T<:Number}(b::AbstractRGB, A::AbstractArray{T}) = mul(b, A)

(+){CV<:TransparentRGB}(A::AbstractArray{CV}, b::TransparentRGB) = (.+)(A, b)
(+){CV<:TransparentRGB}(b::TransparentRGB, A::AbstractArray{CV}) = (.+)(b, A)
(-){CV<:TransparentRGB}(A::AbstractArray{CV}, b::TransparentRGB) = (.-)(A, b)
(-){CV<:TransparentRGB}(b::TransparentRGB, A::AbstractArray{CV}) = (.-)(b, A)
(*){T<:Number}(A::AbstractArray{T}, b::TransparentRGB) = A.*b
(*){T<:Number}(b::TransparentRGB, A::AbstractArray{T}) = A.*b
(.+){C<:TransparentRGB}(A::AbstractArray{C}, b::TransparentRGB) = plus(A, b)
(.+){C<:TransparentRGB}(b::TransparentRGB, A::AbstractArray{C}) = plus(b, A)
(.-){C<:TransparentRGB}(A::AbstractArray{C}, b::TransparentRGB) = minus(A, b)
(.-){C<:TransparentRGB}(b::TransparentRGB, A::AbstractArray{C}) = minus(b, A)
(.*){T<:Number}(A::AbstractArray{T}, b::TransparentRGB) = mul(A, b)
(.*){T<:Number}(b::TransparentRGB, A::AbstractArray{T}) = mul(b, A)

# Scalar Gray
copy(c::AbstractGray) = c
(*)(f::Real, c::AbstractGray) = basecolortype(c){multype(typeof(f),eltype(c))}(f*gray(c))
(*)(f::Real, c::TransparentGray) = basepainttype(c){multype(typeof(f),eltype(c))}(f*gray(c), f*alpha(c))
(*)(c::AbstractGray, f::Real) = (*)(f, c)
(.*)(f::Real, c::AbstractGray) = (*)(f, c)
(.*)(c::AbstractGray, f::Real) = (*)(f, c)
(*)(c::TransparentGray, f::Real) = (*)(f, c)
(.*)(f::Real, c::TransparentGray) = (*)(f, c)
(.*)(c::TransparentGray, f::Real) = (*)(f, c)
(/)(c::AbstractGray, f::Real) = (one(f)/f)*c
(/)(c::TransparentGray, f::Real) = (one(f)/f)*c
(/)(c::AbstractGray, f::Integer) = (one(eltype(c))/f)*c
(/)(c::TransparentGray, f::Integer) = (one(eltype(c))/f)*c
(./)(c::AbstractGray, f::Real) = c/f
(./)(c::TransparentGray, f::Real) = c/f
(+){S,T}(a::AbstractGray{S}, b::AbstractGray{T}) = color_rettype(a,b){sumtype(S,T)}(gray(a)+gray(b))
(+)(a::TransparentGray, b::TransparentGray) = color_rettype(a,b){sumtype(eltype(a),eltype(b))}(gray(a)+gray(b),alpha(a)+alpha(b))
(-){S,T}(a::AbstractGray{S}, b::AbstractGray{T}) = color_rettype(a,b){sumtype(S,T)}(gray(a)-gray(b))
(-)(a::TransparentGray, b::TransparentGray) = color_rettype(a,b){sumtype(eltype(a),eltype(b))}(gray(a)-gray(b),alpha(a)-alpha(b))
(*){S,T}(a::AbstractGray{S}, b::AbstractGray{T}) = color_rettype(a,b){multype(S,T)}(gray(a)*gray(b))
(^){S}(a::AbstractGray{S}, b::Integer) = basecolortype(a){powtype(S,Int)}(gray(a)^convert(Int,b))
(^){S}(a::AbstractGray{S}, b::Real) = basecolortype(a){powtype(S,typeof(b))}(gray(a)^b)
(+)(c::AbstractGray) = c
(+)(c::TransparentGray) = c
(-)(c::AbstractGray) = typeof(c)(-gray(c))
(-)(c::TransparentGray) = typeof(c)(-gray(c),-alpha(c))
(/)(a::AbstractGray, b::AbstractGray) = gray(a)/gray(b)
div(a::AbstractGray, b::AbstractGray) = div(gray(a), gray(b))
(+)(a::AbstractGray, b::Number) = gray(a)+b
(-)(a::AbstractGray, b::Number) = gray(a)-b
(+)(a::Number, b::AbstractGray) = a+gray(b)
(-)(a::Number, b::AbstractGray) = a-gray(b)
(.+)(a::AbstractGray, b::Number) = gray(a)+b
(.-)(a::AbstractGray, b::Number) = gray(a)-b
(.+)(a::Number, b::AbstractGray) = a+gray(b)
(.-)(a::Number, b::AbstractGray) = a-gray(b)

isfinite{T<:FloatingPoint}(c::AbstractGray{T}) = isfinite(gray(c))
isfinite(c::TransparentGrayFloat) = isfinite(gray(c)) && isfinite(alpha(c))
isnan{T<:FloatingPoint}(c::AbstractGray{T}) = isnan(gray(c))
isnan(c::TransparentGrayFloat) = isnan(gray(c)) && isnan(alpha(c))
isinf{T<:FloatingPoint}(c::AbstractGray{T}) = isinf(gray(c))
isinf(c::TransparentGrayFloat) = isinf(gray(c)) && isnan(alpha(c))
abs(c::AbstractGray) = abs(gray(c)) # should this have a different name?
abs(c::TransparentGray) = abs(gray(c))+abs(alpha(c)) # should this have a different name?
abs{T<:Ufixed}(c::AbstractGray{T}) = float32(gray(c)) # should this have a different name?
abs(c::TransparentGrayUfixed) = float32(gray(c)) + float32(alpha(c)) # should this have a different name?
sumsq(x::Real) = x^2
sumsq(c::AbstractGray) = gray(c)^2
sumsq{T<:Ufixed}(c::AbstractGray{T}) = float32(gray(c))^2
sumsq(c::TransparentGray) = gray(c)^2+alpha(c)^2
sumsq(c::TransparentGrayUfixed) = float32(gray(c))^2 + float32(alpha(c))^2
atan2(x::Gray, y::Gray) = atan2(convert(Real, x), convert(Real, y))
hypot(x::Gray, y::Gray) = hypot(convert(Real, x), convert(Real, y))

(<)(c::AbstractGray, r::Real) = gray(c) < r
(<)(r::Real, c::AbstractGray) = r < gray(c)
isless(c::AbstractGray, r::Real) = gray(c) < r
isless(r::Real, c::AbstractGray) = r < gray(c)
(<)(a::AbstractGray, b::AbstractGray) = gray(a) < gray(b)

zero{P<:TransparentGray}(::Type{P}) = P(0,0)
 one{P<:TransparentGray}(::Type{P}) = P(1,1)

 # Arrays
(+){CV<:AbstractGray}(A::AbstractArray{CV}, b::AbstractGray) = (.+)(A, b)
(+){CV<:AbstractGray}(b::AbstractGray, A::AbstractArray{CV}) = (.+)(b, A)
(-){CV<:AbstractGray}(A::AbstractArray{CV}, b::AbstractGray) = (.-)(A, b)
(-){CV<:AbstractGray}(b::AbstractGray, A::AbstractArray{CV}) = (.-)(b, A)
(*){T<:Number}(A::AbstractArray{T}, b::AbstractGray) = A.*b
(*){T<:Number}(b::AbstractGray, A::AbstractArray{T}) = A.*b
(.+){C<:AbstractGray}(A::AbstractArray{C}, b::AbstractGray) = plus(A, b)
(.+){C<:AbstractGray}(b::AbstractGray, A::AbstractArray{C}) = plus(b, A)
(.-){C<:AbstractGray}(A::AbstractArray{C}, b::AbstractGray) = minus(A, b)
(.-){C<:AbstractGray}(b::AbstractGray, A::AbstractArray{C}) = minus(b, A)
(.*){T<:Number}(A::AbstractArray{T}, b::AbstractGray) = mul(A, b)
(.*){T<:Number}(b::AbstractGray, A::AbstractArray{T}) = mul(b, A)
if VERSION < v"0.4.0-dev+6354"
    function (.^){C<:AbstractGray}(A::StridedArray{C}, b::Real)
        Cnew = basecolortype(C){powtype(eltype(C),typeof(b))}
        out = similar(A, Cnew)
        for (i,a) in enumerate(A)
            out[i] = a^b
        end
        out
    end
end

(+){CV<:TransparentGray}(A::AbstractArray{CV}, b::TransparentGray) = (.+)(A, b)
(+){CV<:TransparentGray}(b::TransparentGray, A::AbstractArray{CV}) = (.+)(b, A)
(-){CV<:TransparentGray}(A::AbstractArray{CV}, b::TransparentGray) = (.-)(A, b)
(-){CV<:TransparentGray}(b::TransparentGray, A::AbstractArray{CV}) = (.-)(b, A)
(*){T<:Number}(A::AbstractArray{T}, b::TransparentGray) = A.*b
(*){T<:Number}(b::TransparentGray, A::AbstractArray{T}) = A.*b
(.+){C<:TransparentGray}(A::AbstractArray{C}, b::TransparentGray) = plus(A, b)
(.+){C<:TransparentGray}(b::TransparentGray, A::AbstractArray{C}) = plus(b, A)
(.-){C<:TransparentGray}(A::AbstractArray{C}, b::TransparentGray) = minus(A, b)
(.-){C<:TransparentGray}(b::TransparentGray, A::AbstractArray{C}) = minus(b, A)
(.*){T<:Number}(A::AbstractArray{T}, b::TransparentGray) = mul(A, b)
(.*){T<:Number}(b::TransparentGray, A::AbstractArray{T}) = mul(b, A)

# Called plus/minus instead of plus/sub because `sub` already has a meaning!
function plus(A::AbstractArray, b::Paint)
    bT = convert(eltype(A), b)
    out = similar(A)
    plus!(out, A, bT)
end
plus(b::Paint, A::AbstractArray) = plus(A, b)
function minus(A::AbstractArray, b::Paint)
    bT = convert(eltype(A), b)
    out = similar(A)
    minus!(out, A, bT)
end
function minus(b::Paint, A::AbstractArray)
    bT = convert(eltype(A), b)
    out = similar(A)
    minus!(out, bT, A)
end
function mul{T<:Number}(A::AbstractArray{T}, b::Paint)
    bT = typeof(b*one(T))
    out = similar(A, bT)
    mul!(out, A, b)
end
mul{T<:Number}(b::Paint, A::AbstractArray{T}) = mul(A, b)

@ngenerate N typeof(out) function plus!{T,N}(out, A::AbstractArray{T,N}, b)
    @inbounds begin
        @nloops N i A begin
            @nref(N, out, i) = @nref(N, A, i) + b
        end
    end
    out
end
# need a separate minus! because of unsigned types
@ngenerate N typeof(out) function minus!{T,N}(out, A::AbstractArray{T,N}, b::Paint)  # TODO: change to b::T when julia #8045 fixed
    @inbounds begin
        @nloops N i A begin
            @nref(N, out, i) = @nref(N, A, i) - b
        end
    end
    out
end
@ngenerate N typeof(out) function minus!{T,N}(out, b::Paint, A::AbstractArray{T,N})
    @inbounds begin
        @nloops N i A begin
            @nref(N, out, i) = b - @nref(N, A, i)
        end
    end
    out
end
@ngenerate N typeof(out) function mul!{T,N}(out, A::AbstractArray{T,N}, b)
    @inbounds begin
        @nloops N i A begin
            @nref(N, out, i) = @nref(N, A, i) * b
        end
    end
    out
end
@ngenerate N typeof(out) function div!{T,N}(out, A::AbstractArray{T,N}, b)
    @inbounds begin
        @nloops N i A begin
            @nref(N, out, i) = @nref(N, A, i) / b
        end
    end
    out
end

# To help type inference
if VERSION < v"0.4.0-dev+6354"
    promote_array_type{T<:Real,C<:MathTypes}(::Type{T}, ::Type{C}) = basepainttype(C){promote_type(T, eltype(C))}
#     promote_rule{C<:MathTypes,S<:Integer}(::Type{C}, ::Type{S}) = basepainttype(C){promote_type(eltype(C), S)} # for Array{RGB}./Array{Int}
else
    promote_array_type{T<:Real,C<:MathTypes}(F, ::Type{T}, ::Type{C}) = basecolortype(C){Base.promote_array_type(F, T, eltype(C))}
end
promote_rule{P1<:Paint,P2<:Paint}(::Type{P1}, ::Type{P2}) = color_rettype(P1,P2){promote_type(eltype(P1), eltype(P2))}
promote_rule{T<:Real,C<:AbstractGray}(::Type{T}, ::Type{C}) = promote_type(T, eltype(C))

end