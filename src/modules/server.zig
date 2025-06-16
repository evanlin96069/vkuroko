const std = @import("std");

const interfaces = @import("../interfaces.zig");

const sdk = @import("sdk");
const Vector = sdk.Vector;
const Trace = sdk.Trace;
const CMoveData = sdk.CMoveData;
const VCallConv = sdk.VCallConv;

const core = @import("../core.zig");
const game_detection = @import("../utils/game_detection.zig");
const ent_utils = @import("../utils/ent_utils.zig");

const zhook = @import("zhook");

const Module = @import("Module.zig");

pub var module: Module = .{
    .name = "server",
    .init = init,
    .deinit = deinit,
};

const CGameMovement = extern struct {
    _vt: [*]*const anyopaque,

    const VTIndex = struct {
        const getPlayerMins = 8;
        const getPlayerMaxs = 9;
        var tracePlayerBBox: usize = undefined;
    };

    var use_player_minsmaxs_v2 = false;
    var use_trace_player_bbox_for_ground_v2 = false;

    var offset_player: usize = undefined;
    var offset_mv: usize = undefined;

    var override_minmax = false;
    var _mins: *const Vector = undefined;
    var _maxs: *const Vector = undefined;

    const GetPlayerMinsMaxsFuncV1 = *const fn (this: *const CGameMovement) callconv(VCallConv) *const Vector;
    const GetPlayerMinsMaxsFuncV2 = *const fn (this: *const CGameMovement, out: *Vector) callconv(VCallConv) void;

    var origGetPlayerMinsV1: ?GetPlayerMinsMaxsFuncV1 = undefined;
    var origGetPlayerMinsV2: ?GetPlayerMinsMaxsFuncV2 = undefined;

    fn hookedGetPlayerMinsV1(this: *const CGameMovement) callconv(VCallConv) *const Vector {
        if (override_minmax) {
            return _mins;
        }
        return origGetPlayerMinsV1.?(this);
    }

    fn hookedGetPlayerMinsV2(this: *const CGameMovement, out: *Vector) callconv(VCallConv) void {
        @setRuntimeSafety(false);

        if (override_minmax) {
            out.* = _mins.*;
            return;
        }
        origGetPlayerMinsV2.?(this, out);
    }

    var origGetPlayerMaxsV1: ?GetPlayerMinsMaxsFuncV1 = undefined;
    var origGetPlayerMaxsV2: ?GetPlayerMinsMaxsFuncV2 = undefined;

    fn hookedGetPlayerMaxsV1(this: *const CGameMovement) callconv(VCallConv) *const Vector {
        if (override_minmax) {
            return _maxs;
        }
        return origGetPlayerMaxsV1.?(this);
    }

    fn hookedGetPlayerMaxsV2(this: *const CGameMovement, out: *Vector) callconv(VCallConv) void {
        @setRuntimeSafety(false);

        if (override_minmax) {
            out.* = _maxs.*;
            return;
        }
        origGetPlayerMaxsV2.?(this, out);
    }

    var data: CMoveData = undefined;
    var old_mv: *CMoveData = undefined;
    var old_player: *anyopaque = undefined;

    pub fn setMoveData(self: *CGameMovement) void {
        const server_player = ent_utils.getServerPlayer() orelse return;
        data.player_handle = server_player.getRefEHandle().*;

        const ptr: [*]u8 = @ptrCast(self);
        const player = zhook.mem.loadValue(*anyopaque, ptr + offset_player);
        const mv = zhook.mem.loadValue(*CMoveData, ptr + offset_mv);

        old_mv = mv;
        old_player = player;

        zhook.mem.setValue(*anyopaque, ptr + offset_player, server_player);
        zhook.mem.setValue(*CMoveData, ptr + offset_mv, &data);
    }

    pub fn unsetMoveData(self: *CGameMovement) void {
        const ptr: [*]u8 = @ptrCast(self);
        zhook.mem.setValue(*anyopaque, ptr + offset_player, old_player);
        zhook.mem.setValue(*CMoveData, ptr + offset_mv, old_mv);
    }

    pub fn tracePlayerBBox(
        self: *CGameMovement,
        start: *const Vector,
        end: *const Vector,
        mins: *const Vector,
        maxs: *const Vector,
        mask: c_uint,
        collision_group: c_int,
        pm: *Trace,
    ) void {
        override_minmax = true;
        _mins = mins;
        _maxs = maxs;

        const _tracePlayerBBox: *const fn (
            this: *anyopaque,
            start: *const Vector,
            end: *const Vector,
            mask: c_uint,
            collision_group: c_int,
            pm: *Trace,
        ) callconv(VCallConv) void = @ptrCast(self._vt[VTIndex.tracePlayerBBox]);
        _tracePlayerBBox(
            self,
            start,
            end,
            mask,
            collision_group,
            pm,
        );

        override_minmax = false;
    }

    const TracePlayerBBoxForGroundV1Func = *const fn (
        start: *const Vector,
        end: *const Vector,
        mins: *const Vector,
        maxs: *const Vector,
        player_handle: *anyopaque,
        mask: c_uint,
        collision_group: c_int,
        pm: *Trace,
    ) callconv(.C) void;

    const TracePlayerBBoxForGroundV2Func = *const fn (
        this: *anyopaque,
        start: *const Vector,
        end: *const Vector,
        mask: c_uint,
        collision_group: c_int,
        pm: *Trace,
    ) callconv(VCallConv) void;

    var origTracePlayerBBoxForGroundV1: ?TracePlayerBBoxForGroundV1Func = null;
    var origTracePlayerBBoxForGroundV2: ?TracePlayerBBoxForGroundV2Func = null;

    pub fn tracePlayerBBoxForGround(
        self: *CGameMovement,
        start: *const Vector,
        end: *const Vector,
        mins: *const Vector,
        maxs: *const Vector,
        player: *anyopaque,
        mask: c_uint,
        collision_group: c_int,
        pm: *Trace,
    ) void {
        if (CGameMovement.use_trace_player_bbox_for_ground_v2) {
            override_minmax = true;
            _mins = mins;
            _maxs = maxs;
            origTracePlayerBBoxForGroundV2.?(
                self,
                start,
                end,
                mask,
                collision_group,
                pm,
            );
            override_minmax = false;
        } else {
            origTracePlayerBBoxForGroundV1.?(
                start,
                end,
                mins,
                maxs,
                player,
                mask,
                collision_group,
                pm,
            );
        }
    }
};

// Ignore first 5 bytes in case other plugin is hooking CheckJumpButton
const CheckJumpButton_patterns = zhook.mem.makePatterns(.{
    // 3420
    "?? ?? ?? ?? ?? F1 8B 4E 08 80 B9 C4 09 00 00 00 74 0E 8B 76 04 83 4E 28 02 32 C0 5E 83 C4 1C C3 D9 EE D8 91 30 0D 00 00",
    // 5135
    "?? ?? ?? ?? ?? F1 8B 4E 04 80 B9 04 0A 00 00 00 74 0E 8B 76 08 83 4E 28 02 32 C0 5E 83 C4 1C C3 D9 EE D8 91 70 0D 00 00",
    // 7122284
    "?? ?? ?? ?? ?? 18 56 8B F1 8B ?? 04 80 ?? ?? ?? 00 00 00 74 0E 8B ?? 08 83 ?? 28 02 32 C0 5E 8B E5 5D C3",
});

const TracePlayerBBoxForGround_patterns = zhook.mem.makePatterns(.{
    // 5135
    "55 8B EC 83 E4 F0 81 EC 84 00 00 00 53 56 8B 75 24 8B 46 0C D9 46 2C 8B 4E 10",
    // 7122284
    "55 8B EC 83 EC 3C 53 56 57 8B F9 8D 4D ??",
});

const TracePlayerBBoxForGround2_patterns = zhook.mem.makePatterns(.{
    // 5135
    "55 8B EC 83 E4 F0 8B 4D 18 8B 01 8B 50 08 81 EC 84 00 00 00 53 56 57 FF D2",
    // 7122284
    "53 8B DC 83 EC 08 83 E4 F0 83 C4 04 55 8B 6B ?? 89 6C 24 ?? 8B EC 8B 4B ?? 81 EC 98 00 00 00",
});

pub fn canTracePlayerBBox() bool {
    return CGameMovement.origTracePlayerBBoxForGroundV1 != null or
        CGameMovement.origTracePlayerBBoxForGroundV2 != null;
}

pub var gm: *CGameMovement = undefined;

fn init() bool {
    gm = @ptrCast(interfaces.serverFactory("GameMovement001", null) orelse {
        core.log.err("Failed to get IGameMovement interface", .{});
        return false;
    });

    const server = zhook.mem.getModule("server") orelse return false;

    if (zhook.mem.scanUniquePatterns(server, CheckJumpButton_patterns)) |match| {
        switch (match.index) {
            0 => { // 3420
                CGameMovement.offset_player = 8;
                CGameMovement.offset_mv = 4;

                CGameMovement.use_player_minsmaxs_v2 = false;
                CGameMovement.use_trace_player_bbox_for_ground_v2 = false;

                CGameMovement.VTIndex.tracePlayerBBox = 45;
            },
            1 => { // 5135
                CGameMovement.offset_player = 4;
                CGameMovement.offset_mv = 8;

                CGameMovement.use_player_minsmaxs_v2 = false;
                CGameMovement.use_trace_player_bbox_for_ground_v2 = false;

                CGameMovement.VTIndex.tracePlayerBBox = 10;
            },
            2 => { // steampipe
                CGameMovement.offset_player = 4;
                CGameMovement.offset_mv = 8;

                CGameMovement.use_player_minsmaxs_v2 = true;

                CGameMovement.VTIndex.tracePlayerBBox = 10;
            },
            else => unreachable,
        }

        if (game_detection.doesGameLooksLikePortal()) {
            CGameMovement.use_trace_player_bbox_for_ground_v2 = false;
            if (zhook.mem.scanUniquePatterns(server, TracePlayerBBoxForGround2_patterns)) |_match| {
                CGameMovement.origTracePlayerBBoxForGroundV1 = @ptrCast(_match.ptr);
            }
        } else {
            if (zhook.mem.scanUniquePatterns(server, TracePlayerBBoxForGround_patterns)) |_match| {
                switch (_match.index) {
                    0 => { // 5135
                        CGameMovement.use_trace_player_bbox_for_ground_v2 = false;
                        CGameMovement.origTracePlayerBBoxForGroundV1 = @ptrCast(_match.ptr);
                    },
                    1 => { // 7122284
                        CGameMovement.use_trace_player_bbox_for_ground_v2 = true;
                        CGameMovement.origTracePlayerBBoxForGroundV2 = @ptrCast(_match.ptr);
                    },
                    else => unreachable,
                }
            }
        }

        if (CGameMovement.origTracePlayerBBoxForGroundV1 != null or
            CGameMovement.origTracePlayerBBoxForGroundV2 != null)
        {
            if (CGameMovement.use_player_minsmaxs_v2) {
                CGameMovement.origGetPlayerMinsV2 = core.hook_manager.hookVMT(
                    CGameMovement.GetPlayerMinsMaxsFuncV2,
                    gm._vt,
                    CGameMovement.VTIndex.getPlayerMins,
                    CGameMovement.hookedGetPlayerMinsV2,
                ) catch null;

                CGameMovement.origGetPlayerMaxsV2 = core.hook_manager.hookVMT(
                    CGameMovement.GetPlayerMinsMaxsFuncV2,
                    gm._vt,
                    CGameMovement.VTIndex.getPlayerMaxs,
                    CGameMovement.hookedGetPlayerMaxsV2,
                ) catch null;
            } else {
                CGameMovement.origGetPlayerMinsV1 = core.hook_manager.hookVMT(
                    CGameMovement.GetPlayerMinsMaxsFuncV1,
                    gm._vt,
                    CGameMovement.VTIndex.getPlayerMins,
                    CGameMovement.hookedGetPlayerMinsV1,
                ) catch null;

                CGameMovement.origGetPlayerMaxsV1 = core.hook_manager.hookVMT(
                    CGameMovement.GetPlayerMinsMaxsFuncV1,
                    gm._vt,
                    CGameMovement.VTIndex.getPlayerMaxs,
                    CGameMovement.hookedGetPlayerMaxsV1,
                ) catch null;
            }
        }
    } else {
        core.log.debug("Failed to find CheckJumpButton", .{});
    }

    if (!canTracePlayerBBox()) {
        core.log.warn("Cannot trace player bounding box", .{});
    }

    return true;
}

fn deinit() void {}
