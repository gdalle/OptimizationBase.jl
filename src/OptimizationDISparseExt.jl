using OptimizationBase
import OptimizationBase.ArrayInterface
import OptimizationBase.SciMLBase: OptimizationFunction
import OptimizationBase.LinearAlgebra: I
import DifferentiationInterface
import DifferentiationInterface: prepare_gradient, prepare_hessian, prepare_hvp,
                                 prepare_jacobian,
                                 gradient!, hessian!, hvp!, jacobian!, gradient, hessian,
                                 hvp, jacobian
using ADTypes
using SparseConnectivityTracer, SparseMatrixColorings

function generate_sparse_adtype(adtype)
    if adtype.sparsity_detector isa ADTypes.NoSparsityDetector &&
       adtype.coloring_algorithm isa ADTypes.NoColoringAlgorithm
        adtype = AutoSparse(adtype.dense_ad; sparsity_detector = TracerSparsityDetector(),
            coloring_algorithm = GreedyColoringAlgorithm())
        if adtype.dense_ad isa ADTypes.AutoFiniteDiff
            soadtype = AutoSparse(
                DifferentiationInterface.SecondOrder(adtype.dense_ad, adtype.dense_ad),
                sparsity_detector = TracerSparsityDetector(),
                coloring_algorithm = GreedyColoringAlgorithm())
        elseif !(adtype.dense_ad isa SciMLBase.NoAD) &&
               ADTypes.mode(adtype.dense_ad) isa ADTypes.ForwardMode
            soadtype = AutoSparse(
                DifferentiationInterface.SecondOrder(adtype.dense_ad, AutoReverseDiff()),
                sparsity_detector = TracerSparsityDetector(),
                coloring_algorithm = GreedyColoringAlgorithm()) #make zygote?
        elseif !(adtype isa SciMLBase.NoAD) &&
               ADTypes.mode(adtype.dense_ad) isa ADTypes.ReverseMode
            soadtype = AutoSparse(
                DifferentiationInterface.SecondOrder(AutoForwardDiff(), adtype.dense_ad),
                sparsity_detector = TracerSparsityDetector(),
                coloring_algorithm = GreedyColoringAlgorithm())
        end
    elseif adtype.sparsity_detector isa ADTypes.NoSparsityDetector &&
           !(adtype.coloring_algorithm isa ADTypes.NoColoringAlgorithm)
        adtype = AutoSparse(adtype.dense_ad; sparsity_detector = TracerSparsityDetector(),
            coloring_algorithm = adtype.coloring_algorithm)
        if adtype.dense_ad isa ADTypes.AutoFiniteDiff
            soadtype = AutoSparse(
                DifferentiationInterface.SecondOrder(adtype.dense_ad, adtype.dense_ad),
                sparsity_detector = TracerSparsityDetector(),
                coloring_algorithm = adtype.coloring_algorithm)
        elseif !(adtype.dense_ad isa SciMLBase.NoAD) &&
               ADTypes.mode(adtype.dense_ad) isa ADTypes.ForwardMode
            soadtype = AutoSparse(
                DifferentiationInterface.SecondOrder(adtype.dense_ad, AutoReverseDiff()),
                sparsity_detector = TracerSparsityDetector(),
                coloring_algorithm = adtype.coloring_algorithm)
        elseif !(adtype isa SciMLBase.NoAD) &&
               ADTypes.mode(adtype.dense_ad) isa ADTypes.ReverseMode
            soadtype = AutoSparse(
                DifferentiationInterface.SecondOrder(AutoForwardDiff(), adtype.dense_ad),
                sparsity_detector = TracerSparsityDetector(),
                coloring_algorithm = adtype.coloring_algorithm)
        end
    elseif !(adtype.sparsity_detector isa ADTypes.NoSparsityDetector) &&
           adtype.coloring_algorithm isa ADTypes.NoColoringAlgorithm
        adtype = AutoSparse(adtype.dense_ad; sparsity_detector = adtype.sparsity_detector,
            coloring_algorithm = GreedyColoringAlgorithm())
        if adtype.dense_ad isa ADTypes.AutoFiniteDiff
            soadtype = AutoSparse(
                DifferentiationInterface.SecondOrder(adtype.dense_ad, adtype.dense_ad),
                sparsity_detector = adtype.sparsity_detector,
                coloring_algorithm = GreedyColoringAlgorithm())
        elseif !(adtype.dense_ad isa SciMLBase.NoAD) &&
               ADTypes.mode(adtype.dense_ad) isa ADTypes.ForwardMode
            soadtype = AutoSparse(
                DifferentiationInterface.SecondOrder(adtype.dense_ad, AutoReverseDiff()),
                sparsity_detector = adtype.sparsity_detector,
                coloring_algorithm = GreedyColoringAlgorithm())
        elseif !(adtype isa SciMLBase.NoAD) &&
               ADTypes.mode(adtype.dense_ad) isa ADTypes.ReverseMode
            soadtype = AutoSparse(
                DifferentiationInterface.SecondOrder(AutoForwardDiff(), adtype.dense_ad),
                sparsity_detector = adtype.sparsity_detector,
                coloring_algorithm = GreedyColoringAlgorithm())
        end
    else
        if adtype.dense_ad isa ADTypes.AutoFiniteDiff
            soadtype = AutoSparse(
                DifferentiationInterface.SecondOrder(adtype.dense_ad, adtype.dense_ad),
                sparsity_detector = adtype.sparsity_detector,
                coloring_algorithm = adtype.coloring_algorithm)
        elseif !(adtype.dense_ad isa SciMLBase.NoAD) &&
               ADTypes.mode(adtype.dense_ad) isa ADTypes.ForwardMode
            soadtype = AutoSparse(
                DifferentiationInterface.SecondOrder(adtype.dense_ad, AutoReverseDiff()),
                sparsity_detector = adtype.sparsity_detector,
                coloring_algorithm = adtype.coloring_algorithm)
        elseif !(adtype isa SciMLBase.NoAD) &&
               ADTypes.mode(adtype.dense_ad) isa ADTypes.ReverseMode
            soadtype = AutoSparse(
                DifferentiationInterface.SecondOrder(AutoForwardDiff(), adtype.dense_ad),
                sparsity_detector = adtype.sparsity_detector,
                coloring_algorithm = adtype.coloring_algorithm)
        end
    end
    return adtype, soadtype
end

function instantiate_function(
        f::OptimizationFunction{true}, x, adtype::ADTypes.AutoSparse{<:AbstractADType},
        p = SciMLBase.NullParameters(), num_cons = 0)
    function _f(θ)
        return f(θ, p)[1]
    end

    adtype, soadtype = generate_sparse_adtype(adtype)

    if f.grad === nothing
        extras_grad = prepare_gradient(_f, adtype.dense_ad, x)
        function grad(res, θ)
            gradient!(_f, res, adtype.dense_ad, θ, extras_grad)
        end
    else
        grad = (G, θ) -> f.grad(G, θ, p)
    end

    hess_sparsity = f.hess_prototype
    hess_colors = f.hess_colorvec
    if f.hess === nothing
        extras_hess = prepare_hessian(_f, soadtype, x) #placeholder logic, can be made much better
        function hess(res, θ)
            hessian!(_f, res, soadtype, θ, extras_hess)
        end
    else
        hess = (H, θ) -> f.hess(H, θ, p)
    end

    if f.hv === nothing
        extras_hvp = prepare_hvp(_f, soadtype.dense_ad, x, rand(size(x)))
        hv = function (H, θ, v)
            hvp!(_f, H, soadtype.dense_ad, θ, v, extras_hvp)
        end
    else
        hv = f.hv
    end

    if f.cons === nothing
        cons = nothing
    else
        function cons(res, θ)
            f.cons(res, θ, p)
        end

        function cons_oop(x)
            _res = zeros(eltype(x), num_cons)
            cons(_res, x)
            return _res
        end
    end

    cons_jac_prototype = f.cons_jac_prototype
    cons_jac_colorvec = f.cons_jac_colorvec
    if cons !== nothing && f.cons_j === nothing
        extras_jac = prepare_jacobian(cons_oop, adtype, x)
        function cons_j(J, θ)
            jacobian!(cons_oop, J, adtype, θ, extras_jac)
            if size(J, 1) == 1
                J = vec(J)
            end
        end
    else
        cons_j = (J, θ) -> f.cons_j(J, θ, p)
    end

    conshess_sparsity = f.cons_hess_prototype
    conshess_colors = f.cons_hess_colorvec
    if cons !== nothing && f.cons_h === nothing
        fncs = [(x) -> cons_oop(x)[i] for i in 1:num_cons]
        extras_cons_hess = prepare_hessian.(fncs, Ref(soadtype), Ref(x))

        function cons_h(H, θ)
            for i in 1:num_cons
                hessian!(fncs[i], H[i], soadtype, θ, extras_cons_hess[i])
            end
        end
    else
        cons_h = (res, θ) -> f.cons_h(res, θ, p)
    end

    if f.lag_h === nothing
        lag_h = nothing # Consider implementing this
    else
        lag_h = (res, θ, σ, μ) -> f.lag_h(res, θ, σ, μ, p)
    end
    return OptimizationFunction{true}(f.f, adtype; grad = grad, hess = hess, hv = hv,
        cons = cons, cons_j = cons_j, cons_h = cons_h,
        hess_prototype = hess_sparsity,
        hess_colorvec = hess_colors,
        cons_jac_prototype = cons_jac_prototype,
        cons_jac_colorvec = cons_jac_colorvec,
        cons_hess_prototype = conshess_sparsity,
        cons_hess_colorvec = conshess_colors,
        lag_h,
        lag_hess_prototype = f.lag_hess_prototype,
        sys = f.sys,
        expr = f.expr,
        cons_expr = f.cons_expr)
end

function instantiate_function(
        f::OptimizationFunction{true}, cache::OptimizationBase.ReInitCache,
        adtype::ADTypes.AutoSparse{<:AbstractADType}, num_cons = 0)
    x = cache.u0
    p = cache.p

    return instantiate_function(f, x, adtype, p, num_cons)
end

function instantiate_function(
        f::OptimizationFunction{false}, x, adtype::ADTypes.AutoSparse{<:AbstractADType},
        p = SciMLBase.NullParameters(), num_cons = 0)
    function _f(θ)
        return f(θ, p)[1]
    end

    adtype, soadtype = generate_sparse_adtype(adtype)

    if f.grad === nothing
        extras_grad = prepare_gradient(_f, adtype.dense_ad, x)
        function grad(θ)
            gradient(_f, adtype.dense_ad, θ, extras_grad)
        end
    else
        grad = (θ) -> f.grad(θ, p)
    end

    hess_sparsity = f.hess_prototype
    hess_colors = f.hess_colorvec
    if f.hess === nothing
        extras_hess = prepare_hessian(_f, soadtype, x) #placeholder logic, can be made much better
        function hess(θ)
            hessian(_f, soadtype, θ, extras_hess)
        end
    else
        hess = (θ) -> f.hess(θ, p)
    end

    if f.hv === nothing
        extras_hvp = prepare_hvp(_f, soadtype.dense_ad, x, rand(size(x)))
        function hv(θ, v)
            hvp(_f, soadtype.dense_ad, θ, v, extras_hvp)
        end
    else
        hv = f.hv
    end

    if f.cons === nothing
        cons = nothing
    else
        function cons(θ)
            f.cons(θ, p)
        end
    end

    cons_jac_prototype = f.cons_jac_prototype
    cons_jac_colorvec = f.cons_jac_colorvec
    if cons !== nothing && f.cons_j === nothing
        extras_jac = prepare_jacobian(cons_oop, adtype, x)
        function cons_j(θ)
            J = jacobian(cons_oop, adtype, θ, extras_jac)
            if size(J, 1) == 1
                J = vec(J)
            end
            return J
        end
    else
        cons_j = (θ) -> f.cons_j(θ, p)
    end

    conshess_sparsity = f.cons_hess_prototype
    conshess_colors = f.cons_hess_colorvec
    if cons !== nothing && f.cons_h === nothing
        fncs = [(x) -> cons_oop(x)[i] for i in 1:num_cons]
        extras_cons_hess = prepare_hessian.(fncs, Ref(soadtype), Ref(x))

        function cons_h(θ)
            H = map(1:num_cons) do i
                hessian(fncs[i], soadtype, θ, extras_cons_hess[i])
            end
            return H
        end
    else
        cons_h = (res, θ) -> f.cons_h(res, θ, p)
    end

    if f.lag_h === nothing
        lag_h = nothing # Consider implementing this
    else
        lag_h = (θ, σ, μ) -> f.lag_h(θ, σ, μ, p)
    end
    return OptimizationFunction{true}(f.f, adtype; grad = grad, hess = hess, hv = hv,
        cons = cons, cons_j = cons_j, cons_h = cons_h,
        hess_prototype = hess_sparsity,
        hess_colorvec = hess_colors,
        cons_jac_prototype = cons_jac_prototype,
        cons_jac_colorvec = cons_jac_colorvec,
        cons_hess_prototype = conshess_sparsity,
        cons_hess_colorvec = conshess_colors,
        lag_h,
        lag_hess_prototype = f.lag_hess_prototype,
        sys = f.sys,
        expr = f.expr,
        cons_expr = f.cons_expr)
end

function instantiate_function(
        f::OptimizationFunction{false}, cache::OptimizationBase.ReInitCache,
        adtype::ADTypes.AutoSparse{<:AbstractADType}, num_cons = 0)
    x = cache.u0
    p = cache.p

    return instantiate_function(f, x, adtype, p, num_cons)
end
