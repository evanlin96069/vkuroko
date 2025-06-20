const std = @import("std");
const builtin = @import("builtin");
const testing = std.testing;

const utils = @import("utils.zig");

const isHex = utils.isHex;
const makeHex = utils.makeHex;

pub fn makePattern(comptime str: []const u8) []const ?u8 {
    return comptime blk: {
        @setEvalBranchQuota(10000);
        var it = std.mem.splitSequence(u8, str, " ");
        var pat: []const ?u8 = &.{};

        while (it.next()) |byte| {
            if (byte.len != 2) {
                @compileError("Each byte should be 2 characters");
            }
            if (byte[0] == '?') {
                if (byte[1] != '?') {
                    @compileError("The second question mark is missing");
                }
                pat = pat ++ .{null};
            } else if (isHex(byte[0])) {
                if (!isHex(byte[1])) {
                    @compileError("The second hex digit is missing");
                }
                const n = try std.fmt.parseInt(u8, byte, 16);
                pat = pat ++ .{n};
            } else {
                @compileError("Only hex digits, spaces and question marks are allowed");
            }
        }
        break :blk pat;
    };
}

pub fn makePatterns(comptime arr: anytype) []const []const ?u8 {
    return comptime blk: {
        var patterns: []const []const ?u8 = &.{};
        for (arr) |str| {
            const pat: []const []const ?u8 = &.{makePattern(str)};
            patterns = patterns ++ pat;
        }
        break :blk patterns;
    };
}

pub fn scanFirst(mem: []const u8, pattern: []const ?u8) ?usize {
    if (mem.len < pattern.len) {
        return null;
    }

    var offset: usize = 0;
    outer: while (offset < mem.len - pattern.len + 1) : (offset += 1) {
        for (pattern, 0..) |byte, j| {
            if (byte) |b| {
                if (b != mem[offset + j]) {
                    continue :outer;
                }
            }
        }
        return offset;
    }

    return null;
}

pub fn scanUnique(mem: []const u8, pattern: []const ?u8) ?usize {
    if (scanFirst(mem, pattern)) |offset| {
        if (scanFirst(mem[offset + pattern.len ..], pattern) != null) {
            return null;
        }
        return offset;
    }

    return null;
}

pub const MatchedPattern = struct {
    index: usize,
    ptr: [*]const u8,
};

pub fn scanAllPatterns(mem: []const u8, patterns: []const []const ?u8, data: *std.ArrayList(MatchedPattern)) !void {
    for (patterns, 0..) |pattern, i| {
        var base: usize = 0;
        while (scanFirst(mem[base..], pattern)) |offset| {
            try data.append(MatchedPattern{
                .index = i,
                .ptr = mem.ptr + base + offset,
            });
            base += offset + pattern.len;
        }
    }
}

pub fn scanUniquePatterns(mem: []const u8, patterns: []const []const ?u8) ?MatchedPattern {
    var match: ?MatchedPattern = null;
    for (patterns, 0..) |pattern, i| {
        if (scanFirst(mem, pattern)) |offset| {
            if (scanFirst(mem[offset + pattern.len ..], pattern) != null) {
                return null;
            }

            if (match != null) {
                return null;
            }

            match = .{
                .index = i,
                .ptr = mem.ptr + offset,
            };
        }
    }

    return match;
}

test "Scan first pattern" {
    const mem = makeHex("F6 05 12 34 56 78 12");

    // Match at the start
    const test_pattern1 = makePattern("F6 05 12");
    const result1 = scanFirst(mem, test_pattern1);
    try testing.expect(result1 != null);
    if (result1) |offset| {
        try testing.expectEqual(0, offset);
    }

    // Match at the middle
    const test_pattern2 = makePattern("12 34 56");
    const result2 = scanFirst(mem, test_pattern2);
    try testing.expect(result2 != null);
    if (result2) |offset| {
        try testing.expectEqual(2, offset);
    }

    // Match at the end
    const test_pattern3 = makePattern("56 78 12");
    const result3 = scanFirst(mem, test_pattern3);
    try testing.expect(result3 != null);
    if (result3) |offset| {
        try testing.expectEqual(4, offset);
    }
}

test "Scan unique patterns" {
    const mem = makeHex("F6 05 12 34 56 78 12");
    const test_patterns = makePatterns(.{
        "00 00 ?? ?? 12",
        "12 ?? 56",
        "F6 05 00 34",
    });

    const result = scanUniquePatterns(mem, test_patterns);
    try testing.expect(result != null);
    if (result) |r| {
        try testing.expectEqual(1, r.index);
        try testing.expectEqual(mem.ptr + 2, r.ptr);
    }
}

test "Scan unique patterns with multiple matches" {
    const mem = makeHex("12 34 56 12 34 56 78 9A BC DE");

    const test_patterns1 = makePatterns(.{
        "12 34 56", // Non-unique match
    });
    try testing.expect(scanUniquePatterns(mem, test_patterns1) == null);

    const test_patterns2 = makePatterns(.{
        "12 ?? ?? 12", // Unique match
        "9A BC DE", // Unique match
    });
    try testing.expect(scanUniquePatterns(mem, test_patterns2) == null);

    const test_patterns3 = makePatterns(.{
        "12 34 56", // Non-unique match
        "9A BC DE", // Unique match
    });
    try testing.expect(scanUniquePatterns(mem, test_patterns3) == null);
}

pub fn loadValue(T: type, ptr: [*]const u8) T {
    const val: *align(1) const T = @ptrCast(ptr);
    return val.*;
}

pub fn setValue(T: type, ptr: [*]u8, value: T) void {
    const val: *align(1) T = @ptrCast(ptr);
    val.* = value;
}

test "Load value from memory" {
    const mem = makeHex("E9 B1 9A 78 56"); // jmp
    try testing.expectEqual(0x56789AB1, loadValue(u32, mem.ptr + 1));
}
