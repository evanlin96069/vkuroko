const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{
        .default_target = std.zig.CrossTarget.parse(.{
            .arch_os_abi = "x86-native-gnu",
        }) catch unreachable,
    });
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addSharedLibrary(.{
        .name = "mpt",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    lib.linkLibC();
    b.installArtifact(lib);
}
