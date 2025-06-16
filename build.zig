const std = @import("std");

const kuroko = @import("libs/kuroko/build.zig");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{
        .default_target = std.Target.Query.parse(.{
            .arch_os_abi = "x86-native-gnu",
        }) catch unreachable,
    });
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addSharedLibrary(.{
        .name = "vkuroko",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    lib.linkLibC();
    kuroko.link(b, "libs/kuroko", lib, std.builtin.OptimizeMode.ReleaseFast, target);

    const zhook = b.addModule("zhook", .{
        .root_source_file = b.path("libs/zhook/zhook.zig"),
    });
    lib.root_module.addImport("zhook", zhook);

    const sdk = b.addModule("sdk", .{
        .root_source_file = b.path("libs/sdk/sdk.zig"),
    });
    lib.root_module.addImport("sdk", sdk);

    lib.root_module.addImport("kuroko", kuroko.module(b, "libs/kuroko"));

    b.installArtifact(lib);
}
