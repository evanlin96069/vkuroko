const std = @import("std");
const builtin = @import("builtin");

const interfaces = @import("../interfaces.zig");
const core = @import("../core.zig");
const event = @import("../event.zig");

const Module = @import("Module.zig");

const zhook = @import("zhook");

const sdk = @import("sdk");
const Vector = sdk.Vector;
const QAngle = sdk.QAngle;
const CUserCmd = sdk.CUserCmd;
const VCallConv = sdk.abi.VCallConv;

pub var module: Module = .{
    .name = "client",
    .init = init,
    .deinit = deinit,
};

const IClientEntityList = extern struct {
    _vt: [*]*const anyopaque,

    const VTIndex = struct {
        const getClientEntity = 3;
        const getHighestEntityIndex = 6;
    };

    pub fn getClientEntity(self: *IClientEntityList, index: c_int) ?*sdk.IClientEntity {
        const _getClientEntity: *const fn (this: *anyopaque, index: c_int) callconv(VCallConv) ?*sdk.IClientEntity = @ptrCast(self._vt[VTIndex.getClientEntity]);
        return _getClientEntity(self, index);
    }

    pub fn getHighestEntityIndex(self: *IClientEntityList) c_int {
        const _getHighestEntityIndex: *const fn (this: *anyopaque) callconv(VCallConv) c_int = @ptrCast(self._vt[VTIndex.getHighestEntityIndex]);
        return _getHighestEntityIndex(self);
    }
};

const IBaseClientDLL = extern struct {
    _vt: [*]*const anyopaque,

    const VTIndex = struct {
        var decodeUserCmdFromBuffer: usize = undefined;
    };

    fn findIInput(self: *IBaseClientDLL) ?*IInput {
        const addr: [*]const u8 = @ptrCast(self._vt[VTIndex.decodeUserCmdFromBuffer]);
        var p = addr;
        switch (builtin.os.tag) {
            .windows => {
                while (@intFromPtr(p) - @intFromPtr(addr) < 32) : (p = p + (zhook.x86.x86_len(p) catch {
                    return null;
                })) {
                    if (p[0] == @intFromEnum(zhook.x86.Opcode.Op1.movrmw) and p[1] == zhook.x86.modrm(0b00, 0b001, 0b101)) {
                        return zhook.mem.loadValue(**IInput, p + 2).*;
                    }
                }
            },
            .linux => {
                var GOT_addr: ?u32 = null;
                while (@intFromPtr(p) - @intFromPtr(addr) < 32) : (p = p + (zhook.x86.x86_len(p) catch {
                    return null;
                })) {
                    if (p[0] == @intFromEnum(zhook.x86.Opcode.Op1.call)) {
                        if (zhook.utils.matchPIC(p)) |off| {
                            // imm32 from add
                            const imm32 = zhook.mem.loadValue(u32, p + off);
                            GOT_addr = @intFromPtr(p + 5) +% imm32;
                        }
                    } else if (p[0] == @intFromEnum(zhook.x86.Opcode.Op1.lea) and p[1] == zhook.x86.modrm(0b10, 0b000, 0b000)) {
                        if (GOT_addr) |base| {
                            // imm32 from lea
                            const imm32 = zhook.mem.loadValue(u32, p + 2);
                            return @as(**IInput, @ptrFromInt(base + imm32)).*;
                        }
                    }
                }
            },
            else => unreachable,
        }
        return null;
    }
};

const IInput = extern struct {
    _vt: [*]*const anyopaque,

    const VTIndex = struct {
        const createMove = 3;
        const decodeUserCmdFromBuffer = 7;
        const getUserCmd = 8;
    };

    const CreateMoveFunc = *const @TypeOf(hookedCreateMove);
    var origCreateMove: CreateMoveFunc = undefined;

    fn hookedCreateMove(self: *IInput, sequence_number: c_int, input_sample_frametime: f32, active: bool) callconv(VCallConv) void {
        origCreateMove(self, sequence_number, input_sample_frametime, active);
        event.create_move.emit(.{ true, self.getUserCmd(sequence_number) });
    }

    const DecodeUserCmdFromBufferFunc = *const @TypeOf(hookedDecodeUserCmdFromBuffer);
    var origDecodeUserCmdFromBuffer: DecodeUserCmdFromBufferFunc = undefined;

    fn hookedDecodeUserCmdFromBuffer(self: *IInput, buf: *anyopaque, sequence_number: c_int) callconv(VCallConv) void {
        origDecodeUserCmdFromBuffer(self, buf, sequence_number);
        event.create_move.emit(.{ false, self.getUserCmd(sequence_number) });
    }

    fn getUserCmd(self: *IInput, sequence_number: c_int) callconv(VCallConv) *CUserCmd {
        const _getUserCmd: *const fn (this: *anyopaque, sequence_number: c_int) callconv(VCallConv) *CUserCmd = @ptrCast(self._vt[VTIndex.getUserCmd]);
        return _getUserCmd(self, sequence_number);
    }
};

pub var entlist: *IClientEntityList = undefined;
pub var vclient: *IBaseClientDLL = undefined;
var iinput: *IInput = undefined;

pub var override_fps_panel = false;
const CFPSPanel__ShouldDrawFunc = *const @TypeOf(hookedCFPSPanel__ShouldDraw);
pub var origCFPSPanel__ShouldDraw: ?CFPSPanel__ShouldDrawFunc = null;

fn hookedCFPSPanel__ShouldDraw(this: *anyopaque) callconv(VCallConv) bool {
    if (override_fps_panel) {
        return false;
    }
    return origCFPSPanel__ShouldDraw.?(this);
}

const CFPSPanel__ShouldDraw_patterns = zhook.mem.makePatterns(switch (builtin.os.tag) {
    .windows => .{
        // 5135
        "80 3D ?? ?? ?? ?? 00 75 ?? A1 ?? ?? ?? ?? 83 78 ?? 00 74 ??",
    },
    .linux => .{
        // 9786830
        "E8 ?? ?? ?? ?? 81 C2 ?? ?? ?? ?? 55 89 E5 53 8B 4D 08",
    },
    else => unreachable,
});

const GetDamagePosition_patterns = zhook.mem.makePatterns(switch (builtin.os.tag) {
    .windows => .{
        // 5135
        "83 EC 18 E8 ?? ?? ?? ?? E8 ?? ?? ?? ?? 8B 08 89 4C 24 0C 8B 50 04 6A 00 89 54 24 14 8B 40 08 6A 00 8D 4C 24 08 51 8D 54 24 18 52 89 44 24 24",
        // 1910503
        "55 8B EC 83 EC ?? 56 8B F1 E8 ?? ?? ?? ?? E8 ?? ?? ?? ??",
    },
    .linux => .{
        // 9786830
        "55 89 E5 56 53 E8 ?? ?? ?? ?? 81 C3 ?? ?? ?? ?? 83 EC 30 8B 75 0C E8 ?? ?? ?? ?? E8 ?? ?? ?? ??",
    },
    else => unreachable,
});

pub var mainViewOrigin: ?*const fn () callconv(.c) *const Vector = null;
pub var mainViewAngles: ?*const fn () callconv(.c) *const QAngle = null;

pub var client_dll: []const u8 = "";

fn init() bool {
    client_dll = zhook.utils.getModule("client") orelse blk: {
        core.log.warn("Failed to get client module", .{});
        break :blk "";
    };

    const clientFactory = interfaces.getFactory("client") orelse {
        core.log.err("Failed to get client interface factory", .{});
        return false;
    };

    entlist = @ptrCast(clientFactory("VClientEntityList003", null) orelse {
        core.log.err("Failed to get IClientEntityList interface", .{});
        return false;
    });

    const vclient_info = interfaces.create(clientFactory, "VClient", .{ 15, 17 }) orelse {
        core.log.err("Failed to get VClient interface", .{});
        return false;
    };
    vclient = @ptrCast(vclient_info.interface);
    switch (vclient_info.version) {
        15 => {
            IBaseClientDLL.VTIndex.decodeUserCmdFromBuffer = 22;
        },
        17 => {
            IBaseClientDLL.VTIndex.decodeUserCmdFromBuffer = 25;
        },
        else => unreachable,
    }

    if (vclient.findIInput()) |_iinput| {
        iinput = _iinput;

        IInput.origCreateMove = core.hook_manager.hookVMT(
            IInput.CreateMoveFunc,
            iinput._vt,
            IInput.VTIndex.createMove,
            IInput.hookedCreateMove,
        ) catch {
            core.log.err("Failed to hook CreateMove", .{});
            return false;
        };

        IInput.origDecodeUserCmdFromBuffer = core.hook_manager.hookVMT(
            IInput.DecodeUserCmdFromBufferFunc,
            iinput._vt,
            IInput.VTIndex.decodeUserCmdFromBuffer,
            IInput.hookedDecodeUserCmdFromBuffer,
        ) catch {
            core.log.err("Failed to hook DecodeUserCmdFromBuffer", .{});
            return false;
        };

        event.create_move.works = true;
    } else {
        core.log.warn("Failed to find IInput interface", .{});
    }

    const GetDamagePosition_match = zhook.mem.scanUniquePatterns(client_dll, GetDamagePosition_patterns);
    if (GetDamagePosition_match) |match| {
        const call1_offset: u32 = switch (builtin.os.tag) {
            .windows => switch (match.index) {
                0 => 3,
                1 => 9,
                else => unreachable,
            },
            .linux => 22,
            else => unreachable,
        };
        const call2_offset: u32 = call1_offset + 5;
        mainViewOrigin = @ptrCast(@as(*u8, @ptrFromInt(@intFromPtr(match.ptr + call1_offset + 5) +% zhook.mem.loadValue(u32, match.ptr + call1_offset + 1))));
        mainViewAngles = @ptrCast(@as(*u8, @ptrFromInt(@intFromPtr(match.ptr + call2_offset + 5) +% zhook.mem.loadValue(u32, match.ptr + call2_offset + 1))));
    } else {
        core.log.warn("Failed to find CHudDamageIndicator::GetDamagePosition", .{});
    }

    origCFPSPanel__ShouldDraw = core.hook_manager.findAndHook(
        CFPSPanel__ShouldDrawFunc,
        client_dll,
        CFPSPanel__ShouldDraw_patterns,
        hookedCFPSPanel__ShouldDraw,
    ) catch |e| blk: {
        switch (e) {
            error.PatternNotFound => core.log.debug("Cannot find CFPSPanel::ShouldDraw", .{}),
            else => core.log.debug("Failed to hook CFPSPanel::ShouldDraw: {t}", .{e}),
        }
        break :blk null;
    };

    return true;
}

fn deinit() void {}
