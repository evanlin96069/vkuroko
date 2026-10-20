const std = @import("std");

const Feature = @import("Feature.zig");

const datamap = @import("datamap.zig");

const core = @import("../core.zig");

const modules = @import("../modules.zig");
const tier1 = modules.tier1;
const engine = modules.engine;
const server = modules.server;
const client = modules.client;
const ConCommand = tier1.ConCommand;

const sdk = @import("sdk");
const CBaseHandle = sdk.CBaseHandle;
const IServerEntity = sdk.IServerEntity;
const IClientEntity = sdk.IClientEntity;
const Vector = sdk.Vector;
const QAngle = sdk.QAngle;
const VMatrix = sdk.VMatrix;

const game_detection = @import("../utils/game_detection.zig");

pub var feature: Feature = .{
    .name = "entity list",
    .shouldLoad = shouldLoad,
    .init = init,
    .deinit = deinit,
};

pub const PortalInfo = struct {
    ent: ?*anyopaque = null,
    handle: CBaseHandle = .{},
    linked_handle: CBaseHandle = .{},
    pos: Vector = .{},
    ang: QAngle = .{},
    is_orange: bool = false,
    is_activated: bool = false,
    is_open: bool = false,
    linkage_id: u8 = 0,
    matrix_this_to_linked: VMatrix = std.mem.zeroes(VMatrix),
};

fn EntityList(comptime is_server: bool) type {
    return struct {
        const Self = @This();
        const EntType = if (is_server) *IServerEntity else *IClientEntity;

        allocator: std.mem.Allocator,
        ent_list: std.ArrayList(EntType),
        portal_list: std.ArrayList(PortalInfo),
        last_update: c_int = -1,

        pub fn init(alloc: std.mem.Allocator) Self {
            return .{
                .allocator = alloc,
                .ent_list = .empty,
                .portal_list = .empty,
            };
        }

        pub fn deinit(self: *Self) void {
            self.ent_list.deinit(self.allocator);
            self.portal_list.deinit(self.allocator);
        }

        pub fn checkRebuildLists(self: *Self) !void {
            const new_tick = engine.tool.hostFrameTime();
            if (new_tick == self.last_update) return;
            self.last_update = new_tick;

            self.ent_list.clearRetainingCapacity();
            self.portal_list.clearRetainingCapacity();

            if (!self.isValid()) return;

            if (is_server) {
                var i: u32 = 0;
                while (i < sdk.NUM_ENT_ENTRIES) : (i += 1) {
                    if (self.getEntity(i)) |ent| {
                        try self.ent_list.append(self.allocator, ent);
                        if (self.entityIsPortal(ent)) {
                            try self.portal_list.append(self.allocator, self.getPortalInfo(ent));
                        }
                    }
                }
            } else {
                const max_ent = client.entlist.getHighestEntityIndex() orelse {
                    // No entities
                    return;
                };

                var i: u32 = 0;
                while (i < max_ent) : (i += 1) {
                    if (self.getEntity(i)) |ent| {
                        try self.ent_list.append(self.allocator, ent);
                        if (self.entityIsPortal(ent)) {
                            try self.portal_list.append(self.allocator, self.getPortalInfo(ent));
                        }
                    }
                }
            }
        }

        pub fn getEntityList(self: *Self) !*std.ArrayList(EntType) {
            try self.checkRebuildLists();
            return &self.ent_list;
        }

        pub fn getPortalList(self: *Self) !*std.ArrayList(PortalInfo) {
            try self.checkRebuildLists();
            return &self.portal_list;
        }

        pub fn getEntity(self: *const Self, index: u32) ?EntType {
            _ = self;
            if (is_server) {
                if (server.entlist.getEntInfoPtrByIndex(index)) |ent_info| {
                    return ent_info.entity;
                }
                return null;
            } else {
                return client.entlist.getClientEntity(@intCast(index));
            }
        }

        pub fn getClassName(self: *const Self, ent: EntType) [*:0]const u8 {
            if (!is_server) {
                return self.getNetworkClassName(ent);
            }

            const map = ent.getDataDescMap();

            // Datamap pattern scan might miss some maps. Add them if we found a new one.
            datamap.ensureEntityMaps(is_server, map) catch |err| {
                core.log.debug("Failed to add datamap {s}: {t}", .{ map.data_class_name, err });
            };

            return map.data_class_name;
        }

        pub fn getNetworkClassName(self: *const Self, ent: EntType) [*:0]const u8 {
            _ = self;
            if (is_server) {
                const S = struct {
                    var f_class: datamap.CachedField(.{
                        .T = ?*sdk.ServerClass,
                        .map = "CBaseEntity",
                        .field = "m_Network.m_hParent",
                        .is_server = true,
                        .additional_offset = -@sizeOf(CBaseHandle),
                    }) = .{};
                };

                if (S.f_class.getPtr(ent)) |class_ptr_ptr| {
                    if (class_ptr_ptr.*) |class_ptr| {
                        return class_ptr.getName();
                    }
                }
                return "";
            } else {
                return ent.getClientClass().getName();
            }
        }

        pub fn getPlayer(self: *const Self) ?EntType {
            return self.getEntity(1);
        }

        pub fn entityIsPortal(self: *const Self, ent: EntType) bool {
            return std.mem.eql(u8, std.mem.span(self.getClassName(ent)), "CProp_Portal");
        }

        pub fn isValid(self: *const Self) bool {
            return self.getEntity(0) != null;
        }

        pub fn getPortalInfo(self: *const Self, ent: EntType) PortalInfo {
            std.debug.assert(self.entityIsPortal(ent));

            if (is_server) {
                const S = struct {
                    var fields = datamap.CachedFields(.{
                        .{ Vector, "CProp_Portal", "m_vecAbsOrigin", true },
                        .{ QAngle, "CProp_Portal", "m_angAbsRotation", true },
                        .{ CBaseHandle, "CProp_Portal", "m_hLinkedPortal", true },
                        .{ bool, "CProp_Portal", "m_bIsPortal2", true },
                        .{ bool, "CProp_Portal", "m_bActivated", true },
                        .{ u8, "CProp_Portal", "m_iLinkageGroupID", true },
                        .{ VMatrix, "CProp_Portal", "m_matrixThisToLinked", true },
                    }){};
                };
                if (!S.fields.hasAll()) {
                    return .{};
                }

                const pos, const ang, const linked, const p2, const activated, const linkage_id, const mat = S.fields.getAllPtrs(ent);

                return .{
                    .ent = ent,
                    .handle = ent.getRefEHandle().*,
                    .linked_handle = linked.?.*,
                    .pos = pos.?.*,
                    .ang = ang.?.*,
                    .is_orange = p2.?.*,
                    .is_activated = activated.?.*,
                    .is_open = linked.?.isValid(),
                    .linkage_id = linkage_id.?.*,
                    .matrix_this_to_linked = mat.?.*,
                };
            } else {
                // TODO: Implement client portal
                return .{};
            }
        }
    };
}

pub var server_list = EntityList(true).init(core.allocator);
pub var client_list = EntityList(false).init(core.allocator);

var vkrk_print_portals = ConCommand.init(.{
    .name = "vkrk_print_portals",
    .help_string = "Prints all portals.",
    .command_callback = print_portals_Fn,
});

fn print_portals_Fn(args: *const tier1.CCommand) callconv(.c) void {
    _ = args;

    if (!server_list.isValid()) {
        std.log.info("Cannot find server", .{});
        return;
    }

    const portals = server_list.getPortalList() catch return;
    if (portals.items.len == 0) {
        std.log.info("No portals", .{});
        return;
    }

    for (portals.items) |portal| {
        std.log.info(
            \\[{d}] {s} {s} portal
            \\    pos: {d:.9} {d:.9} {d:.9}
            \\    ang: {d:.9} {d:.9} {d:.9}
            \\    linkage id: {d}
            \\    linked portal: {d}
        ,
            .{
                portal.handle.getEntryIndex(),
                if (portal.linked_handle.isValid()) "open" else if (portal.is_activated) "closed" else "invisible",
                if (portal.is_orange) "orange" else "blue",
                portal.pos.x,
                portal.pos.y,
                portal.pos.z,
                portal.ang.x,
                portal.ang.y,
                portal.ang.z,
                portal.linkage_id,
                if (portal.linked_handle.isValid())
                    @as(i32, @intCast(portal.linked_handle.getEntryIndex()))
                else
                    -1,
            },
        );
    }
}

var vkrk_print_ents = ConCommand.init(.{
    .name = "vkrk_print_ents",
    .help_string = "Prints all entities.",
    .command_callback = print_ents_Fn,
});

fn print_ents_Fn(args: *const tier1.CCommand) callconv(.c) void {
    _ = args;

    var found_entity = false;
    var index: u32 = 0;
    while (index < sdk.NUM_ENT_ENTRIES) : (index += 1) {
        const server_ent = server_list.getEntity(index);
        const client_ent = if (index < sdk.MAX_EDICTS)
            client_list.getEntity(index)
        else
            null;

        if (server_ent) |s_ent| {
            found_entity = true;
            if (client_ent) |c_ent| {
                std.log.info(
                    "[ {d: >3}] SERVER (serial {d: >5}) : {s}, CLIENT (serial {d: >5}) : {s}",
                    .{
                        index,
                        s_ent.getRefEHandle().getSerialNumber(),
                        server_list.getClassName(s_ent),
                        c_ent.getRefEHandle().getSerialNumber(),
                        client_list.getClassName(c_ent),
                    },
                );
            } else {
                std.log.info(
                    "[ {d: >3}] SERVER (serial {d: >5}) : {s}",
                    .{ index, s_ent.getRefEHandle().getSerialNumber(), server_list.getClassName(s_ent) },
                );
            }
        } else if (client_ent) |c_ent| {
            found_entity = true;
            std.log.info(
                "[ {d: >3}] CLIENT (serial {d: >5}) : {s}",
                .{ index, c_ent.getRefEHandle().getSerialNumber(), client_list.getClassName(c_ent) },
            );
        }
    }

    if (!found_entity) {
        std.log.info("No entities", .{});
    }
}

fn shouldLoad() bool {
    return datamap.feature.loaded;
}

fn init() bool {
    if (game_detection.doesGameLooksLikePortal()) {
        vkrk_print_portals.register();
    }
    vkrk_print_ents.register();
    return true;
}

fn deinit() void {
    server_list.deinit();
    client_list.deinit();
}
