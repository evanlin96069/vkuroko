const std = @import("std");

const vkrk = @import("kuroko.zig");

const game_detection = @import("../../utils/game_detection.zig");
const entlist = @import("../entlist.zig");
const playerio = @import("../playerio.zig");

const kuroko = @import("kuroko");
const VM = kuroko.KrkVM;
const KrkValue = kuroko.KrkValue;
const KrkString = kuroko.KrkString;
const KrkClass = kuroko.KrkClass;
const KrkInstance = kuroko.KrkInstance;
const KrkList = kuroko.KrkList;

const vkrk_types = @import("vkrk_types.zig");

pub const PlayerInfo = struct {
    var class: *KrkClass = undefined;

    pub fn create(player: *const playerio.PlayerInfo) KrkValue {
        const inst = KrkInstance.create(class);
        VM.push(inst.asValue());
        inst.fields.attachNamedValue("pos", vkrk_types.Vector.create(player.position));
        inst.fields.attachNamedValue("ang", vkrk_types.QAngle.create(player.angles));
        inst.fields.attachNamedValue("vel", vkrk_types.Vector.create(player.velocity));
        inst.fields.attachNamedValue("ducked", KrkValue.boolValue(player.ducked));
        inst.fields.attachNamedValue("grounded", KrkValue.boolValue(player.grounded));
        inst.fields.attachNamedValue("water_level", KrkValue.intValue(player.water_level));
        inst.fields.attachNamedValue("entity_friction", KrkValue.floatValue(player.entity_friction));
        return VM.pop();
    }
};

pub const PortalInfo = struct {
    var class: *KrkClass = undefined;

    pub fn create(portal: *const entlist.PortalInfo) KrkValue {
        const inst = KrkInstance.create(class);
        VM.push(inst.asValue());
        inst.fields.attachNamedValue("index", KrkValue.intValue(portal.handle.getEntryIndex()));
        inst.fields.attachNamedValue(
            "linked_index",
            if (portal.linked_handle.isValid())
                KrkValue.intValue(portal.linked_handle.getEntryIndex())
            else
                KrkValue.noneValue(),
        );

        inst.fields.attachNamedValue("pos", vkrk_types.Vector.create(portal.pos));
        inst.fields.attachNamedValue("ang", vkrk_types.QAngle.create(portal.ang));
        inst.fields.attachNamedValue("is_orange", KrkValue.boolValue(portal.is_orange));
        inst.fields.attachNamedValue("is_activated", KrkValue.boolValue(portal.is_activated));
        inst.fields.attachNamedValue("is_open", KrkValue.boolValue(portal.is_open));
        inst.fields.attachNamedValue("linkage_id", KrkValue.intValue(portal.linkage_id));
        inst.fields.attachNamedValue(
            "matrix_this_to_linked",
            if (portal.linked_handle.isValid())
                vkrk_types.VMatrix.create(&portal.matrix_this_to_linked)
            else
                KrkValue.noneValue(),
        );
        return VM.pop();
    }
};

pub fn bindAttributes(module: *KrkInstance) void {
    _ = VM.interpret(@embedFile("scripts/entity.krk"), vkrk.module_name);

    PlayerInfo.class = module.fields.get(KrkString.copyString("PlayerInfo").asValue()).?.asClass();
    PortalInfo.class = module.fields.get(KrkString.copyString("PortalInfo").asValue()).?.asClass();

    if (playerio.feature.loaded) {
        module.bindFunction("get_player", get_player).setDoc(
            \\@brief Gets the player information
            \\@arguments is_server
            \\@return player information, `None` if not available
        );
    }

    if (entlist.feature.loaded and game_detection.doesGameLooksLikePortal()) {
        module.bindFunction("get_portals", get_portals).setDoc(
            \\@brief Gets all information of all portals
            \\@arguments is_server
            \\@return list of portal information
        );
    }
}

fn get_player(argc: c_int, argv: [*]const KrkValue, has_kw: c_int) callconv(.C) KrkValue {
    var i_is_server: c_int = 1;
    if (!kuroko.parseArgs(
        "__init__",
        argc,
        argv,
        has_kw,
        "|p",
        &.{
            "is_server",
        },
        .{
            &i_is_server,
        },
    )) {
        return KrkValue.noneValue();
    }

    const is_server = (i_is_server != 0);

    var player_info: playerio.PlayerInfo = .{};

    if (is_server) {
        if (entlist.server_list.getPlayer()) |player| {
            player_info = playerio.getPlayerInfo(player, is_server);
        } else {
            return KrkValue.noneValue();
        }
    } else {
        if (entlist.client_list.getPlayer()) |player| {
            player_info = playerio.getPlayerInfo(player, is_server);
        } else {
            return KrkValue.noneValue();
        }
    }

    return PlayerInfo.create(&player_info);
}

fn get_portals(argc: c_int, argv: [*]const KrkValue, has_kw: c_int) callconv(.C) KrkValue {
    var i_is_server: c_int = 1;
    if (!kuroko.parseArgs(
        "__init__",
        argc,
        argv,
        has_kw,
        "|p",
        &.{
            "is_server",
        },
        .{
            &i_is_server,
        },
    )) {
        return KrkValue.noneValue();
    }

    const is_server = (i_is_server != 0);

    var portals: *std.ArrayList(entlist.PortalInfo) = undefined;
    if (is_server) {
        if (entlist.server_list.isValid()) {
            portals = entlist.server_list.getPortalList() catch return KrkValue.noneValue();
        } else {
            return KrkValue.noneValue();
        }
    } else {
        if (entlist.client_list.isValid()) {
            portals = entlist.client_list.getPortalList() catch return KrkValue.noneValue();
        } else {
            return KrkValue.noneValue();
        }
    }

    const list = KrkList.listOf(0, null, false);
    VM.push(list);
    for (portals.items) |*portal| {
        list.asList().append(PortalInfo.create(portal));
    }
    _ = VM.pop();
    return list;
}
