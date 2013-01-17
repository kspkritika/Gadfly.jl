
module Stat

import Gadfly
using DataFrames
using Compose

import Gadfly.Scale, Gadfly.element_aesthetics, Gadfly.default_scales
import Distributions.Uniform
import Iterators.chain, Iterators.cycle

include("bincount.jl")

# Apply a series of statistics.
#
# Args:
#   stats: Statistics to apply in order.
#   scales: Scales used by the plot.
#   aes: A Aesthetics instance.
#
# Returns:
#   Nothing, modifies aes.
#
function apply_statistics(stats::Vector{Gadfly.StatisticElement},
                          scales::Dict{Symbol, Gadfly.ScaleElement},
                          aes::Gadfly.Aesthetics)
    for stat in stats
        apply_statistic(stat, scales, aes)
    end
    nothing
end

type Nil <: Gadfly.StatisticElement
end

const nil = Nil()

type Identity <: Gadfly.StatisticElement
end

function apply_statistic(stat::Identity,
                         scales::Dict{Symbol, Gadfly.ScaleElement},
                         aes::Gadfly.Aesthetics)
    nothing
end

const identity = Identity()


type HistogramStatistic <: Gadfly.StatisticElement
end


element_aesthetics(::HistogramStatistic) = [:x]


const histogram = HistogramStatistic()


function apply_statistic(stat::HistogramStatistic,
                         scales::Dict{Symbol, Gadfly.ScaleElement},
                         aes::Gadfly.Aesthetics)
    d, bincounts = choose_bin_count_1d(aes.x)

    x_min, x_max = min(aes.x), max(aes.x)
    binwidth = (x_max - x_min) / d

    aes.x_min = Array(Float64, d)
    aes.x_max = Array(Float64, d)
    aes.y = Array(Float64, d)

    for k in 1:d
        aes.x_min[k] = x_min + (k - 1) * binwidth
        aes.x_max[k] = x_min + k * binwidth
        aes.y[k] = bincounts[k]
    end
end


type RectangularBinStatistic <: Gadfly.StatisticElement
end


element_aesthetics(::RectangularBinStatistic) = [:x, :y, :color]


default_scales(::RectangularBinStatistic) = [Gadfly.Scale.color_gradient]


const rectbin = RectangularBinStatistic()


function apply_statistic(stat::RectangularBinStatistic,
                         scales::Dict{Symbol, Gadfly.ScaleElement},
                         aes::Gadfly.Aesthetics)

    dx, dy, bincounts = choose_bin_count_2d(aes.x, aes.y)

    x_min, x_max = min(aes.x), max(aes.x)
    y_min, y_max = min(aes.y), max(aes.y)

    # bin widths
    wx = (x_max - x_min) / dx
    wy = (y_max - y_min) / dy

    aes.x_min = Array(Float64, dx)
    aes.x_max = Array(Float64, dx)
    for k in 1:dx
        aes.x_min[k] = x_min + (k - 1) * wx
        aes.x_max[k] = x_min + k * wx
    end

    aes.y_min = Array(Float64, dy)
    aes.y_max = Array(Float64, dy)
    for k in 1:dy
        aes.y_min[k] = y_min + (k - 1) * wy
        aes.y_max[k] = y_min + k * wy
    end

    if !has(scales, :color)
        error("RectangularBinStatistic requires a color scale.")
    end
    color_scale = scales[:color]
    if !(typeof(color_scale) <: Scale.ContinuousColorScale)
        error("RectangularBinStatistic requires a continuous color scale.")
    end

    aes.color_key_title = "Count"

    data = Gadfly.Data()
    data.color = [cnt < 1 ? NA : cnt for cnt in bincounts]
    Scale.apply_scale(color_scale, [aes], data)
    nothing
end


default_statistic(stat::RectangularBinStatistic) = [Scale.color_gradient]


# Find reasonable places to put tick marks and grid lines.
type TickStatistic <: Gadfly.StatisticElement
    in_vars::Vector{Symbol}
    out_var::Symbol
end


const x_ticks = TickStatistic([:x], :xtick)
const y_ticks = TickStatistic(
    [:y, :middle, :lower_hinge, :upper_hinge,
     :lower_fence, :upper_fence], :ytick)


# Apply a tick statistic.
#
# Args:
#   stat: statistic.
#   aes: aesthetics.
#
# Returns:
#   nothing
#
# Modifies:
#   aes
#
function apply_statistic(stat::TickStatistic,
                         scales::Dict{Symbol, Gadfly.ScaleElement},
                         aes::Gadfly.Aesthetics)
    in_values = [getfield(aes, var) for var in stat.in_vars]
    in_values = filter(val -> !(val === nothing), in_values)
    in_values = chain(in_values...)
    # TODO: handle the outliers aesthetic

    minval = Inf
    maxval = -Inf
    all_int = true

    for val in in_values
        if val < minval
            minval = val
        end

        if val > maxval
            maxval = val
        end

        if !(typeof(val) <: Integer)
            all_int = false
        end
    end

    # all the input values in order.
    if all_int
        ticks = Set{Float64}()
        add_each(ticks, chain(in_values))
        ticks = Float64[t for t in ticks]
        sort!(ticks)
    else
        ticks = Gadfly.optimize_ticks(minval, maxval)
    end

    # We use the first label function we find for any of the aesthetics. I'm not
    # positive this is the right thing to do, or would would be.
    labeler = getfield(aes, symbol(@sprintf("%s_label", stat.in_vars[1])))

    setfield(aes, stat.out_var, ticks)
    setfield(aes, symbol(@sprintf("%s_label", stat.out_var)), labeler)

    nothing
end

type BoxplotStatistic <: Gadfly.StatisticElement
end


element_aesthetics(::BoxplotStatistic) = [:x, :y]


const boxplot = BoxplotStatistic()


function apply_statistic(stat::BoxplotStatistic,
                         scales::Dict{Symbol, Gadfly.ScaleElement},
                         aes::Gadfly.Aesthetics)
    Gadfly.assert_aesthetics_defined("BoxplotStatistic", aes, :y)

    groups = Dict()

    aes_x = aes.x === nothing ? [nothing] : aes.x
    aes_color = aes.color === nothing ? [nothing] : aes.color

    for (x, y, c) in zip(cycle(aes_x), aes.y, cycle(aes_color))
        if !has(groups, (x, c))
            groups[(x, c)] = Float64[]
        else
            push!(groups[(x, c)], y)
        end
    end

    m = length(groups)
    aes.middle = Array(Float64, m)
    aes.lower_hinge = Array(Float64, m)
    aes.upper_hinge = Array(Float64, m)
    aes.lower_fence = Array(Float64, m)
    aes.upper_fence = Array(Float64, m)
    aes.outliers = Vector{Float64}[]

    for (i, ((x, c), ys)) in enumerate(groups)
        aes.lower_hinge[i], aes.middle[i], aes.upper_hinge[i] =
                quantile(ys, [0.25, 0.5, 0.75])
        iqr = aes.upper_hinge[i] - aes.lower_hinge[i]
        aes.lower_fence[i] = aes.lower_hinge[i] - 1.5iqr
        aes.upper_fence[i] = aes.upper_hinge[i] + 1.5iqr
        push!(aes.outliers,
             filter(y -> y < aes.lower_fence[i] || y > aes.upper_fence[i], ys))
    end

    if !is(aes.x, nothing)
        aes.x = Int64[x for (x, c) in keys(groups)]
    end

    if !is(aes.color, nothing)
        aes.color = PooledDataArray(Color[c for (x, c) in keys(groups)],
                                    levels(aes.color))
    end

    nothing
end


end # module Stat
