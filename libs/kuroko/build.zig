const std = @import("std");

pub fn module(b: *std.Build, dir: []const u8) *std.Build.Module {
    return b.createModule(.{
        .root_source_file = b.path(b.fmt("{s}/kuroko.zig", .{dir})),
    });
}

pub fn link(
    b: *std.Build,
    dir: []const u8,
    step: *std.Build.Step.Compile,
    optimize: std.builtin.OptimizeMode,
    target: std.Build.ResolvedTarget,
) void {
    const src_path = b.fmt("{s}/src", .{dir});

    const lib = b.addStaticLibrary(.{
        .name = "kuroko",
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path(b.fmt("{s}/root.zig", .{src_path})),
    });

    lib.addIncludePath(b.path(src_path));

    lib.addCSourceFiles(.{
        .root = b.path(src_path),
        .files = &.{
            "modules/module_dis.c",
            "modules/module_fileio.c",
            "modules/module_gc.c",
            "modules/module_locale.c",
            "modules/module_math.c",
            "modules/module_os.c",
            "modules/module_random.c",
            // "modules/module_socket.c",
            "modules/module_stat.c",
            "modules/module_time.c",
            "modules/module_timeit.c",
            "modules/module_wcwidth.c",
            "modules/module__pheap.c",
            "builtins.c",
            "chunk.c",
            "compiler.c",
            "debug.c",
            "exceptions.c",
            "memory.c",
            "modules.c",
            "object.c",
            "obj_base.c",
            "obj_bytes.c",
            "obj_dict.c",
            "obj_function.c",
            "obj_gen.c",
            "obj_list.c",
            "obj_long.c",
            "obj_numeric.c",
            "obj_range.c",
            "obj_set.c",
            "obj_slice.c",
            "obj_str.c",
            "obj_tuple.c",
            "obj_typing.c",
            "parseargs.c",
            "scanner.c",
            "sys.c",
            "table.c",
            "threads.c",
            "value.c",
            "vm.c",
            "io.c",
            "libtime.c",
        },
        .flags = &.{
            "-DKRK_BUILD_DATE=\"Feb 27 2025\"", // Date of commit 0ae991c68e0dd58bd12d1f05172bc07c1454a439
            "-DKRK_BUNDLE_LIBS",
            "-DKRK_DISABLE_THREADS",
        },
    });

    lib.linkLibC();

    step.linkLibrary(lib);
}
