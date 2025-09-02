const std = @import("std");
const builtin = @import("builtin");

const sdk = @import("sdk");

const interfaces = @import("../interfaces.zig");
const tier0 = @import("tier0.zig");
const core = @import("../core.zig");
const FileCompletion = @import("../utils/completion.zig").FileCompletion;

const abi = sdk.abi;
const VCallConv = sdk.abi.VCallConv;

const Module = @import("Module.zig");

pub const FCvar = packed struct(c_uint) {
    unregistered: bool = false,
    development_only: bool = false,
    game_dll: bool = false,
    client_dll: bool = false,
    hidden: bool = false,
    protected: bool = false,
    sp_only: bool = false,
    archive: bool = false,
    notify: bool = false,
    user_info: bool = false,
    printable_only: bool = false,
    unlogged: bool = false,
    never_as_string: bool = false,
    replicated: bool = false,
    cheat: bool = false,
    _pad_0: u1 = 0,
    demo: bool = false,
    dont_record: bool = false,
    _pad_1: u2 = 0,
    reload_materials: bool = false,
    reload_textures: bool = false,
    not_connected: bool = false,
    material_system_thread: bool = false,
    archive_xbox: bool = false,
    accessible_from_threads: bool = false,
    _pad_2: u2 = 0,
    server_can_execute: bool = false,
    server_cannot_query: bool = false,
    clientcmd_can_execute: bool = false,
    _pad_3: u1 = 0,
};

pub const ConCommandBase = extern struct {
    _vt: *align(@alignOf(*anyopaque)) const anyopaque = undefined,
    next: ?*ConCommandBase = null,
    registered: bool = false,
    name: [*:0]const u8,
    help_string: [*:0]const u8 = "",
    flags: FCvar = .{},

    const VTable = extern struct {
        dtor: abi.DtorVTable,
        isCommand: *const fn (this: *const anyopaque) callconv(VCallConv) bool,
        isFlagSet: *const anyopaque,
        addFlags: *const anyopaque,
        getName: *const anyopaque,
        getHelpText: *const anyopaque,
        isRegistered: *const anyopaque,
        getDLLIdentifier: *const fn (this: *anyopaque) callconv(VCallConv) c_int,

        create: *const anyopaque,
        init: *const anyopaque,
    };

    fn getDLLIdentifier(this: *anyopaque) callconv(VCallConv) c_int {
        _ = this;
        return ICvar.dll_identifier;
    }

    fn vt(self: *const ConCommandBase) *const VTable {
        return @ptrCast(self._vt);
    }

    pub fn isCommand(self: *const ConCommandBase) bool {
        return self.vt().isCommand(self);
    }
};

pub const CCommand = extern struct {
    argc: c_int,
    argv_0_size: c_int,
    args_buffer: [max_length]u8,
    argv_buffer: [max_length]u8,
    argv: [max_argc][*:0]const u8,

    pub const max_argc = 64;
    pub const max_length = 512;

    pub fn args(self: *const CCommand, index: usize) []const u8 {
        return std.mem.span(self.argv[index]);
    }
};

pub const ConCommand = extern struct {
    base: ConCommandBase,
    command_callback: CommandCallbackFn,
    completion_callback: ?CommandCompletionCallbackFn = null,

    callback_flags: packed struct(u8) {
        has_completion_callback: bool = false,
        using_new_command_callback: bool = true,
        using_command_callback_interface: bool = false,
        _pad_0: u5 = 0,
    } = .{},

    pub const CommandCallbackFn = *const fn (args: *const CCommand) callconv(.c) void;

    pub const completion_max_items = 64;
    pub const completion_item_length = 64;
    pub const CommandCompletionCallbackFn = *const fn (
        partial: [*:0]const u8,
        commands: *[completion_max_items][completion_item_length]u8,
    ) callconv(.c) c_int;

    pub const Data = struct {
        name: [*:0]const u8,
        help_string: [*:0]const u8 = "",
        flags: FCvar = .{},
        command_callback: CommandCallbackFn,
        completion_callback: ?CommandCompletionCallbackFn = null,
    };

    var vtable: VTable = undefined;

    const VTable = extern struct {
        base: ConCommandBase.VTable,
        autoCompleteSuggest: *const anyopaque,
        canAutoComplete: *const anyopaque,
        dispatch: *const fn (this: *anyopaque, command: *const CCommand) callconv(VCallConv) void,
    };

    fn vt(self: *const ConCommand) *const VTable {
        return @ptrCast(self.base._vt);
    }

    pub fn dispatch(self: *ConCommand, command: *const CCommand) void {
        self.vt().dispatch(self, command);
    }

    pub fn init(cmd: Data) ConCommand {
        return ConCommand{
            .base = .{
                ._vt = &ConCommand.vtable,
                .name = cmd.name,
                .flags = cmd.flags,
                .help_string = cmd.help_string,
            },
            .command_callback = cmd.command_callback,
            .completion_callback = cmd.completion_callback,
            .callback_flags = .{
                .has_completion_callback = cmd.completion_callback != null,
                .using_new_command_callback = true,
                .using_command_callback_interface = false,
            },
        };
    }

    pub fn register(self: *ConCommand) void {
        icvar.registerConCommandBase(@ptrCast(self));
    }
};

pub const IConVar = extern struct {
    _vt: *align(@alignOf(*anyopaque)) const anyopaque = &class_meta.vtable,

    var class_meta: abi.ClassMeta(VTable) = undefined;

    const VTable = switch (builtin.os.tag) {
        .windows => extern struct {
            setInt: *const fn (this: *anyopaque, value: c_int) callconv(VCallConv) void,
            setFloat: *const fn (this: *anyopaque, value: f32) callconv(VCallConv) void,
            setString: *const fn (this: *anyopaque, value: [*:0]const u8) callconv(VCallConv) void,
            getName: *const anyopaque,
            isFlagSet: *const anyopaque,
        },
        .linux => extern struct {
            setString: *const fn (this: *anyopaque, value: [*:0]const u8) callconv(VCallConv) void,
            setFloat: *const fn (this: *anyopaque, value: f32) callconv(VCallConv) void,
            setInt: *const fn (this: *anyopaque, value: c_int) callconv(VCallConv) void,
            getName: *const anyopaque,
            isFlagSet: *const anyopaque,
        },
        else => unreachable,
    };
};

pub const ConVar = extern struct {
    base1: ConCommandBase,
    base2: IConVar = .{
        ._vt = &IConVar.class_meta.vtable,
    },
    parent: ?*ConVar = null,
    default_value: [*:0]const u8,

    // Dynamically allocated
    string_value: ?[*:0]u8 = null,
    string_length: c_int = 0,

    float_value: f32 = 0.0,
    int_value: c_int = 0,

    has_min: bool = false,
    min_value: f32 = 0.0,
    has_max: bool = false,
    max_value: f32 = 0.0,

    change_callback: ?ChangeCallbackFn = null,

    pub const ChangeCallbackFn = *const fn (cvar: *IConVar, old_string: [*:0]const u8, old_value: f32) callconv(.c) void;

    pub const Data = struct {
        name: [*:0]const u8,
        default_value: [*:0]const u8,
        flags: FCvar = .{},
        help_string: [*:0]const u8 = "",
        min_value: ?f32 = null,
        max_value: ?f32 = null,
        change_callback: ?ConVar.ChangeCallbackFn = null,
    };

    var class_meta: abi.ClassMeta(VTable) = undefined;

    const VTable = switch (builtin.os.tag) {
        .windows => extern struct {
            base: ConCommandBase.VTable,
            _setString: *const anyopaque,
            _setFloat: *const anyopaque,
            _setInt: *const anyopaque,
            clampValue: *const anyopaque,
            changeStringValue: *const anyopaque,
            create: *const fn (
                this: *anyopaque,
                name: [*:0]const u8,
                default_value: [*:0]const u8,
                flags: FCvar,
                help_string: [*:0]const u8,
                has_min: bool,
                min_value: f32,
                has_max: bool,
                max_value: f32,
                callback: ?ChangeCallbackFn,
            ) callconv(VCallConv) void,
        },
        .linux => extern struct {
            base: ConCommandBase.VTable,
            setString: *const anyopaque,
            setFloat: *const anyopaque,
            setInt: *const anyopaque,
            _setString: *const anyopaque,
            _setFloat: *const anyopaque,
            _setInt: *const anyopaque,
            clampValue: *const anyopaque,
            changeStringValue: *const anyopaque,
            create: *const fn (
                this: *anyopaque,
                name: [*:0]const u8,
                default_value: [*:0]const u8,
                flags: FCvar,
                help_string: [*:0]const u8,
                has_min: bool,
                min_value: f32,
                has_max: bool,
                max_value: f32,
                callback: ?ChangeCallbackFn,
            ) callconv(VCallConv) void,
        },
        else => unreachable,
    };

    pub fn init(cvar: Data) ConVar {
        return ConVar{
            .base1 = .{
                ._vt = &ConVar.class_meta.vtable,
                .name = cvar.name,
                .flags = cvar.flags,
                .help_string = cvar.help_string,
            },
            .default_value = cvar.default_value,
            .has_min = cvar.min_value != null,
            .min_value = if (cvar.min_value) |v| v else 0.0,
            .has_max = cvar.max_value != null,
            .max_value = if (cvar.max_value) |v| v else 0.0,
            .change_callback = cvar.change_callback,
        };
    }

    fn vt1(self: *const ConVar) *const VTable {
        return @ptrCast(self.base1._vt);
    }

    fn vt2(self: *const ConVar) *const IConVar.VTable {
        return @ptrCast(self.base2._vt);
    }

    pub fn register(self: *ConVar) void {
        self.vt1().create(
            self,
            self.base1.name,
            self.default_value,
            self.base1.flags,
            self.base1.help_string,
            self.has_min,
            self.min_value,
            self.has_max,
            self.max_value,
            self.change_callback,
        );
    }

    pub fn getParent(self: *ConVar) *ConVar {
        if (self.parent) |parent| {
            return parent;
        }
        return self;
    }

    pub fn getParentConst(self: *const ConVar) *const ConVar {
        if (self.parent) |parent| {
            return parent;
        }
        return self;
    }

    pub fn getString(self: *const ConVar) [:0]const u8 {
        if (self.getParentConst().base1.flags.never_as_string) {
            return "FCVAR_NEVER_AS_STRING";
        }

        if (self.getParentConst().string_value) |s| {
            return std.mem.span(s);
        }

        return "";
    }

    pub fn getFloat(self: *const ConVar) f32 {
        return self.getParentConst().float_value;
    }

    pub fn getInt(self: *const ConVar) i32 {
        return self.getParentConst().int_value;
    }

    pub fn getBool(self: *const ConVar) bool {
        return self.getInt() != 0;
    }

    pub fn setString(self: *ConVar, value: [*:0]const u8) void {
        self.vt2().setString(&self.base2, value);
    }

    pub fn setFloat(self: *ConVar, value: f32) void {
        self.vt2().setFloat(&self.base2, value);
    }

    pub fn setInt(self: *ConVar, value: i32) void {
        self.vt2().setInt(&self.base2, @intCast(value));
    }
};

pub const Variable = extern struct {
    cvar: ConVar,
    next: ?*Variable = null,

    var vars: ?*Variable = null;

    pub fn init(cvar: ConVar.Data) Variable {
        return Variable{
            .cvar = ConVar.init(cvar),
        };
    }

    pub fn deinit(self: *Variable) void {
        if (self.cvar.string_value) |s| {
            tier0.allocator.free(std.mem.span(s));
            self.cvar.string_value = null;
        }
    }

    pub fn register(self: *Variable) void {
        self.cvar.register();

        self.next = Variable.vars;
        Variable.vars = self;
    }

    pub fn getString(self: *const Variable) [:0]const u8 {
        return self.cvar.getString();
    }

    pub fn getFloat(self: *const Variable) f32 {
        return self.cvar.getFloat();
    }

    pub fn getInt(self: *const Variable) i32 {
        return self.cvar.getInt();
    }

    pub fn getBool(self: *const Variable) bool {
        return self.cvar.getBool();
    }

    pub fn setString(self: *Variable, value: [*:0]const u8) void {
        self.cvar.setString(value);
    }

    pub fn setFloat(self: *Variable, value: f32) void {
        self.cvar.setFloat(value);
    }

    pub fn setInt(self: *Variable, value: i32) void {
        self.cvar.setInt(value);
    }
};

const ICvar = extern struct {
    _vt: *align(@alignOf(*anyopaque)) const anyopaque,

    const VTable = extern struct {
        base: interfaces.IAppSystem.VTable,

        allocateDLLIDentifier: *const fn (this: *anyopaque) callconv(VCallConv) c_int,

        registerConCommandBase: *const fn (this: *anyopaque, cmd: *ConCommandBase) callconv(VCallConv) void,
        unregisterConCommand: *const fn (this: *anyopaque, cmd: *ConCommandBase) callconv(VCallConv) void,
        unregisterConCommands: *const fn (this: *anyopaque, id: c_int) callconv(VCallConv) void,

        getCommandLineValue: *const anyopaque,

        // The order of const and non-const version of these function will be opposite on Linux, but should still work.
        findCommandBaseConst: *const anyopaque,
        findCommandBase: *const fn (this: *anyopaque, name: [*:0]const u8) callconv(VCallConv) ?*ConCommandBase,
        findVarConst: *const anyopaque,
        findVar: *const fn (this: *anyopaque, name: [*:0]const u8) callconv(VCallConv) ?*ConVar,
        findCommandConst: *const anyopaque,
        findCommand: *const fn (this: *anyopaque, name: [*:0]const u8) callconv(VCallConv) ?*ConCommand,

        getCommandsConst: *const anyopaque,
        getCommands: *const fn (this: *anyopaque) callconv(VCallConv) ?*ConCommandBase,

        installGlobalChangeCallback: *const anyopaque,
        removeGlobalChangeCallback: *const anyopaque,
        callGlobalChangeCallbacks: *const anyopaque,

        installConsoleDisplayFunc: *const anyopaque,
        removeConsoleDisplayFunc: *const anyopaque,
        consoleColorPrintf: *const anyopaque,
        consolePrintf: *const anyopaque,
        consoleDPrintf: *const anyopaque,

        revertFlaggedConVar: *const anyopaque,
        installCVarQuery: *const anyopaque,
    };

    var dll_identifier: c_int = undefined;

    fn vt(self: *const ICvar) *const VTable {
        return @ptrCast(self._vt);
    }

    fn allocateDLLIDentifier(self: *ICvar) void {
        dll_identifier = self.vt().allocateDLLIDentifier(self);
    }

    pub fn unregisterConCommand(self: *ICvar, cmd: *ConCommandBase) void {
        self.vt().unregisterConCommand(self, cmd);
    }

    fn unregisterConCommands(self: *ICvar) void {
        self.vt().unregisterConCommands(self, dll_identifier);
    }

    fn registerConCommandBase(self: *ICvar, cmd: *ConCommandBase) void {
        self.vt().registerConCommandBase(self, cmd);
        cmd.registered = true;
    }

    pub fn findCommandBase(self: *ICvar, name: [*:0]const u8) ?*ConCommandBase {
        return self.vt().findCommandBase(self, name);
    }

    pub fn findVar(self: *ICvar, name: [*:0]const u8) ?*ConVar {
        return self.vt().findVar(self, name);
    }

    pub fn findCommand(self: *ICvar, name: [*:0]const u8) ?*ConCommand {
        return self.vt().findCommand(self, name);
    }

    pub fn getCommands(self: *ICvar) ?*ConCommandBase {
        return self.vt().getCommands(self);
    }
};

pub var icvar: *ICvar = undefined;

pub var module: Module = .{
    .name = "tier1",
    .init = init,
    .deinit = deinit,
};

fn init() bool {
    icvar = @ptrCast(interfaces.engineFactory("VEngineCvar004", null) orelse {
        core.log.err("Failed to get ICvar interface", .{});
        return false;
    });

    icvar.allocateDLLIDentifier();

    const cvar = icvar.findVar("sv_gravity") orelse {
        core.log.err("Failed to get ConVar vtable", .{});
        return false;
    };
    const cmd = icvar.findCommand("kill") orelse {
        core.log.err("Failed to get ConCommand vtable", .{});
        return false;
    };

    // Stealing vtables from existing command and cvar
    const cvar_vt_ptr: *const ConVar.VTable = @ptrCast(cvar.base1._vt);
    ConVar.class_meta.vtable = cvar_vt_ptr.*;
    ConVar.class_meta.vtable.base.getDLLIdentifier = ConCommandBase.getDLLIdentifier;
    const cvar_rtti_ptr: [*]const *const anyopaque = @ptrCast(cvar.base1._vt);
    ConVar.class_meta.rtti = (cvar_rtti_ptr - 1)[0];
    if (builtin.os.tag == .linux) {
        ConVar.class_meta.top_offset = 0; // this is the top
    }

    const iconvar_vt_ptr: *const IConVar.VTable = @ptrCast(cvar.base2._vt);
    IConVar.class_meta.vtable = iconvar_vt_ptr.*;
    const iconvar_rtti_ptr: [*]const *const anyopaque = @ptrCast(cvar.base2._vt);
    IConVar.class_meta.rtti = (iconvar_rtti_ptr - 1)[0];
    if (builtin.os.tag == .linux) {
        IConVar.class_meta.top_offset = -@offsetOf(ConVar, "base2");
    }

    const cmd_vt_ptr: *const ConCommand.VTable = @ptrCast(cmd.base._vt);
    ConCommand.vtable = cmd_vt_ptr.*;
    ConCommand.vtable.base.getDLLIdentifier = ConCommandBase.getDLLIdentifier;

    return true;
}

fn deinit() void {
    icvar.unregisterConCommands();
    var it = Variable.vars;
    while (it) |curr| : (it = curr.next) {
        curr.deinit();
    }

    FileCompletion.deinitAll();
}
