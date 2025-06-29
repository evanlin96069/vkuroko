const std = @import("std");
const builtin = @import("builtin");

const sdk = @import("sdk");
const abi = sdk.abi;

const interfaces = @import("../interfaces.zig");
const core = @import("../core.zig");
const event = @import("../event.zig");

const game_detection = @import("../utils/game_detection.zig");

const zhook = @import("zhook");

const Module = @import("Module.zig");

const Color = sdk.Color;
const VCallConv = abi.VCallConv;
const CUtlVector = sdk.CUtlVector;
const HScheme = sdk.HScheme;
const HFont = sdk.HFont;
const CFontAmalgam = sdk.CFontAmalgam;

pub var module: Module = .{
    .name = "vgui",
    .init = init,
    .deinit = deinit,
};

const IPanel = extern struct {
    _vt: [*]*const anyopaque,

    const VTIndex = struct {
        var getName: usize = undefined;
        var paintTraverse: usize = undefined;
    };

    const PaintTraverseFunc = *const @TypeOf(hookedPaintTraverse);
    var origPaintTraverse: PaintTraverseFunc = undefined;

    fn getName(self: *IPanel, panel: u32) [*:0]const u8 {
        const _setEnabled: *const fn (this: *anyopaque, panel: u32) callconv(VCallConv) [*:0]const u8 = @ptrCast(self._vt[VTIndex.getName]);
        return _setEnabled(self, panel);
    }

    fn hookedPaintTraverse(this: *IPanel, vgui_panel: u32, force_repaint: bool, allow_force: bool) callconv(VCallConv) void {
        const S = struct {
            var panel_id: u32 = 0;
            var found_panel_id: bool = false;
        };

        origPaintTraverse(this, vgui_panel, force_repaint, allow_force);

        if (!S.found_panel_id) {
            if (std.mem.eql(u8, std.mem.span(ipanel.getName(vgui_panel)), "FocusOverlayPanel")) {
                S.panel_id = vgui_panel;
                S.found_panel_id = true;
            }
        } else if (S.panel_id == vgui_panel) {
            event.paint.emit(.{});
        }
    }
};

const IEngineVGui = extern struct {
    _vt: [*]*const anyopaque,

    const VTIndex = struct {
        const isInitialized: usize = 7 + abi.dtor_adjust;
    };

    const VTable = extern struct {
        dtor: abi.DtorVTable,
        getPanel: *const fn (this: *anyopaque, panel_type: c_int) callconv(VCallConv) c_uint,
        isGameUIVisible: *const fn (this: *anyopaque) callconv(VCallConv) bool,
    };

    fn vt(self: *IEngineVGui) *const VTable {
        return @ptrCast(self._vt);
    }

    pub fn isGameUIVisible(self: *IEngineVGui) bool {
        return self.vt().isGameUIVisible(self);
    }

    pub fn isInitialized(self: *IEngineVGui) bool {
        const _isInitialized: *const fn (this: *anyopaque) callconv(VCallConv) bool = @ptrCast(self._vt[VTIndex.isInitialized]);
        return _isInitialized(self);
    }
};

const IMatSystemSurface = extern struct {
    _vt: [*]*const anyopaque,

    const VTIndex = struct {
        const drawSetColor: usize = switch (builtin.os.tag) {
            .windows => 10,
            .linux => 11,
            else => unreachable,
        };
        const drawFilledRect: usize = 12;
        const drawOutlinedRect: usize = 14;
        const drawLine: usize = 15;
        var getScreenSize: usize = undefined;
        var getFontTall: usize = undefined;
        var getTextSize: usize = undefined;
        var drawOutlinedCircle: usize = undefined;
        var getFontName: ?usize = null;
        var drawColoredText: usize = undefined;
    };

    fn findFontAmalgams(self: *IMatSystemSurface) ?*CUtlVector(CFontAmalgam) {
        var FontManagerFunc: ?*const fn () *CUtlVector(CFontAmalgam) = null;

        const addr: [*]const u8 = @ptrCast(self._vt[VTIndex.getFontTall]);
        var p = addr;
        var call_count: u32 = 0;
        while (@intFromPtr(p) - @intFromPtr(addr) < 32) : (p = p + (zhook.x86.x86_len(p) catch {
            return null;
        })) {
            if (p[0] == zhook.x86.Opcode.Op1.call) {
                call_count += 1;
                // First call in Linux is PIC
                if (builtin.os.tag == .linux and call_count != 2) continue;

                const offset = zhook.mem.loadValue(u32, p + 1);
                FontManagerFunc = @ptrFromInt(@intFromPtr(p + 5) +% offset);
                break;
            }
        }

        if (FontManagerFunc) |f| {
            return f();
        }
        return null;
    }

    pub fn drawSetColor(self: *IMatSystemSurface, color: Color) void {
        const _drawSetColor: *const fn (this: *anyopaque, color: Color) callconv(VCallConv) void = @ptrCast(self._vt[VTIndex.drawSetColor]);
        _drawSetColor(self, color);
    }

    pub fn drawFilledRect(self: *IMatSystemSurface, x0: i32, y0: i32, x1: i32, y1: i32) void {
        const _drawFilledRect: *const fn (this: *anyopaque, x0: c_int, y0: c_int, x1: c_int, y1: c_int) callconv(VCallConv) void = @ptrCast(self._vt[VTIndex.drawFilledRect]);
        _drawFilledRect(self, x0, y0, x1, y1);
    }

    pub fn drawOutlinedRect(self: *IMatSystemSurface, x0: i32, y0: i32, x1: i32, y1: i32) void {
        const _drawOutlinedRect: *const fn (this: *anyopaque, x0: c_int, y0: c_int, x1: c_int, y1: c_int) callconv(VCallConv) void = @ptrCast(self._vt[VTIndex.drawOutlinedRect]);
        _drawOutlinedRect(self, x0, y0, x1, y1);
    }

    pub fn drawLine(self: *IMatSystemSurface, x0: i32, y0: i32, x1: i32, y1: i32) void {
        const _drawLine: *const fn (this: *anyopaque, x0: c_int, y0: c_int, x1: c_int, y1: c_int) callconv(VCallConv) void = @ptrCast(self._vt[VTIndex.drawLine]);
        _drawLine(self, x0, y0, x1, y1);
    }

    pub fn getScreenSize(self: *IMatSystemSurface) struct { wide: i32, tall: i32 } {
        var wide: c_int = undefined;
        var tall: c_int = undefined;

        const _getScreenSize: *const fn (this: *anyopaque, wide: *c_int, tall: *c_int) callconv(VCallConv) void = @ptrCast(self._vt[VTIndex.getScreenSize]);
        _getScreenSize(self, &wide, &tall);

        return .{
            .wide = wide,
            .tall = tall,
        };
    }

    pub fn getFontTall(self: *IMatSystemSurface, font: HFont) c_int {
        const _getFontTall: *const fn (this: *anyopaque, font: HFont) callconv(VCallConv) c_int = @ptrCast(self._vt[VTIndex.getFontTall]);
        return _getFontTall(self, font);
    }

    pub fn drawOutlinedCircle(self: *IMatSystemSurface, x: i32, y: i32, radius: i32, segments: i32) void {
        const _drawOutlinedCircle: *const fn (this: *anyopaque, x: c_int, y: c_int, radius: c_int, segments: c_int) callconv(VCallConv) void = @ptrCast(self._vt[VTIndex.drawOutlinedCircle]);
        _drawOutlinedCircle(self, x, y, radius, segments);
    }

    fn getFontName(self: *IMatSystemSurface, font: HFont) ?[*:0]const u8 {
        if (VTIndex.getFontName) |index| {
            const _getFontName: *const fn (this: *anyopaque, font: HFont) callconv(VCallConv) [*:0]const u8 = @ptrCast(self._vt[index]);
            return _getFontName(self, font);
        }

        return null;
    }

    pub fn drawText(
        self: *IMatSystemSurface,
        font: HFont,
        x: i32,
        y: i32,
        comptime fmt: []const u8,
        args: anytype,
    ) void {
        self.drawColoredText(
            self,
            font,
            x,
            y,
            .{
                .r = 255,
                .g = 255,
                .b = 255,
                .a = 255,
            },
            fmt,
            args,
        );
    }

    pub fn drawColoredText(
        self: *IMatSystemSurface,
        font: HFont,
        x: i32,
        y: i32,
        color: Color,
        comptime fmt: []const u8,
        args: anytype,
    ) void {
        const _drawColoredText: *const fn (
            this: *anyopaque,
            font: HFont,
            x: c_int,
            y: c_int,
            r: c_int,
            g: c_int,
            b: c_int,
            a: c_int,
            fmt: [*:0]const u8,
            ...,
        ) callconv(.C) c_int = @ptrCast(self._vt[VTIndex.drawColoredText]);

        const text = std.fmt.allocPrintZ(core.allocator, fmt, args) catch return;
        defer core.allocator.free(text);

        _ = _drawColoredText(
            self,
            font,
            x,
            y,
            color.r,
            color.g,
            color.b,
            color.a,
            "%s",
            text.ptr,
        );
    }
};

const ISchemeManager = extern struct {
    _vt: [*]*const anyopaque,

    const VTIndex = struct {
        const getDefaultScheme: usize = 4 + abi.dtor_adjust;
        const getIScheme: usize = 8 + abi.dtor_adjust;
    };

    fn getDefaultScheme(self: *ISchemeManager) HScheme {
        const _getDefaultScheme: *const fn (this: *anyopaque) callconv(VCallConv) HScheme = @ptrCast(self._vt[VTIndex.getDefaultScheme]);
        return _getDefaultScheme(self);
    }

    fn getIScheme(self: *ISchemeManager, font: HFont) ?*IScheme {
        const _getIScheme: *const fn (this: *anyopaque, font: HFont) callconv(VCallConv) ?*IScheme = @ptrCast(self._vt[VTIndex.getIScheme]);
        return _getIScheme(self, font);
    }
};

const IScheme = extern struct {
    _vt: [*]*const anyopaque,

    const VTIndex = struct {
        const getFont: usize = 3 + abi.dtor_adjust;
    };

    pub fn getFont(self: *IScheme, name: [*:0]const u8, proportional: bool) HFont {
        const _getFont: *const fn (this: *anyopaque, name: [*:0]const u8, proportional: bool) callconv(VCallConv) HFont = @ptrCast(self._vt[VTIndex.getFont]);
        return _getFont(self, name, proportional);
    }
};

pub const FontManager = struct {
    pub var font_amalgamas: ?*CUtlVector(CFontAmalgam) = null;

    pub fn canGetFontName() bool {
        if (font_amalgamas == null) return false;
        if (IMatSystemSurface.VTIndex.getFontName == null) {
            return switch (builtin.os.tag) {
                .windows => CUtlSymbol__String != null,
                .linux => true,
                else => unreachable,
            };
        }
        return true;
    }

    pub fn getFontCount() u32 {
        if (font_amalgamas) |fonts| {
            return fonts.size;
        }
        return 0;
    }

    pub fn getFontName(font: HFont) ?[*:0]const u8 {
        if (!canGetFontName()) return null;
        if (!isValidFont(font)) return null;

        if (IMatSystemSurface.VTIndex.getFontName != null) {
            return imatsystem.getFontName(font);
        }

        if (font_amalgamas.?.elements[font].fonts.size == 0) return null;

        const vgui_font = font_amalgamas.?.elements[font].fonts.elements[0].font;
        return switch (builtin.os.tag) {
            .windows => if (CUtlSymbol__String) |stringFn|
                stringFn(&vgui_font.name)
            else
                null,
            .linux => vgui_font.name.get(),
            else => unreachable,
        };
    }

    pub fn isValidFont(font: HFont) bool {
        if (font_amalgamas) |fonts| {
            if (font >= fonts.size) return false;
            if (fonts.elements[font].fonts.size == 0) return false;
            return fonts.elements[font].fonts.elements[0].font.isValid();
        }
        return false;
    }

    pub fn findFont(font_name: []const u8, size: u32) !HFont {
        if (!canGetFontName()) return error.FontFailed;

        var found_name = false;
        var i: u32 = 0;
        while (i < font_amalgamas.?.size) : (i += 1) {
            if (isValidFont(i)) {
                const name = FontManager.getFontName(i);
                if (std.mem.eql(u8, font_name, std.mem.span(name))) {
                    found_name = true;
                    if (size == font_amalgamas.?.elements[i].max_height) {
                        return i;
                    }
                }
            }
        }

        if (found_name) {
            return error.SizeNotFound;
        }
        return error.NameNotFound;
    }
};

pub var imatsystem: *IMatSystemSurface = undefined;
pub var ienginevgui: *IEngineVGui = undefined;
var ipanel: *IPanel = undefined;
var ischeme_mgr: *ISchemeManager = undefined;
pub var ischeme: *IScheme = undefined;

pub fn getEngineVGui() ?*IEngineVGui {
    return @ptrCast(interfaces.engineFactory("VEngineVGui001", null));
}

// Windows 5135
const CUtlSymbol__String_patterns = zhook.mem.makePattern("51 66 8B 09 8B C4");
var CUtlSymbol__String: ?*const fn (this: *sdk.CUtlSymbol) callconv(.Thiscall) [*:0]const u8 = null;

pub var vgui_dll: []const u8 = undefined;

fn init() bool {
    vgui_dll = zhook.utils.getModule("vguimatsurface") orelse blk: {
        core.log.warn("Failed to get vguimatsurface module", .{});
        break :blk "";
    };

    const imatsystem_info = interfaces.create(interfaces.engineFactory, "MatSystemSurface", .{ 6, 8 }) orelse {
        core.log.err("Failed to get IMatSystem interface", .{});
        return false;
    };
    imatsystem = @ptrCast(imatsystem_info.interface);
    switch (imatsystem_info.version) {
        6 => {
            IMatSystemSurface.VTIndex.getScreenSize = 37;
            IMatSystemSurface.VTIndex.getFontTall = 67;
            IMatSystemSurface.VTIndex.getTextSize = 72;
            IMatSystemSurface.VTIndex.drawOutlinedCircle = 96;
            IMatSystemSurface.VTIndex.drawColoredText = if (@import("root").ifacever == 2) 134 else 138;
            // 4104 uses 134, but has ifacever = 3
            // We can just check the build number, but I also want it to work on leaked build
            if (game_detection.getBuildNumber()) |n| {
                if (n <= 4104) {
                    IMatSystemSurface.VTIndex.drawColoredText = 134;
                }
            }

            IPanel.VTIndex.getName = 35 + abi.dtor_adjust;
            IPanel.VTIndex.paintTraverse = 40 + abi.dtor_adjust;
        },
        8 => {
            IMatSystemSurface.VTIndex.getScreenSize = 38;
            IMatSystemSurface.VTIndex.getFontTall = 69;
            IMatSystemSurface.VTIndex.getTextSize = 75;
            IMatSystemSurface.VTIndex.drawOutlinedCircle = 99;
            IMatSystemSurface.VTIndex.getFontName = 130;
            IMatSystemSurface.VTIndex.drawColoredText = 162;

            IPanel.VTIndex.getName = 36 + abi.dtor_adjust;
            IPanel.VTIndex.paintTraverse = 41 + abi.dtor_adjust;
        },
        else => unreachable,
    }

    ischeme_mgr = @ptrCast(interfaces.engineFactory("VGUI_Scheme010", null) orelse {
        core.log.err("Failed to get ISchemeManager interface", .{});
        return false;
    });

    ischeme = ischeme_mgr.getIScheme(ischeme_mgr.getDefaultScheme()) orelse {
        core.log.err("Failed to get IScheme", .{});
        return false;
    };

    ienginevgui = getEngineVGui() orelse {
        core.log.err("Failed to get IEngineVgui interface", .{});
        return false;
    };

    ipanel = @ptrCast(interfaces.engineFactory("VGUI_Panel009", null) orelse {
        core.log.err("Failed to get IPanel interface", .{});
        return false;
    });

    FontManager.font_amalgamas = imatsystem.findFontAmalgams();
    if (FontManager.font_amalgamas == null) {
        core.log.warn("Failed find FontManager", .{});
    } else if (builtin.os.tag == .windows and IMatSystemSurface.VTIndex.getFontName == null) {
        if (zhook.mem.scanUnique(vgui_dll, CUtlSymbol__String_patterns)) |offset| {
            CUtlSymbol__String = @ptrCast(vgui_dll.ptr + offset);
        } else {
            core.log.warn("Failed to find CUtlSymbol::String", .{});
        }
    }

    if (!FontManager.canGetFontName()) {
        core.log.warn("FontManager won't be able to get font name", .{});
    }

    IPanel.origPaintTraverse = core.hook_manager.hookVMT(
        IPanel.PaintTraverseFunc,
        ipanel._vt,
        IPanel.VTIndex.paintTraverse,
        IPanel.hookedPaintTraverse,
    ) catch {
        core.log.err("Failed to hook PaintTraverse", .{});
        return false;
    };
    event.paint.works = true;

    return true;
}

fn deinit() void {}
