const std = @import("std");

const str_utils = @import("str_utils.zig");

const core = @import("../core.zig");
const modules = @import("../modules.zig");
const tier1 = modules.tier1;
const ConCommand = tier1.ConCommand;
const engine = modules.engine;

const max_items = ConCommand.completion_max_items;
const max_length = ConCommand.completion_item_length;

pub fn simpleComplete(
    base: []const u8,
    completions: []const []const u8,
    partial: [*:0]const u8,
    commands: *[max_items][max_length]u8,
) c_int {
    const line = std.mem.span(partial);
    if (!std.mem.startsWith(u8, line, base)) {
        return 0;
    }

    var pos = base.len;
    while (partial[pos] == ' ') {
        pos += 1;
    }

    var count: u8 = 0;
    for (completions) |completion| {
        if (std.mem.startsWith(u8, completion, line[pos..])) {
            str_utils.concatToBufferZ(
                u8,
                &commands[count],
                &[_][]const u8{
                    partial[0..pos],
                    completion,
                },
            );

            count += 1;
            if (count >= max_items) {
                break;
            }
        }
    }

    return @intCast(count);
}

pub const FileCompletion = struct {
    command: []const u8,
    base_path: []const u8,
    file_extension: []const u8,
    cache: std.ArrayList([]const u8),
    cached_directory: ?[]const u8,

    registered: bool = false,
    next: ?*FileCompletion = null,

    var list: ?*FileCompletion = null;

    pub fn init(
        command: []const u8,
        base_path: []const u8,
        file_extension: []const u8,
    ) FileCompletion {
        return .{
            .command = command,
            .base_path = base_path,
            .file_extension = file_extension,
            .cache = std.ArrayList([]const u8).init(core.allocator),
            .cached_directory = null,
        };
    }

    fn deinit(self: *FileCompletion) void {
        self.clearCache();
        self.cache.deinit();
    }

    fn register(self: *FileCompletion) void {
        self.next = FileCompletion.list;
        FileCompletion.list = self;
        self.registered = true;
    }

    fn clearCache(self: *FileCompletion) void {
        if (self.cached_directory) |dir| {
            core.allocator.free(dir);
            self.cached_directory = null;
        }

        for (self.cache.items) |s| {
            core.allocator.free(s);
        }

        self.cache.clearRetainingCapacity();
    }

    pub fn deinitAll() void {
        var it = FileCompletion.list;
        while (it) |completion| : (it = completion.next) {
            completion.deinit();
        }
    }

    pub fn complete(
        self: *FileCompletion,
        partial: [*:0]const u8,
        commands: *[max_items][max_length]u8,
    ) !c_int {
        if (!self.registered) {
            // I think just by calling init on ArrayList won't allocate memory, so we only register the one we used.
            self.register();
        }

        const line = std.mem.span(partial);
        if (!std.mem.startsWith(u8, line, self.command)) {
            return 0;
        }

        var pos = self.command.len;
        if (partial[pos] != ' ') {
            return 0;
        }

        while (partial[pos] == ' ') {
            pos += 1;
        }

        const arg1 = line[pos..];
        if (std.mem.containsAtLeast(u8, arg1, 1, " ")) {
            // Multiple arguments
            // TODO: Handle quoted argument
            return 0;
        }

        const slash_pos = std.mem.lastIndexOf(u8, line, "/");
        var end_pos = slash_pos orelse pos;
        const dir_name = line[pos..end_pos];

        if (slash_pos != null) {
            end_pos += 1;
        }

        var cached: bool = false;
        if (self.cached_directory) |s| {
            cached = std.mem.eql(u8, dir_name, s);
        }

        if (!cached) {
            self.clearCache();
            self.cached_directory = try core.allocator.dupe(u8, dir_name);

            const path = try std.fmt.allocPrint(
                core.allocator,
                "{s}/{s}{s}{s}/*.*",
                .{
                    engine.client.getGameDirectory(),
                    self.base_path,
                    if (dir_name.len == 0) "" else "/",
                    dir_name,
                },
            );
            defer core.allocator.free(path);

            // Using std.fs.cwd().openDir Keeps getting me stack overflow so I just use Windows API calls.
            const w_path = try std.unicode.utf8ToUtf16LeAllocZ(core.allocator, path);
            defer core.allocator.free(w_path);

            var fd: std.os.windows.WIN32_FIND_DATAW = undefined;
            const h_find = std.os.windows.kernel32.FindFirstFileW(w_path, &fd);
            if (h_find == std.os.windows.INVALID_HANDLE_VALUE) {
                return 0;
            }
            defer std.os.windows.FindClose(h_find);

            while (true) {
                const len = std.mem.indexOf(u16, &fd.cFileName, &[_]u16{0}).?;
                const name = try std.unicode.utf16LeToUtf8Alloc(core.allocator, fd.cFileName[0..len]);
                defer core.allocator.free(name);

                if (fd.dwFileAttributes & std.os.windows.FILE_ATTRIBUTE_DIRECTORY != 0) {
                    if (!std.mem.eql(u8, name, ".") and !std.mem.eql(u8, name, "..")) {
                        const s = try std.fmt.allocPrint(core.allocator, "{s}/", .{name});
                        errdefer core.allocator.free(s);
                        try self.cache.append(s);
                    }
                } else {
                    if (std.mem.endsWith(u8, name, self.file_extension)) {
                        const dot = std.mem.lastIndexOf(u8, name, ".") orelse continue;
                        const s = try core.allocator.dupe(u8, name[0..dot]);
                        errdefer core.allocator.free(s);
                        try self.cache.append(s);
                    }
                }

                if (std.os.windows.kernel32.FindNextFileW(h_find, &fd) == std.os.windows.FALSE) {
                    break;
                }
            }
        }

        return simpleComplete(line[0..end_pos], self.cache.items, partial, commands);
    }
};
