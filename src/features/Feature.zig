name: []const u8,

shouldLoad: *const fn () bool,
init: *const fn () bool,
deinit: *const fn () void,

loaded: bool = false,

status: Status = .none,

const Status = enum {
    none,
    ok,
    failed,
    skipped,
};
