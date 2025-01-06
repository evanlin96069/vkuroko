const std = @import("std");
const windows = std.os.windows;

const DynLib = @This();

dll: windows.HMODULE = undefined,

pub fn open(comptime path: []const u8) !DynLib {
    const dll = try windows.LoadLibraryW(std.unicode.utf8ToUtf16LeStringLiteral(path));
    return .{
        .dll = dll,
    };
}

pub fn close(self: *DynLib) void {
    windows.FreeLibrary(self.dll);
    self.* = undefined;
}

pub fn lookup(self: *DynLib, comptime T: type, name: [:0]const u8) ?T {
    if (windows.kernel32.GetProcAddress(self.dll, name.ptr)) |addr| {
        return @as(T, @ptrCast(@alignCast(addr)));
    } else {
        return null;
    }
}
