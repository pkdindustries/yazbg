const std = @import("std");
const builtin = @import("builtin");

// wasm references used to create this:
// https://github.com/permutationlock/zig_emscripten_threads/blob/main/build.zig
// https://ziggit.dev/docs?topic=3531
// https://ziggit.dev/t/state-of-concurrency-support-on-wasm32-freestanding/1465/8
// https://ziggit.dev/t/why-suse-offset-converter-is-needed/4131/3
// https://github.com/raysan5/raylib/blob/master/src/build.zig
// https://github.com/silbinarywolf/3d-raylib-toy-project/blob/main/raylib-zig/build.zig
// https://github.com/ziglang/zig/issues/10836
// https://github.com/bluesillybeard/ZigAndRaylibSetup/blob/main/build.zig
// https://github.com/Not-Nik/raylib-zig/issues/24
// https://github.com/raysan5/raylib/wiki/Working-for-Web-%28HTML5%29

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

    if (is_wasm) {
        if (b.sysroot == null) {
            @panic("Pass '--sysroot \"../emsdk/upstream/emscripten\"'");
        }

        const exe_lib = b.addStaticLibrary(.{
            .name = "yazbg",
            .root_source_file = b.path("src/main.zig"),
            .target = wasm_target,
            .optimize = optimize,
            .link_libc = true,
        });
        exe_lib.shared_memory = false;
        exe_lib.root_module.single_threaded = true;

        // Add ECS dependency for WebAssembly build
        const ecs_dep = b.dependency("entt", .{
            .target = wasm_target,
            .optimize = optimize,
        });
        exe_lib.root_module.addImport("ecs", ecs_dep.module("zig-ecs"));

        exe_lib.linkLibrary(raylib_artifact);
        exe_lib.addIncludePath(raylib_dep.path("src"));

        const sysroot_include = b.pathJoin(&.{ b.sysroot.?, "cache", "sysroot", "include" });
        var dir = std.fs.openDirAbsolute(sysroot_include, std.fs.Dir.OpenDirOptions{ .access_sub_paths = true, .no_follow = true }) catch @panic("No emscripten cache. Generate it!");
        dir.close();

        exe_lib.addIncludePath(.{ .cwd_relative = sysroot_include });

        const emcc_exe = switch (builtin.os.tag) {
            .windows => "emcc.bat",
            else => "emcc",
        };

        const emcc_exe_path = b.pathJoin(&.{ b.sysroot.?, emcc_exe });
        const emcc_command = b.addSystemCommand(&[_][]const u8{emcc_exe_path});
        // Build the HTML5 output with preloaded resources mounted at /resources
        const resource_src = b.path("resources").getPath(b);
        const resource_arg = std.fmt.allocPrint(b.allocator, "{s}@/resources", .{resource_src}) catch unreachable;
        emcc_command.addArgs(&[_][]const u8{
            "-o",
            "zig-out/web/yazbg.html",
            "-O3",
            "-flto",
            "--closure 1",
            "-sMINIFY_HTML=1",
            "-sUSE_GLFW=3",
            "-sASYNCIFY",
            // "-sINITIAL_MEMORY=167772160",
            "-sSTACK_SIZE=16777216",
            // "-sALLOW_MEMORY_GROWTH=1",
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
            exe_lib,
        };
        for (link_items) |item| {
            emcc_command.addFileArg(item.getEmittedBin());
            emcc_command.step.dependOn(&item.step);
        }

        const install = emcc_command;
        b.default_step.dependOn(&install.step);

        // Benchmark HTML output for WebAssembly build
        const benchmark_lib = b.addStaticLibrary(.{
            .name = "yazbg-benchmark",
            .root_source_file = b.path("src/benchmark.zig"),
            .target = wasm_target,
            .optimize = optimize,
            .link_libc = true,
        });
        benchmark_lib.shared_memory = false;
        benchmark_lib.root_module.single_threaded = true;
        benchmark_lib.root_module.addImport("ecs", ecs_dep.module("zig-ecs"));
        benchmark_lib.linkLibrary(raylib_artifact);
        benchmark_lib.addIncludePath(raylib_dep.path("src"));
        benchmark_lib.addIncludePath(.{ .cwd_relative = sysroot_include });

        const emcc_benchmark = b.addSystemCommand(&[_][]const u8{emcc_exe_path});
        emcc_benchmark.addArgs(&[_][]const u8{
            "-o",
            "zig-out/web/yazbg-benchmark.html",
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
    } else {
        const exe = b.addExecutable(.{
            .name = "yazbg",
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .omit_frame_pointer = false, // keep frame pointer
        });
        exe.root_module.strip = strip;
        exe.linkLibrary(raylib_artifact);

        const ecs_dep = b.dependency("entt", .{
            .target = target,
            .optimize = optimize,
        });
        exe.root_module.addImport("ecs", ecs_dep.module("zig-ecs"));

        b.installArtifact(exe);

        const run_cmd = b.addRunArtifact(exe);
        run_cmd.step.dependOn(b.getInstallStep());
        if (b.args) |args| {
            run_cmd.addArgs(args);
        }

        const run_step = b.step("run", "Run the app");
        run_step.dependOn(&run_cmd.step);

        // Benchmark executable
        const benchmark_exe = b.addExecutable(.{
            .name = "yazbg-benchmark",
            .root_source_file = b.path("src/benchmark.zig"),
            .target = target,
            .optimize = optimize,
            .omit_frame_pointer = false, // keep frame pointer
        });
        benchmark_exe.root_module.strip = strip;
        benchmark_exe.linkLibrary(raylib_artifact);
        benchmark_exe.root_module.addImport("ecs", ecs_dep.module("zig-ecs"));

        b.installArtifact(benchmark_exe);

        const run_benchmark = b.addRunArtifact(benchmark_exe);
        run_benchmark.step.dependOn(b.getInstallStep());
        if (b.args) |args| {
            run_benchmark.addArgs(args);
        }

        const benchmark_step = b.step("benchmark", "Run the animation/render benchmark");
        benchmark_step.dependOn(&run_benchmark.step);

        const unit_tests = b.addTest(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        });

        const run_unit_tests = b.addRunArtifact(unit_tests);
        const test_step = b.step("test", "Run unit tests");
        test_step.dependOn(&run_unit_tests.step);
    }
}
