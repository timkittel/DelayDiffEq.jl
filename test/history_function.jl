@testset "HistoryFunction" begin
    # check constant extrapolation with problem with vanishing delays at t = 0
    @testset "vanishing delays" begin
        prob = DDEProblem((du,u,h,p,t) -> -h(p, t/2)[1], [1.0], (p, t) -> [1.0], (0.0, 10.0))
        solve(prob, MethodOfSteps(RK4()))
    end


    @testset "general" begin
        # naive history functions
        h_notinplace(p, t; idxs=nothing) = typeof(idxs) <: Nothing ? [t, -t] : [t, -t][idxs]

        function h_inplace(val, p, t; idxs=nothing)
            if typeof(idxs) <: Nothing
                val[1] = t
                val[2] = -t
            else
                val .= [t; -t][idxs]
            end
        end

        @testset "agrees (h=$h)" for h in (h_notinplace, h_inplace)
            @test DelayDiffEq.agrees(h, zeros(2), nothing, 0)
            @test !DelayDiffEq.agrees(h, ones(2), nothing, 1)
        end

        # ODE integrator
        prob = ODEProblem((du,u,p,t)->@.(du=p*u), ones(2), (0.0, 1.0),1.01)
        integrator = init(prob, Tsit5())

        # combined history function
        history_notinplace = DelayDiffEq.HistoryFunction(h_notinplace,
                                                         integrator.sol,
                                                         integrator)
        history_inplace = DelayDiffEq.HistoryFunction(h_inplace,
                                                      integrator.sol,
                                                      integrator)

        # test evaluation of history function
        @testset "evaluation (idxs=$idxs)" for idxs in (nothing, [2])
            # expected value
            trueval = h_notinplace(nothing, -1; idxs = idxs)

            # out-of-place
            @test history_notinplace(nothing, -1, Val{0}; idxs = idxs) == trueval

            # in-place
            val = zero(trueval)
            history_inplace(val, nothing, -1; idxs = idxs)
            @test val == trueval

            val = zero(trueval)
            history_inplace(val, nothing, -1, Val{0}; idxs = idxs)
            @test val == trueval
        end

        # test constant extrapolation
        @testset "constant extrapolation (deriv=$deriv, idxs=$idxs)" for
            deriv in (Val{0}, Val{1}), idxs in (nothing, [2])
            # expected value
            trueval = deriv == Val{0} ?
                (idxs == nothing ? integrator.u : integrator.u[[2]]) :
                (idxs == nothing ? zeros(2) : [0.0])

            # out-of-place
            integrator.isout = false
            @test history_notinplace(nothing, 1, deriv; idxs = idxs) == trueval &&
                integrator.isout

            # in-place
            integrator.isout = false
            @test history_inplace(nothing, nothing, 1, deriv; idxs = idxs) == trueval &&
                integrator.isout

            integrator.isout = false
            val = 1 .- trueval # ensures that val ≠ trueval
            history_inplace(val, nothing, 1, deriv; idxs = idxs)
            @test val == trueval && integrator.isout
        end

        # add step to integrator
        @testset "update integrator" begin
            OrdinaryDiffEq.loopheader!(integrator)
            OrdinaryDiffEq.perform_step!(integrator, integrator.cache)
            integrator.t = integrator.dt
            @test 0.01 < integrator.t < 1
            @test integrator.sol.t[end] == 0
        end

        # test integrator interpolation
        @testset "integrator interpolation (deriv=$deriv, idxs=$idxs)" for
            deriv in (Val{0}, Val{1}), idxs in (nothing, [2])
            # expected value
            trueval = OrdinaryDiffEq.current_interpolant(0.01, integrator, idxs, deriv)

            # out-of-place
            integrator.isout = false
            @test history_notinplace(nothing, 0.01, deriv; idxs = idxs) == trueval &&
                integrator.isout

            # in-place
            integrator.isout = false
            val = zero(trueval)
            history_inplace(val, nothing, 0.01, deriv; idxs = idxs)
            @test val == trueval && integrator.isout
        end

        # add step to solution
        @testset "update solution" begin
            integrator.t = 0
            OrdinaryDiffEq.loopfooter!(integrator)
            @test integrator.t == integrator.sol.t[end]
        end

        # test solution interpolation
        @testset "solution interpolation (deriv=$deriv, idxs=$idxs)" for
            deriv in (Val{0}, Val{1}), idxs in (nothing, [2])
            # expected value
            trueval = integrator.sol.interp(0.01, idxs, deriv, integrator.p)

            # out-of-place
            @test history_notinplace(nothing, 0.01, deriv; idxs = idxs) == trueval &&
                !integrator.isout

            # in-place
            val = zero(trueval)
            history_inplace(val, nothing, 0.01, deriv; idxs = idxs)
            @test val == trueval && !integrator.isout
        end

        # test integrator extrapolation
        @testset "integrator extrapolation (deriv=$deriv, idxs=$idxs)" for
            deriv in (Val{0}, Val{1}), idxs in (0, [2])
            idxs == 0 && (idxs = nothing)
            # expected value
            trueval = OrdinaryDiffEq.current_interpolant(1, integrator, idxs, deriv)

            # out-of-place
            integrator.isout = false
            @test history_notinplace(nothing, 1, deriv; idxs = idxs) == trueval &&
                integrator.isout

            # in-place
            integrator.isout = false
            val = zero(trueval)
            history_inplace(val, nothing, 1, deriv; idxs = idxs)
            @test val == trueval && integrator.isout
        end
    end
end
