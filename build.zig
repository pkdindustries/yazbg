const std = @import("std");
const builtin = @import("builtin");

// game configuration
const GameConfig = struct {
    name: []const u8,
    secondaries: []const []const u8 = &.{},
};

const games = [_]GameConfig{
    .{ .name = "blocks", .secondaries = &.{"benchmark"} },
    .{ .name = "spaced" },
};

fn configureModule(module: *std.Build.Module, engine_module: *std.Build.Module, ecs_dep: *std.Build.Dependency, raylib_dep: *std.Build.Dependency, raylib_artifact: *std.Build.Step.Compile, sysroot_include: ?[]const u8, strip: bool) void {
    module.addImport("engine", engine_module);
    module.addImport("ecs", ecs_dep.module("zig-ecs"));
    module.linkLibrary(raylib_artifact);
    module.addIncludePath(raylib_dep.path("src"));
    if (sysroot_include) |include| {
        module.addIncludePath(.{ .cwd_relative = include });
    }
    if (strip) {
        module.strip = true;
    }
}

fn buildWasmBinary(b: *std.Build, name: []const u8, source_path: []const u8, wasm_target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, engine_module: *std.Build.Module, ecs_dep: *std.Build.Dependency, raylib_dep: *std.Build.Dependency, raylib_artifact: *std.Build.Step.Compile, sysroot_include: []const u8, emcc_exe_path: []const u8, emcc_args: []const []const u8) void {
    const lib = b.addStaticLibrary(.{
        .name = name,
        .root_source_file = b.path(source_path),
        .target = wasm_target,
        .optimize = optimize,
        .link_libc = true,
    });
    lib.shared_memory = false;
    lib.root_module.single_threaded = true;
    configureModule(lib.root_module, engine_module, ecs_dep, raylib_dep, raylib_artifact, sysroot_include, false);

    const emcc_command = b.addSystemCommand(&[_][]const u8{emcc_exe_path});
    emcc_command.addArgs(&[_][]const u8{
        "-o",
        b.fmt("zig-out/web/{s}.html", .{name}),
    });
    emcc_command.addArgs(emcc_args);
    
    const link_items: []const *std.Build.Step.Compile = &.{ raylib_artifact, lib };
    for (link_items) |item| {
        emcc_command.addFileArg(item.getEmittedBin());
        emcc_command.step.dependOn(&item.step);
    }
    b.default_step.dependOn(&emcc_command.step);
}

fn buildNativeBinary(b: *std.Build, name: []const u8, source_path: []const u8, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, engine_module: *std.Build.Module, ecs_dep: *std.Build.Dependency, raylib_dep: *std.Build.Dependency, raylib_artifact: *std.Build.Step.Compile, strip: bool, step_name: []const u8, step_desc: []const u8) *std.Build.Step {
    const exe = b.addExecutable(.{
        .name = name,
        .root_source_file = b.path(source_path),
        .target = target,
        .optimize = optimize,
        .omit_frame_pointer = false,
    });
    configureModule(exe.root_module, engine_module, ecs_dep, raylib_dep, raylib_artifact, null, strip);
    
    b.installArtifact(exe);
    
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    
    const run_step = b.step(step_name, step_desc);
    run_step.dependOn(&run_cmd.step);
    return &run_cmd.step;
}

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

    // dependencies
    const raylib_dep = b.dependency("raylib", .{
        .target = actual_target,
        .optimize = raylib_optimize,
    });
    const raylib_artifact = raylib_dep.artifact("raylib");
    
    const ecs_dep = b.dependency("entt", .{
        .target = actual_target,
        .optimize = optimize,
    });

    // engine module
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

        // common emcc args
        const emcc_args = [_][]const u8{
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
        };

        // build each game for wasm
        for (games) |game| {
            buildWasmBinary(
                b,
                game.name,
                b.fmt("src/games/{s}/main.zig", .{game.name}),
                wasm_target,
                optimize,
                engine_module,
                ecs_dep,
                raylib_dep,
                raylib_artifact,
                sysroot_include,
                emcc_exe_path,
                &emcc_args,
            );
            
            // secondary binaries
            for (game.secondaries) |secondary| {
                buildWasmBinary(
                    b,
                    b.fmt("{s}-{s}", .{ game.name, secondary }),
                    b.fmt("src/games/{s}/{s}.zig", .{ game.name, secondary }),
                    wasm_target,
                    optimize,
                    engine_module,
                    ecs_dep,
                    raylib_dep,
                    raylib_artifact,
                    sysroot_include,
                    emcc_exe_path,
                    &emcc_args,
                );
            }
        }
    } else {
        // build each game for native
        var first_game = true;
        for (games) |game| {
            const run_step = buildNativeBinary(
                b,
                game.name,
                b.fmt("src/games/{s}/main.zig", .{game.name}),
                target,
                optimize,
                engine_module,
                ecs_dep,
                raylib_dep,
                raylib_artifact,
                strip,
                game.name,
                b.fmt("Run {s} game", .{game.name}),
            );
            
            // the first game is the default for 'zig build run'
            if (first_game) {
                const run_default = b.step("run", "Run the default game");
                run_default.dependOn(run_step);
                first_game = false;
            }
            
            // secondary binaries
            for (game.secondaries) |secondary| {
                _ = buildNativeBinary(
                    b,
                    b.fmt("{s}-{s}", .{ game.name, secondary }),
                    b.fmt("src/games/{s}/{s}.zig", .{ game.name, secondary }),
                    target,
                    optimize,
                    engine_module,
                    ecs_dep,
                    raylib_dep,
                    raylib_artifact,
                    strip,
                    b.fmt("{s}-{s}", .{ game.name, secondary }),
                    b.fmt("Run {s} {s}", .{ game.name, secondary }),
                );
            }
            
            // unit tests
            const unit_tests = b.addTest(.{
                .root_source_file = b.path(b.fmt("src/games/{s}/main.zig", .{game.name})),
                .target = target,
                .optimize = optimize,
            });
            unit_tests.root_module.addImport("engine", engine_module);
            unit_tests.root_module.addImport("ecs", ecs_dep.module("zig-ecs"));
            
            const run_unit_tests = b.addRunArtifact(unit_tests);
            const test_step = b.step(b.fmt("{s}-test", .{game.name}), b.fmt("Run {s} unit tests", .{game.name}));
            test_step.dependOn(&run_unit_tests.step);
        }
    }
}
