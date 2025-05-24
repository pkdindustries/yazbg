const std = @import("std");
const builtin = @import("builtin");

// game configuration - name, has_benchmark
const GameConfig = struct {
    name: []const u8,
    has_benchmark: bool = false,
};

const games = [_]GameConfig{
    .{ .name = "blocks", .has_benchmark = true },
    .{ .name = "spaced" },
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const wasm_target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .cpu_model = .{ .explicit = &std.Target.wasm.cpu.mvp },
        .cpu_features_add = std.Target.wasm.featureSet(&.{
            .atomics,
            .bulk_memory,
        }),
        .os_tag = .emscripten,
    });
    const is_wasm = target.result.cpu.arch == .wasm32;
    const actual_target = if (is_wasm) wasm_target else target;

    const raylib_optimize = b.option(
        std.builtin.OptimizeMode,
        "raylib-optimize",
        "Prioritize performance, safety, or binary size (-O flag), defaults to value of optimize option",
    ) orelse optimize;

    const strip = b.option(
        bool,
        "strip",
        "Strip debug info to reduce binary size, defaults to false",
    ) orelse false;

    const raylib_dep = b.dependency("raylib", .{
        .target = actual_target,
        .optimize = raylib_optimize,
    });
    const raylib_artifact = raylib_dep.artifact("raylib");

    // Add ECS dependency
    const ecs_dep = b.dependency("entt", .{
        .target = actual_target,
        .optimize = optimize,
    });

    // Create engine module (shared between native and wasm)
    const engine_module = b.addModule("engine", .{
        .root_source_file = b.path("src/engine/engine.zig"),
        .target = actual_target,
        .optimize = optimize,
    });
    engine_module.addImport("ecs", ecs_dep.module("zig-ecs"));
    engine_module.addIncludePath(raylib_dep.path("src"));

    if (is_wasm) {
        if (b.sysroot == null) {
            @panic("Pass '--sysroot \"../emsdk/upstream/emscripten\"'");
        }

        // Add emscripten system include paths for the engine module
        const sysroot_include = b.pathJoin(&.{ b.sysroot.?, "cache", "sysroot", "include" });
        engine_module.addIncludePath(.{ .cwd_relative = sysroot_include });

        // verify emscripten cache
        var dir = std.fs.openDirAbsolute(sysroot_include, std.fs.Dir.OpenDirOptions{ .access_sub_paths = true, .no_follow = true }) catch @panic("No emscripten cache. Generate it!");
        dir.close();

        const emcc_exe = switch (builtin.os.tag) {
            .windows => "emcc.bat",
            else => "emcc",
        };
        const emcc_exe_path = b.pathJoin(&.{ b.sysroot.?, emcc_exe });

        // build the HTML5 output with preloaded resources mounted at /resources
        const resource_src = b.path("resources").getPath(b);
        const resource_arg = std.fmt.allocPrint(b.allocator, "{s}@/resources", .{resource_src}) catch unreachable;

        // build each game for wasm
        for (games) |game| {
            // main game executable
            const lib = b.addStaticLibrary(.{
                .name = game.name,
                .root_source_file = b.path(b.fmt("src/games/{s}/main.zig", .{game.name})),
                .target = wasm_target,
                .optimize = optimize,
                .link_libc = true,
            });
            lib.shared_memory = false;
            lib.root_module.single_threaded = true;
            lib.root_module.addImport("engine", engine_module);
            lib.root_module.addImport("ecs", ecs_dep.module("zig-ecs"));
            lib.linkLibrary(raylib_artifact);
            lib.addIncludePath(raylib_dep.path("src"));
            lib.addIncludePath(.{ .cwd_relative = sysroot_include });

            const emcc_command = b.addSystemCommand(&[_][]const u8{emcc_exe_path});
            emcc_command.addArgs(&[_][]const u8{
                "-o",
                b.fmt("zig-out/web/{s}.html", .{game.name}),
                "-O3",
                "-flto",
                "--closure 1",
                "-sMINIFY_HTML=1",
                "-sUSE_GLFW=3",
                "-sASYNCIFY",
                "-sSTACK_SIZE=16777216",
                "-sAUDIO_WORKLET=0",
                "-sUSE_OFFSET_CONVERTER",
                "-sEXPORTED_RUNTIME_METHODS=['HEAPF32', 'ccall', 'cwrap']",
                "--preload-file",
                resource_arg,
                "--shell-file",
                b.path("web/shell.html").getPath(b),
                "--preload-file",
                resource_arg,
            });

            const link_items: []const *std.Build.Step.Compile = &.{
                raylib_artifact,
                lib,
            };
            for (link_items) |item| {
                emcc_command.addFileArg(item.getEmittedBin());
                emcc_command.step.dependOn(&item.step);
            }
            b.default_step.dependOn(&emcc_command.step);

            // benchmark if it exists
            if (game.has_benchmark) {
                const benchmark_lib = b.addStaticLibrary(.{
                    .name = b.fmt("{s}-benchmark", .{game.name}),
                    .root_source_file = b.path(b.fmt("src/games/{s}/benchmark.zig", .{game.name})),
                    .target = wasm_target,
                    .optimize = optimize,
                    .link_libc = true,
                });
                benchmark_lib.shared_memory = false;
                benchmark_lib.root_module.single_threaded = true;
                benchmark_lib.root_module.addImport("engine", engine_module);
                benchmark_lib.root_module.addImport("ecs", ecs_dep.module("zig-ecs"));
                benchmark_lib.linkLibrary(raylib_artifact);
                benchmark_lib.addIncludePath(raylib_dep.path("src"));
                benchmark_lib.addIncludePath(.{ .cwd_relative = sysroot_include });

                const emcc_benchmark = b.addSystemCommand(&[_][]const u8{emcc_exe_path});
                emcc_benchmark.addArgs(&[_][]const u8{
                    "-o",
                    b.fmt("zig-out/web/{s}-benchmark.html", .{game.name}),
                    "-sUSE_GLFW=3",
                    "-O3",
                    "-flto",
                    "--closure 1",
                    "-sMINIFY_HTML=1",
                    "-sASYNCIFY",
                    "-sSTACK_SIZE=16777216",
                    "-sAUDIO_WORKLET=0",
                    "-sUSE_OFFSET_CONVERTER",
                    "-sEXPORTED_RUNTIME_METHODS=['HEAPF32', 'ccall', 'cwrap']",
                    "--preload-file",
                    resource_arg,
                    "--shell-file",
                    b.path("web/shell.html").getPath(b),
                    "--preload-file",
                    resource_arg,
                });
                const benchmark_link_items: []const *std.Build.Step.Compile = &.{
                    raylib_artifact,
                    benchmark_lib,
                };
                for (benchmark_link_items) |item| {
                    emcc_benchmark.addFileArg(item.getEmittedBin());
                    emcc_benchmark.step.dependOn(&item.step);
                }
                b.default_step.dependOn(&emcc_benchmark.step);
            }
        }
    } else {
        // build each game for native
        var first_game = true;
        for (games) |game| {
            // main game executable
            const exe = b.addExecutable(.{
                .name = game.name,
                .root_source_file = b.path(b.fmt("src/games/{s}/main.zig", .{game.name})),
                .target = target,
                .optimize = optimize,
                .omit_frame_pointer = false, // keep frame pointer
            });
            exe.root_module.strip = strip;
            exe.linkLibrary(raylib_artifact);
            exe.root_module.addImport("engine", engine_module);
            exe.root_module.addImport("ecs", ecs_dep.module("zig-ecs"));

            b.installArtifact(exe);

            const run_cmd = b.addRunArtifact(exe);
            run_cmd.step.dependOn(b.getInstallStep());
            if (b.args) |args| {
                run_cmd.addArgs(args);
            }

            // create step to run this game
            const run_step = b.step(game.name, b.fmt("Run {s} game", .{game.name}));
            run_step.dependOn(&run_cmd.step);

            // the first game is the default for 'zig build run'
            if (first_game) {
                const run_default = b.step("run", "Run the default game");
                run_default.dependOn(&run_cmd.step);
                first_game = false;
            }

            // benchmark if it exists
            if (game.has_benchmark) {
                const benchmark_exe = b.addExecutable(.{
                    .name = b.fmt("{s}-benchmark", .{game.name}),
                    .root_source_file = b.path(b.fmt("src/games/{s}/benchmark.zig", .{game.name})),
                    .target = target,
                    .optimize = optimize,
                    .omit_frame_pointer = false, // keep frame pointer
                });
                benchmark_exe.root_module.strip = strip;
                benchmark_exe.linkLibrary(raylib_artifact);
                benchmark_exe.root_module.addImport("engine", engine_module);
                benchmark_exe.root_module.addImport("ecs", ecs_dep.module("zig-ecs"));

                b.installArtifact(benchmark_exe);

                const run_benchmark = b.addRunArtifact(benchmark_exe);
                run_benchmark.step.dependOn(b.getInstallStep());
                if (b.args) |args| {
                    run_benchmark.addArgs(args);
                }

                const benchmark_step = b.step(b.fmt("{s}-benchmark", .{game.name}), b.fmt("Run the {s} benchmark", .{game.name}));
                benchmark_step.dependOn(&run_benchmark.step);
            }

            // unit tests
            const unit_tests = b.addTest(.{
                .root_source_file = b.path(b.fmt("src/games/{s}/main.zig", .{game.name})),
                .target = target,
                .optimize = optimize,
            });

            const run_unit_tests = b.addRunArtifact(unit_tests);
            const test_step = b.step(b.fmt("{s}-test", .{game.name}), b.fmt("Run {s} unit tests", .{game.name}));
            test_step.dependOn(&run_unit_tests.step);
        }
    }
}
