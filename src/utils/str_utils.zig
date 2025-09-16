const std = @import("std");

// I think std.bufPrintZ doesn't always null-terminate when running out of space, so we have these string utils.

// Copy buffer, always null-terminated.
pub fn copyToBufferZ(comptime T: type, dest: []T, src: []const T) void {
    if (dest.len == 0) {
        return;
    }

    const max_copy_len = dest.len - 1;
    const copy_len = @min(max_copy_len, src.len);
    @memcpy(dest[0..copy_len], src[0..copy_len]);
    dest[copy_len] = 0;
}

// Concat buffers, always null-terminated.
pub fn concatToBufferZ(comptime T: type, dest: []T, slices: []const []const T) void {
    if (dest.len == 0) {
        return;
    }

    var pos: usize = 0;
    for (slices) |slice| {
        if (pos >= dest.len - 1) {
            break;
        }

        const max_copy_len = dest.len - 1 - pos;
        const copy_len = @min(max_copy_len, slice.len);
        @memcpy(dest[pos .. pos + copy_len], slice[0..copy_len]);
        pos += copy_len;
    }

    dest[pos] = 0;
}

pub fn stringLessThan(_: void, lhs: []const u8, rhs: []const u8) bool {
    return std.mem.order(u8, lhs, rhs) == .lt;
}
