const std = @import("std");
const builtin = @import("builtin");

const kuroko = @import("libs/kuroko/build.zig");

const Target = enum { linux, windows };

const vkrk_version = std.SemanticVersion{ .major = 0, .minor = 1, .patch = 0 };

pub fn build(b: *std.Build) void {
    const target_option: Target = b.option(Target, "target", "The target to build vkuroko for") orelse
        switch (builtin.os.tag) {
            .linux => .linux,
            .windows => .windows,
            else => unreachable,
        };

    const target_query: std.Target.Query = std.Build.parseTargetQuery(switch (target_option) {
        .linux => .{ .arch_os_abi = "x86-linux-gnu" },
        .windows => .{ .arch_os_abi = "x86-windows-gnu" },
    }) catch unreachable;
    const target = b.resolveTargetQuery(target_query);
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addLibrary(.{
        .name = "vkuroko",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
        .linkage = .dynamic,
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

    const build_options = b.addOptions();
    const version_str = b.fmt("{d}.{d}.{d}", .{ vkrk_version.major, vkrk_version.minor, vkrk_version.patch });
    build_options.addOption([]const u8, "version_str", version_str);
    const build_options_module = build_options.createModule();

    lib.root_module.addImport("build_options", build_options_module);

    if (target_option == .windows) {
        b.installArtifact(lib);
    } else {
        const install = b.addInstallArtifact(lib, .{ .dest_sub_path = "vkuroko.so" });
        b.getInstallStep().dependOn(&install.step);
    }
}
