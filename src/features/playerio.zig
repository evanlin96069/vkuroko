const std = @import("std");

const Feature = @import("Feature.zig");

const datamap = @import("datamap.zig");
const texthud = @import("texthud.zig");

const event = @import("../event.zig");
const game_detection = @import("../utils/game_detection.zig");
const ent_utils = @import("../utils/ent_utils.zig");

const modules = @import("../modules.zig");
const tier1 = modules.tier1;
const ConVar = tier1.ConVar;
const engine = modules.engine;
const client = modules.client;
const server = modules.server;
const vgui = modules.vgui;

const sdk = @import("sdk");
const Vector = sdk.Vector;
const QAngle = sdk.QAngle;
const CUserCmd = sdk.CUserCmd;
const Trace = sdk.Trace;

pub const PlayerInfo = struct {
    position: Vector = .{},
    angles: QAngle = .{},
    velocity: Vector = .{},
    ducked: bool = false,
    grounded: bool = false,
    water_level: u8 = 0,
    entity_friction: f32 = 0.0,

    tick_time: f32 = 0.015,

    // ConVars
    accelerate: f32 = 0.0,
    airaccelerate: f32 = 0.0,
    friction: f32 = 0.0,
    maxspeed: f32 = 0.0,
    stopspeed: f32 = 0.0,

    wish_speed_cap: f32 = 0.0,
};

pub const PlayerField = struct {
    m_vecAbsOrigin: usize,
    m_vecAbsVelocity: usize,
    m_surfaceFriction: usize,
    m_flMaxspeed: usize,
    m_bDucked: usize,
    m_hGroundEntity: usize,
    m_nWaterLevel: usize,

    m_vecPreviouslyPredictedOrigin: usize = 0, // server-only
};

var server_player_field: PlayerField = undefined;
var client_player_field: PlayerField = undefined;

pub fn getPlayerField(is_server: bool) *const PlayerField {
    return if (is_server) &server_player_field else &client_player_field;
}

fn traceIsPlayerGrounded(server_player: *anyopaque, position: Vector, ducked: bool, velocity: Vector) bool {
    if (velocity.z > 140.0) {
        return false;
    }

    var bump_origin = position;
    if (ducked) {
        bump_origin.z -= 36;
    }
    var point = bump_origin;
    point.z -= 2;

    const mins: Vector = .{
        .x = -16,
        .y = -16,
        .z = if (ducked) 36 else 0,
    };
    const maxs: Vector = .{
        .x = 16,
        .y = 16,
        .z = 72,
    };

    server.gm.setMoveData();
    defer server.gm.unsetMoveData();

    var pm: Trace = undefined;
    const mask_playersolid = (0x1 | 0x4000 | 0x10000 | 0x2 | 0x2000000 | 0x8);
    const collision_group_player_movement = 8;

    server.gm.tracePlayerBBox(
        &bump_origin,
        &point,
        &mins,
        &maxs,
        mask_playersolid,
        collision_group_player_movement,
        &pm,
    );

    if (pm.ent != null and pm.plane.normal.z >= 0.7) {
        return true;
    }

    server.gm.tracePlayerBBoxForGround(
        &bump_origin,
        &point,
        &mins,
        &maxs,
        server_player,
        mask_playersolid,
        collision_group_player_movement,
        &pm,
    );

    if (pm.ent != null and pm.plane.normal.z >= 0.7) {
        return true;
    }

    return false;
}

pub fn getPlayerInfo(player: *anyopaque, is_server: bool) PlayerInfo {
    const player_field: *const PlayerField = getPlayerField(is_server);

    // Basic player info
    const position = datamap.getField(Vector, player, player_field.m_vecAbsOrigin).*;
    const angles = engine.client.getViewAngles();
    const velocity = datamap.getField(Vector, player, player_field.m_vecAbsVelocity).*;

    const ducked = datamap.getField(bool, player, player_field.m_bDucked).*;

    // Gournded
    const index_mask = ((1 << 11) - 1);
    var grounded = (datamap.getField(c_long, player, player_field.m_hGroundEntity).* & index_mask) != index_mask;
    if (is_server and server.canTracePlayerBBox()) {
        grounded = traceIsPlayerGrounded(player, position, ducked, velocity);
    }
    const water_level = datamap.getField(u8, player, player_field.m_nWaterLevel).*;

    // Entity friction
    var entity_friction = datamap.getField(f32, player, player_field.m_surfaceFriction).*;
    if (is_server) {
        const previously_predicted_origin = datamap.getField(Vector, player, player_field.m_vecPreviouslyPredictedOrigin).*;
        if (!Vector.eql(position, previously_predicted_origin)) {
            if (game_detection.doesGameLooksLikePortal()) {
                entity_friction = 1.0;
            }
            if (velocity.z <= 140.0) {
                if (grounded) {
                    entity_friction = 1.0;
                } else if (velocity.z > 0.0) {
                    entity_friction = 0.25;
                }
            }
        }
    }

    // ConVars
    const accelerate = sv_accelerate.getFloat();
    const airaccelerate = if (game_detection.doesGameLooksLikePortal()) 15 else sv_airaccelerate.getFloat();
    const friction = sv_friction.getFloat();
    var maxspeed = datamap.getField(f32, player, player_field.m_flMaxspeed).*;
    maxspeed = if (maxspeed > 0) @min(maxspeed, sv_maxspeed.getFloat()) else sv_maxspeed.getFloat();
    const stopspeed = sv_stopspeed.getFloat();

    const wish_speed_cap: f32 = if (game_detection.doesGameLooksLikePortal()) 60 else 30;

    return PlayerInfo{
        .position = position,
        .angles = angles,
        .velocity = velocity,
        .ducked = ducked,
        .grounded = grounded,
        .entity_friction = entity_friction,
        .water_level = water_level,

        .tick_time = 0.015,

        .accelerate = accelerate,
        .airaccelerate = airaccelerate,
        .friction = friction,
        .maxspeed = maxspeed,
        .stopspeed = stopspeed,

        .wish_speed_cap = wish_speed_cap,
    };
}

const PosTextHUD = struct {
    var cl_showpos: ?*ConVar = null;

    fn shouldDraw() bool {
        if (cl_showpos == null) {
            cl_showpos = tier1.icvar.findVar("cl_showpos");
        }

        if (cl_showpos) |v| {
            return v.getBool();
        }

        return false;
    }

    fn paint() void {
        var origin: Vector = client.mainViewOrigin.?().*;
        var angles: QAngle = client.mainViewAngles.?().*;
        var vel: Vector = .{};

        const player = ent_utils.getPlayer(false);
        if (player) |p| {
            vel = datamap.getField(Vector, p, client_player_field.m_vecAbsVelocity).*;
            if (cl_showpos.?.getInt() == 2) {
                origin = datamap.getField(Vector, p, client_player_field.m_vecAbsOrigin).*;
                angles = engine.client.getViewAngles();
            }
        }
        texthud.drawTextHUD("pos:  {d:.2} {d:.2} {d:.2}", .{ origin.x, origin.y, origin.z });
        texthud.drawTextHUD("ang:  {d:.2} {d:.2} {d:.2}", .{ angles.x, angles.y, angles.z });
        texthud.drawTextHUD("vel:  {d:.2}", .{vel.getlength2D()});
    }

    fn register() void {
        texthud.addHUDElement(.{
            .shouldDraw = shouldDraw,
            .paint = paint,
        });
    }
};

var vkrk_hud_vars = tier1.Variable.init(.{
    .name = "vkrk_hud_vars",
    .help_string = "Show player movement variables.",
    .default_value = "0",
});

const PlayerioTextHUD = struct {
    var player_info: PlayerInfo = .{};

    fn onCreateMove(is_server: bool, cmd: *CUserCmd) void {
        _ = cmd;
        const player = ent_utils.getPlayer(is_server) orelse return;
        player_info = getPlayerInfo(player, is_server);
    }

    fn shouldDraw() bool {
        return vkrk_hud_vars.getBool();
    }

    fn paint() void {
        texthud.drawTextHUD("ducked: {s}", .{if (player_info.ducked) "true" else "false"});
        texthud.drawTextHUD("grounded: {s}", .{if (player_info.grounded) "true" else "false"});
        texthud.drawTextHUD("entity friction: {d:.2}", .{player_info.entity_friction});
        texthud.drawTextHUD("water level: {d}", .{player_info.water_level});
        texthud.drawTextHUD("accelerate: {d:.2}", .{player_info.accelerate});
        texthud.drawTextHUD("airaccelerate: {d:.2}", .{player_info.airaccelerate});
        texthud.drawTextHUD("friction: {d:.2}", .{player_info.friction});
        texthud.drawTextHUD("maxspeed: {d:.2}", .{player_info.maxspeed});
        texthud.drawTextHUD("stopspeed: {d:.2}", .{player_info.stopspeed});
    }

    fn register() void {
        if (event.create_move.works) {
            event.create_move.connect(onCreateMove);
            vkrk_hud_vars.register();
            texthud.addHUDElement(.{
                .shouldDraw = shouldDraw,
                .paint = paint,
            });
        }
    }
};

pub var feature: Feature = .{
    .name = "playerio",
    .shouldLoad = shouldLoad,
    .init = init,
    .deinit = deinit,
};

var sv_friction: *ConVar = undefined;
var sv_maxspeed: *ConVar = undefined;
var sv_stopspeed: *ConVar = undefined;
var sv_accelerate: *ConVar = undefined;
var sv_airaccelerate: *ConVar = undefined;

fn shouldLoad() bool {
    if (datamap.feature.loaded) {
        if (vgui.origCFPSPanelShouldDraw != null) {
            return client.mainViewOrigin != null and client.mainViewAngles != null;
        }
        return true;
    }
    return false;
}

fn init() bool {
    sv_friction = tier1.icvar.findVar("sv_friction") orelse return false;
    sv_maxspeed = tier1.icvar.findVar("sv_maxspeed") orelse return false;
    sv_stopspeed = tier1.icvar.findVar("sv_stopspeed") orelse return false;
    sv_accelerate = tier1.icvar.findVar("sv_accelerate") orelse return false;
    sv_airaccelerate = tier1.icvar.findVar("sv_airaccelerate") orelse return false;

    if (datamap.server_map.get("CBasePlayer")) |map| {
        const m_vecAbsOrigin = map.get("CBaseEntity::m_vecAbsOrigin");
        const m_vecAbsVelocity = map.get("CBaseEntity::m_vecAbsVelocity");
        const m_flMaxspeed = map.get("CBasePlayer::m_flMaxspeed");
        const m_bDucked = map.get("CBasePlayer::m_Local.CPlayerLocalData::m_bDucked");
        const m_hGroundEntity = map.get("CBaseEntity::m_hGroundEntity");
        const m_bSinglePlayerGameEnding = map.get("CBasePlayer::m_bSinglePlayerGameEnding");
        const m_vecPreviouslyPredictedOrigin = map.get("CBasePlayer::m_vecPreviouslyPredictedOrigin");
        const m_nWaterLevel = map.get("CBaseEntity::m_nWaterLevel");
        if (m_vecAbsOrigin == null) {
            std.log.debug("Cannot find CBaseEntity::m_vecAbsOrigin offset", .{});
        }
        if (m_vecAbsVelocity == null) {
            std.log.debug("Cannot find CBaseEntity::m_vecAbsVelocity offset", .{});
        }
        if (m_flMaxspeed == null) {
            std.log.debug("Cannot find CBasePlayer::m_flMaxspeed offset", .{});
        }
        if (m_bDucked == null) {
            std.log.debug("Cannot find CBasePlayer::m_Local.CPlayerLocalData::m_bDucked offset", .{});
        }
        if (m_hGroundEntity == null) {
            std.log.debug("Cannot find CBaseEntity::m_hGroundEntity offset", .{});
        }
        if (m_bSinglePlayerGameEnding == null) {
            std.log.debug("Cannot find CBasePlayer::m_bSinglePlayerGameEnding offset", .{});
        }
        if (m_vecPreviouslyPredictedOrigin == null) {
            std.log.debug("Cannot find CBasePlayer::m_vecPreviouslyPredictedOrigin offset", .{});
        }
        if (m_nWaterLevel == null) {
            std.log.debug("Cannot find CBaseEntity::m_nWaterLevel offset", .{});
        }

        if (m_vecAbsOrigin == null or
            m_vecAbsVelocity == null or
            m_flMaxspeed == null or
            m_bDucked == null or
            m_hGroundEntity == null or
            m_bSinglePlayerGameEnding == null or
            m_vecPreviouslyPredictedOrigin == null or
            m_nWaterLevel == null)
        {
            return false;
        }

        server_player_field.m_vecAbsOrigin = m_vecAbsOrigin.?;
        server_player_field.m_vecAbsVelocity = m_vecAbsVelocity.?;
        server_player_field.m_flMaxspeed = m_flMaxspeed.?;
        server_player_field.m_bDucked = m_bDucked.?;
        server_player_field.m_hGroundEntity = m_hGroundEntity.?;
        server_player_field.m_surfaceFriction = (m_bSinglePlayerGameEnding.? & ~@as(usize, @intCast(3))) - 4;
        server_player_field.m_vecPreviouslyPredictedOrigin = m_vecPreviouslyPredictedOrigin.?;
        server_player_field.m_nWaterLevel = m_nWaterLevel.?;
    } else {
        std.log.debug("Cannot find CBasePlayer datamap", .{});
        return false;
    }

    if (datamap.client_map.get("C_BasePlayer")) |map| {
        const m_vecAbsOrigin = map.get("C_BaseEntity::m_vecAbsOrigin");
        const m_vecAbsVelocity = map.get("C_BaseEntity::m_vecAbsVelocity");
        const m_flMaxspeed = map.get("C_BasePlayer::m_flMaxspeed");
        const m_bDucked = map.get("C_BasePlayer::m_Local.CPlayerLocalData::m_bDucked");
        const m_hGroundEntity = map.get("C_BasePlayer::m_hGroundEntity");
        const m_surfaceFriction = map.get("C_BasePlayer::m_surfaceFriction");
        const m_nWaterLevel = map.get("C_BasePlayer::m_nWaterLevel");
        if (m_vecAbsOrigin == null) {
            std.log.debug("Cannot find C_BaseEntity::m_vecAbsOrigin offset", .{});
        }
        if (m_vecAbsVelocity == null) {
            std.log.debug("Cannot find C_BaseEntity::m_vecAbsVelocity offset", .{});
        }
        if (m_flMaxspeed == null) {
            std.log.debug("Cannot find C_BasePlayer::m_flMaxspeed offset", .{});
        }
        if (m_bDucked == null) {
            std.log.debug("Cannot find C_BasePlayer::m_Local.CPlayerLocalData::m_bDucked offset", .{});
        }
        if (m_hGroundEntity == null) {
            std.log.debug("Cannot find C_BasePlayer::m_hGroundEntity offset", .{});
        }
        if (m_surfaceFriction == null) {
            std.log.debug("Cannot find C_BasePlayer::m_surfaceFriction offset", .{});
        }
        if (m_nWaterLevel == null) {
            std.log.debug("Cannot find C_BasePlayer::m_nWaterLevel offset", .{});
        }

        if (m_vecAbsOrigin == null or
            m_vecAbsVelocity == null or
            m_flMaxspeed == null or
            m_bDucked == null or
            m_hGroundEntity == null or
            m_surfaceFriction == null or
            m_nWaterLevel == null)
        {
            return false;
        }

        client_player_field.m_vecAbsOrigin = m_vecAbsOrigin.?;
        client_player_field.m_vecAbsVelocity = m_vecAbsVelocity.?;
        client_player_field.m_flMaxspeed = m_flMaxspeed.?;
        client_player_field.m_bDucked = m_bDucked.?;
        client_player_field.m_hGroundEntity = m_hGroundEntity.?;
        client_player_field.m_surfaceFriction = m_surfaceFriction.?;
        client_player_field.m_nWaterLevel = m_nWaterLevel.?;
    } else {
        std.log.debug("Cannot find C_BasePlayer datamap", .{});
        return false;
    }

    if (vgui.origCFPSPanelShouldDraw != null) {
        PosTextHUD.register();
    }

    if (event.create_move.works) {
        PlayerioTextHUD.register();
    }

    return true;
}

fn deinit() void {}
