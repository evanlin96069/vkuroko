const std = @import("std");

const Feature = @import("Feature.zig");

const datamap = @import("datamap.zig");

const core = @import("../core.zig");

const modules = @import("../modules.zig");
const tier1 = modules.tier1;
const engine = modules.engine;
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

        ent_list: std.ArrayList(EntType),
        portal_list: std.ArrayList(PortalInfo),
        last_update: c_int = -1,

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .ent_list = std.ArrayList(EntType).init(allocator),
                .portal_list = std.ArrayList(PortalInfo).init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            self.ent_list.deinit();
            self.portal_list.deinit();
        }

        pub fn checkRebuildLists(self: *Self) !void {
            const new_tick = engine.tool.hostFrameTime();
            if (new_tick == self.last_update) return;
            self.last_update = new_tick;

            self.ent_list.clearRetainingCapacity();
            self.portal_list.clearRetainingCapacity();

            if (!self.isValid()) return;

            if (is_server) {
                const max_ent = engine.server.getEntityCount();
                var i: u32 = 0;
                while (self.ent_list.items.len < max_ent and i < sdk.MAX_EDICTS) : (i += 1) {
                    if (self.getEntity(i)) |ent| {
                        try self.ent_list.append(ent);
                        if (self.entityIsPortal(ent)) {
                            try self.portal_list.append(self.getPortalInfo(ent));
                        }
                    }
                }
            } else {
                const max_ent = client.entlist.getHighestEntityIndex();
                var i: u32 = 0;
                while (i < max_ent) : (i += 1) {
                    if (self.getEntity(i)) |ent| {
                        try self.ent_list.append(ent);
                        if (self.entityIsPortal(ent)) {
                            try self.portal_list.append(self.getPortalInfo(ent));
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
                if (engine.server.pEntityOfEntIndex(@intCast(index))) |ed| {
                    return ed.getIServerEntity();
                }
                return null;
            } else {
                return client.entlist.getClientEntity(@intCast(index));
            }
        }

        pub fn getNetworkClassName(self: *const Self, ent: EntType) [*:0]const u8 {
            _ = self;
            if (is_server) {
                const S = struct {
                    var f_class: datamap.CachedField(.{
                        .T = ?*sdk.ServerClass,
                        .map = "CBaseEntity",
                        .field = "CBaseEntity::m_Network.CServerNetworkProperty::m_hParent",
                        .is_server = true,
                        .additional_offset = -@sizeOf(CBaseHandle),
                    }) = .{};
                };

                if (S.f_class.getPtr(ent)) |class_ptr_ptr| {
                    if (class_ptr_ptr.*) |class_ptr| {
                        return class_ptr.getName();
                    }
                    std.log.info("ServerClass is null", .{});
                } else {
                    std.log.info("Cannot find ServerClass", .{});
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
            return std.mem.eql(u8, std.mem.span(self.getNetworkClassName(ent)), "CProp_Portal");
        }

        pub fn isValid(self: *const Self) bool {
            return self.getEntity(0) != null;
        }

        pub fn getPortalInfo(self: *const Self, ent: EntType) PortalInfo {
            std.debug.assert(self.entityIsPortal(ent));

            if (is_server) {
                const S = struct {
                    var fields = datamap.CachedFields(.{
                        .{ Vector, "CProp_Portal", "CBaseEntity::m_vecAbsOrigin", true },
                        .{ QAngle, "CProp_Portal", "CBaseEntity::m_angAbsRotation", true },
                        .{ CBaseHandle, "CProp_Portal", "CProp_Portal::m_hLinkedPortal", true },
                        .{ bool, "CProp_Portal", "CProp_Portal::m_bIsPortal2", true },
                        .{ bool, "CProp_Portal", "CProp_Portal::m_bActivated", true },
                        .{ u8, "CProp_Portal", "CProp_Portal::m_iLinkageGroupID", true },
                        .{ VMatrix, "CProp_Portal", "CProp_Portal::m_matrixThisToLinked", true },
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

fn print_portals_Fn(args: *const tier1.CCommand) callconv(.C) void {
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
                if (portal.linked_handle.isValid()) portal.linked_handle.getEntryIndex() else -1,
            },
        );
    }
}

var vkrk_print_ents = ConCommand.init(.{
    .name = "vkrk_print_ents",
    .help_string = "Prints all entities.",
    .command_callback = print_ents_Fn,
});

fn print_ents_Fn(args: *const tier1.CCommand) callconv(.C) void {
    _ = args;

    if (server_list.isValid()) {
        const ents = server_list.getEntityList() catch return;
        for (ents.items) |ent| {
            std.log.info("{d}: {s}", .{ ent.getRefEHandle().getEntryIndex(), server_list.getNetworkClassName(ent) });
        }
    } else if (client_list.isValid()) {
        const ents = client_list.getEntityList() catch return;
        for (ents.items) |ent| {
            std.log.info("{d}: {s}", .{ ent.getRefEHandle().getEntryIndex(), client_list.getNetworkClassName(ent) });
        }
    } else {
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
