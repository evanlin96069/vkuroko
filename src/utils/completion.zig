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
    while (partial[pos] != ' ') {
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
    ) c_int {
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

        while (partial[pos] != ' ') {
            pos += 1;
        }

        const arg1 = line[pos..];
        if (std.mem.containsAtLeast(u8, arg1, 1, " ")) {
            // Multiple arguments
            // TODO: Handle quoted argument
            return 0;
        }

        const end_pos = std.mem.lastIndexOf(u8, line, "/\\") orelse pos;
        const dir_name = line[pos..end_pos];

        var cached: bool = false;
        if (self.cached_directory) |s| {
            cached = std.mem.eql(u8, dir_name, s);
        }

        if (!cached) {
            self.clearCache();
            const path = std.fmt.allocPrint(core.allocator, "{s}/{s}", .{ engine.client.getGameDirectory(), dir_name }) catch {
                return 0;
            };
            self.cached_directory = path;

            var dir = std.fs.openDirAbsolute(path, .{ .iterate = true }) catch {
                return 0;
            };
            var walker = dir.walk(core.allocator) catch {
                return 0;
            };
            defer walker.deinit();
            while (walker.next() catch {
                return 0;
            }) |entry| {
                const name = entry.basename;
                switch (entry.kind) {
                    .directory => {
                        if (std.mem.eql(u8, name, ".") or std.mem.eql(u8, name, "..")) {
                            continue;
                        }
                        const s = std.fmt.allocPrint(core.allocator, "{s}/", .{name}) catch continue;
                        self.cache.append(s) catch continue;
                    },
                    .file => {
                        if (std.mem.endsWith(u8, name, self.file_extension)) {
                            continue;
                        }
                        const dot = std.mem.lastIndexOf(u8, name, ".") orelse continue;
                        const s = core.allocator.dupe(u8, name[0..dot]) catch continue;
                        self.cache.append(s) catch continue;
                    },
                    else => {},
                }
            }
        }

        return simpleComplete(line[0..end_pos], self.cache.items, partial, commands);
    }
};
