"""
Methods for loading and representing 3D physical scenes/vignettes in terms of tracks of bounding boxes of objects of interest.
"""
module Scenes

export Frame, Box, compute_distance

using Images
using PyPlot
import PyPlot: plot
using PyCall
@pyimport matplotlib.patches as patches
import Base: +, -

const TRACK_MAP = Dict("right_hand"=>1, "left_hand"=>2, "rat"=>3, "monkey"=>4)

immutable Point{T}
    x::T
    y::T
end

Point(x, y) = Point(promote(x, y)...)

for op in [:-, :+]
    @eval $op(p1::Point, p2::Point) = Point($op(p1.x, p2.x), $op(p1.y, p2.y))
end

immutable Box
    top_left::Point{Float64}
    bottom_right::Point{Float64}
end

function Base.show(io::IO, box::Box)
    print(io, @sprintf("(%.2f, %.2f, %.2f, %.2f)", box.top_left.x, box.top_left.y, box.bottom_right.x, box.bottom_right.y))
end

plot(box::Box) = plot(box, 1)

function plot(box::Box, box_id)
    color_wheel = ["red", "green", "blue", "orange", "purple"]
    ax = gca()
    ax[:add_patch](patches.Rectangle((box.top_left.x, box.top_left.y), box.bottom_right.x-box.top_left.x, box.bottom_right.y-box.top_left.y, fill=false, linewidth=3, edgecolor=color_wheel[mod1(box_id, length(color_wheel))]))
end

center(b::Box) = Point((b.top_left.x+b.bottom_right.x)//2, (b.bottom_right.y+b.top_left.y)//2)
compute_distance(b1::Box, b2::Box) = compute_distance(center(b1), center(b2))

function compute_distance(p1::Point, p2::Point)
    return sqrt((p1.x-p2.x)^2 + (p1.y-p2.y)^2)
end

immutable Frame
    boxes::Vector{Box}
    track_ids::Vector{Int}
    optical_flows::Array{Float64, 2}
end

Frame(boxes::Vector{Box}) = Frame(boxes, zeros(Int, length(boxes)), zeros(Float64, length(boxes), 2))
Frame() = Frame(Box[])

type Scene
    color::Nullable{Array{Float64, 4}}
    depth::Nullable{Array{Float64, 3}}
    detections::Nullable{Vector{Frame}}
    path::Nullable{String}
end

Scene() = Scene(Nullable{Array{Float64,4}}(), Nullable{Array{Float64, 3}}(), Nullable{Vector{Frame}}(), Nullable{String}())

function load_color_frame(path)
    im::Images.Image = load(path)
    raw = convert(Array{Float64}, data(separate(im)))
    raw
end

function plot(scene::Scene, frame_id)
    isnull(scene.path) && error("Scene doesn't have path information")
    path = get(scene.path)
    frame = load_color_frame(joinpath(path, "color", "image-$frame_id.jpg"))
    imshow(frame)
    if !isnull(scene.detections)
        detections = get(scene.detections)
        for (box_id, box) in enumerate(detections[frame_id].boxes)
            plot(box, box_id)
        end
    end
end

function load_annotations(frames, path)
    const track_id=1
    const xmin=2
    const ymin=3
    const xmax=4
    const ymax=5
    const frame=6
    const lost=7
    const occluded=8
    const generated=9
    const label=10
    const turk_width = 720
    const turk_height = 405
    const real_width = 1920
    const real_height = 1080
    width_ratio = real_width/turk_width
    height_ratio = real_height/turk_height
    data = readdlm(path)

    for row in 1:size(data, 1)
        track_id = TRACK_MAP[data[row, label]]
        box = Box(Point{Float64}(width_ratio*data[row, xmin], height_ratio*data[row, ymin]),
            Point{Float64}(width_ratio*data[row, xmax], height_ratio*data[row, ymax]))
        frame_id = data[row, frame]+1
        push!(frames[frame_id].boxes, box)
        push!(frames[frame_id].track_ids, track_id)
    end
end

function load_hand_positions(frames::Vector{Frame}, path)
    const frame_id = 1
    const person_id = 2
    const right_hand_x = 3
    const right_hand_y = 4
    const left_hand_x = 5
    const left_hand_y = 6
    const width = 50

    points = readcsv(path)
    correspondance_file = joinpath(dirname(path), "color", "frame_correspondance.csv") |> readcsv
    correspondance = Dict{Int, Int}()
    for row in 2:size(correspondance_file, 1)
        correspondance[correspondance_file[row, 2]] = correspondance_file[row, 1] + 1
    end
    for row in 2:size(points, 1)
        points[row, person_id] == 0 && continue
        true_frame = points[row, frame_id]
        (true_frame ∉ keys(correspondance)) && continue
        frame = correspondance[true_frame]
        frame > length(frames) && continue
        # frame > length(frames) && continue  # TODO: figure out frame alignment issue
        for (hand, pos_x, pos_y) in [("right_hand", points[row, right_hand_x], points[row, right_hand_y]), ("left_hand", points[row, left_hand_x], points[row, left_hand_y])]
            if isa(pos_x, Number)
                top_left = Point(pos_x - width/2, pos_y-width/2)
                bottom_right = Point(pos_x + width/2, pos_y+width/2)
                push!(frames[frame].boxes, Box(top_left, bottom_right))
                push!(frames[frame].track_ids, TRACK_MAP[hand])
            end
        end
    end
end

function load_scene(path)
    ids = Dict{Int, String}()
    for file in readdir(joinpath(path, "color"))
        m = match(r".*?(\d+)\.jpg", file)
        if m !== nothing
            id = m.captures[1]
            ids[parse(Int, id)] = file
        end
    end
    scene = Scene()
    scene.path = path
    detections = Frame[]
    n_frames = maximum(keys(ids))
    for frame in 1:n_frames
        push!(detections, Frame())
    end
    if isfile(joinpath(path, "hand_points.csv"))
        load_hand_positions(detections, joinpath(path, "hand_points.csv"))
    end
    if isfile(joinpath(path, "annotations.txt"))
        load_annotations(detections, joinpath(path, "annotations.txt"))
    end

    scene.detections = Nullable(detections)
    return scene
end
scene = load_scene("/storage/malmaud/kinect/pickup1")
figure()


clf(); plot(scene,400)

end
