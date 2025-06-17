const std = @import("std");

const kuroko = @import("libs/kuroko/build.zig");

const Target = enum { linux, windows };

pub fn build(b: *std.Build) void {
    const target_option: ?Target = b.option(Target, "target", "The target to build vkuroko for");
    const target_query: std.Target.Query = std.Build.parseTargetQuery(if (target_option) |option| switch (option) {
        .linux => .{ .arch_os_abi = "x86-linux-gnu" },
        .windows => .{ .arch_os_abi = "x86-windows-gnu" },
    } else .{ .arch_os_abi = "x86-native-gnu" }) catch unreachable;
    const target = b.resolveTargetQuery(target_query);
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addSharedLibrary(.{
        .name = "vkuroko",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    lib.link_z_notext = true;

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

    if (target_option == .windows) {
        b.installArtifact(lib);
    } else {
        const install = b.addInstallArtifact(lib, .{ .dest_sub_path = "vkuroko.so" });
        b.getInstallStep().dependOn(&install.step);
    }
}
