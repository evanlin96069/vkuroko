const std = @import("std");

const modules = @import("../../modules.zig");
const tier0 = modules.tier0;
const tier1 = modules.tier1;
const engine = modules.engine;

const kuroko = @import("kuroko");
const VM = kuroko.KrkVM;
const KrkValue = kuroko.KrkValue;
const KrkString = kuroko.KrkString;
const KrkInstance = kuroko.KrkInstance;
const KrkClass = kuroko.KrkClass;

pub fn bindAttributes(module: *KrkInstance) void {
    module.bindFunction("cmd", cmd).setDoc(
        \\@brief Runs a console command.
        \\@arguments command
        \\
        \\Runs @p command using `IVEngineClient::ClientCmd`.
    );
    module.bindFunction("find_var", find_var).setDoc(
        \\@brief Finds a `ConVar`.
        \\@arguments name
        \\@return `ConVar` if found, `None` if not found.
    );
    module.bindFunction("find_command", find_command).setDoc(
        \\@brief Finds a `ConCommand`.
        \\@arguments name
        \\@return `ConCommand` if found, `None` if not found.
    );

    ConVar.class = KrkClass.makeClass(module, ConVar, "ConVar", null);
    ConVar.class.setDoc("Interface to a ConVar.");
    ConVar.class.alloc_size = @sizeOf(ConVar);
    ConVar.class.bindMethod("get_name", ConVar.get_name).setDoc(
        \\@brief Get the name of the ConVar.
    );
    ConVar.class.bindMethod("get_default", ConVar.get_default).setDoc(
        \\@brief Get the default string value of the ConVar.
    );
    ConVar.class.bindMethod("set_value", ConVar.set_value).setDoc(
        \\@brief Set the value of the ConVar.
        \\@arguments value
        \\
        \\@p value can be str, float, int, or bool.
    );
    ConVar.class.bindMethod("get_string", ConVar.get_string).setDoc(
        \\@brief Get the string value of the ConVar.
    );
    ConVar.class.bindMethod("get_float", ConVar.get_float).setDoc(
        \\@brief Get the float value of the ConVar.
    );
    ConVar.class.bindMethod("get_int", ConVar.get_int).setDoc(
        \\@brief Get the int value of the ConVar.
    );
    ConVar.class.bindMethod("get_bool", ConVar.get_bool).setDoc(
        \\@brief Get the bool value of the ConVar.
    );
    _ = ConVar.class.bindMethod("__repr__", ConVar.__repr__);
    ConVar.class.bindMethod("__init__", ConVar.__init__).setDoc(
        \\@note ConVar objects can not be initialized using this constructor.
    );
    ConVar.class.finalizeClass();

    ConCommand.class = KrkClass.makeClass(module, ConCommand, "ConCommand", null);
    ConCommand.class.setDoc("Interface to a ConCommand.");
    ConCommand.class.alloc_size = @sizeOf(ConCommand);
    ConCommand.class.bindMethod("get_name", ConCommand.get_name).setDoc(
        \\@brief Get the name of the ConVar.
    );
    _ = ConCommand.class.bindMethod("__repr__", ConCommand.__repr__);
    ConCommand.class.bindMethod("__init__", ConCommand.__init__).setDoc(
        \\@note ConVar objects can not be initialized using this constructor.
    );
    ConCommand.class.bindMethod("__call__", ConCommand.__call__).setDoc(
        \\@brief Invokes the callback function of the command.
    );
    ConCommand.class.finalizeClass();
}

fn cmd(argc: c_int, argv: [*]const KrkValue, has_kw: c_int) callconv(.C) KrkValue {
    var command: [*:0]const u8 = undefined;
    if (!kuroko.parseArgs(
        "cmd",
        argc,
        argv,
        has_kw,
        "s",
        &.{"command"},
        .{&command},
    )) {
        return KrkValue.noneValue();
    }

    engine.client.clientCmd(command);

    return KrkValue.noneValue();
}

fn find_var(argc: c_int, argv: [*]const KrkValue, has_kw: c_int) callconv(.C) KrkValue {
    var name: [*:0]const u8 = undefined;
    if (!kuroko.parseArgs(
        "find_var",
        argc,
        argv,
        has_kw,
        "s",
        &.{"name"},
        .{&name},
    )) {
        return KrkValue.noneValue();
    }

    const cvar = tier1.icvar.findVar(name) orelse {
        return KrkValue.noneValue();
    };

    const inst = KrkInstance.create(ConVar.class);
    const cvar_inst: *ConVar = @ptrCast(inst);
    cvar_inst.cvar = cvar;

    return inst.asValue();
}

fn find_command(argc: c_int, argv: [*]const KrkValue, has_kw: c_int) callconv(.C) KrkValue {
    var name: [*:0]const u8 = undefined;
    if (!kuroko.parseArgs(
        "find_command",
        argc,
        argv,
        has_kw,
        "s",
        &.{"name"},
        .{&name},
    )) {
        return KrkValue.noneValue();
    }

    const command = tier1.icvar.findCommand(name) orelse {
        return KrkValue.noneValue();
    };

    const inst = KrkInstance.create(ConCommand.class);
    const command_inst: *ConCommand = @ptrCast(inst);
    command_inst.command = command;

    return inst.asValue();
}

const ConVar = extern struct {
    inst: KrkInstance,
    cvar: *tier1.ConVar,

    var class: *KrkClass = undefined;

    fn isConVar(v: KrkValue) bool {
        return v.isInstanceOf(class);
    }

    fn asConVar(v: KrkValue) *ConVar {
        return @ptrCast(v.asObject());
    }

    fn __repr__(argc: c_int, argv: [*]const KrkValue, has_kw: c_int) callconv(.C) KrkValue {
        _ = has_kw;
        if (argc != 1) {
            return VM.getInstance().exceptions.argumentError.runtimeError("__repr__() takes no arguments (%d given)", .{argc - 1});
        }

        const self = asConVar(argv[0]);
        return KrkValue.stringFromFormat("<ConVar %s at %p>", .{ self.cvar.base1.name, @intFromPtr(self) });
    }

    fn __init__(argc: c_int, argv: [*]const KrkValue, has_kw: c_int) callconv(.C) KrkValue {
        _ = argc;
        _ = argv;
        _ = has_kw;
        return VM.getInstance().exceptions.typeError.runtimeError("ConVar objects can not be instantiated.", .{});
    }

    fn get_name(argc: c_int, argv: [*]const KrkValue, has_kw: c_int) callconv(.C) KrkValue {
        _ = has_kw;
        if (argc != 1) {
            return VM.getInstance().exceptions.argumentError.runtimeError("get_name() takes no arguments (%d given)", .{argc - 1});
        }

        const self = asConVar(argv[0]);
        return KrkString.copyString(self.cvar.base1.name).asValue();
    }

    fn get_default(argc: c_int, argv: [*]const KrkValue, has_kw: c_int) callconv(.C) KrkValue {
        _ = has_kw;
        if (argc != 1) {
            return VM.getInstance().exceptions.argumentError.runtimeError("get_default() takes no arguments (%d given)", .{argc - 1});
        }

        const self = asConVar(argv[0]);
        return KrkString.copyString(self.cvar.default_value).asValue();
    }

    fn set_value(argc: c_int, argv: [*]const KrkValue, has_kw: c_int) callconv(.C) KrkValue {
        _ = has_kw;
        if (argc != 2) {
            return VM.getInstance().exceptions.argumentError.runtimeError("set_value() takes exactly 1 argument (%d given)", .{argc - 1});
        }

        const self = asConVar(argv[0]);

        const value = argv[1];
        if (value.isString()) {
            self.cvar.setString(value.asCString());
        } else if (value.isFloat()) {
            self.cvar.setFloat(@floatCast(value.asFloat()));
        } else if (value.isInt()) {
            self.cvar.setInt(@intCast(value.asInt()));
        } else if (value.isBool()) {
            self.cvar.setInt(@intFromBool(value.asBool()));
        } else {
            return VM.getInstance().exceptions.typeError.runtimeError("bad value type for set_value()", .{});
        }

        return KrkValue.noneValue();
    }

    fn get_string(argc: c_int, argv: [*]const KrkValue, has_kw: c_int) callconv(.C) KrkValue {
        _ = has_kw;
        if (argc != 1) {
            return VM.getInstance().exceptions.argumentError.runtimeError("get_string() takes no arguments (%d given)", .{argc - 1});
        }

        const self = asConVar(argv[0]);
        return KrkString.copyString(self.cvar.getString()).asValue();
    }

    fn get_float(argc: c_int, argv: [*]const KrkValue, has_kw: c_int) callconv(.C) KrkValue {
        _ = has_kw;
        if (argc != 1) {
            return VM.getInstance().exceptions.argumentError.runtimeError("get_float() takes no arguments (%d given)", .{argc - 1});
        }

        const self = asConVar(argv[0]);
        return KrkValue.floatValue(self.cvar.getFloat());
    }

    fn get_int(argc: c_int, argv: [*]const KrkValue, has_kw: c_int) callconv(.C) KrkValue {
        _ = has_kw;
        if (argc != 1) {
            return VM.getInstance().exceptions.argumentError.runtimeError("get_int() takes no arguments (%d given)", .{argc - 1});
        }

        const self = asConVar(argv[0]);
        return KrkValue.intValue(self.cvar.getInt());
    }

    fn get_bool(argc: c_int, argv: [*]const KrkValue, has_kw: c_int) callconv(.C) KrkValue {
        _ = has_kw;
        if (argc != 1) {
            return VM.getInstance().exceptions.argumentError.runtimeError("get_bool() takes no arguments (%d given)", .{argc - 1});
        }

        const self = asConVar(argv[0]);
        return KrkValue.boolValue(self.cvar.getBool());
    }
};

const ConCommand = extern struct {
    inst: KrkInstance,
    command: *tier1.ConCommand,

    var class: *KrkClass = undefined;

    fn isConCommand(v: KrkValue) bool {
        return v.isInstanceOf(class);
    }

    fn asConCommand(v: KrkValue) *ConCommand {
        return @ptrCast(v.asObject());
    }

    fn __repr__(argc: c_int, argv: [*]const KrkValue, has_kw: c_int) callconv(.C) KrkValue {
        _ = has_kw;
        if (argc != 1) {
            return VM.getInstance().exceptions.argumentError.runtimeError("__repr__() takes no arguments (%d given)", .{argc - 1});
        }

        const self = asConCommand(argv[0]);
        return KrkValue.stringFromFormat("<ConCommand %s at %p>", .{ self.command.base.name, @intFromPtr(self) });
    }

    fn __init__(argc: c_int, argv: [*]const KrkValue, has_kw: c_int) callconv(.C) KrkValue {
        _ = argc;
        _ = argv;
        _ = has_kw;
        return VM.getInstance().exceptions.typeError.runtimeError("ConCommand objects can not be instantiated.", .{});
    }

    fn __call__(argc: c_int, argv: [*]const KrkValue, has_kw: c_int) callconv(.C) KrkValue {
        _ = has_kw;
        if (argc < 1) {
            return VM.getInstance().exceptions.argumentError.runtimeError("__call__() required self", .{});
        }

        const self = asConCommand(argv[0]);
        const command = self.command;

        const max_length = tier1.CCommand.max_length;
        const max_argc = tier1.CCommand.max_argc;

        if (argc > max_argc) {
            return VM.getInstance().exceptions.argumentError.runtimeError("Too many arguments", .{});
        }

        var ccmd: tier1.CCommand = .{
            .argc = argc,
            .argv_0_size = @intCast(std.mem.len(command.base.name)),
            .args_buffer = std.mem.zeroes([max_length]u8),
            .argv_buffer = std.mem.zeroes([max_length]u8),
            .argv = undefined,
        };

        var buffer_index: u32 = 0;
        var i: u32 = 0;
        while (i < argc) : (i += 1) {
            var arg: []const u8 = undefined;
            if (i == 0) {
                arg = std.mem.span(command.base.name);
            } else {
                if (!argv[i].isString()) {
                    return VM.getInstance().exceptions.typeError.runtimeError("Expected str", .{});
                }
                arg = std.mem.span(argv[i].asString().chars);
            }

            if (buffer_index + arg.len >= max_length or buffer_index + arg.len + 1 >= max_length) {
                return VM.getInstance().exceptions.argumentError.runtimeError("Arguments too long", .{});
            }

            std.mem.copyForwards(u8, ccmd.args_buffer[buffer_index..], arg);
            ccmd.args_buffer[buffer_index + arg.len] = if (i + 1 == argc) 0 else ' ';
            std.mem.copyForwards(u8, ccmd.argv_buffer[buffer_index..], arg);
            ccmd.argv_buffer[buffer_index + arg.len] = 0;
            ccmd.argv[i] = @ptrCast(ccmd.argv_buffer[buffer_index..].ptr);
            buffer_index += arg.len + 1;
        }

        command.dispatch(&ccmd);

        return KrkValue.noneValue();
    }

    fn get_name(argc: c_int, argv: [*]const KrkValue, has_kw: c_int) callconv(.C) KrkValue {
        _ = has_kw;
        if (argc != 1) {
            return VM.getInstance().exceptions.argumentError.runtimeError("get_name() takes no arguments (%d given)", .{argc - 1});
        }

        const self = asConCommand(argv[0]);
        return KrkString.copyString(self.command.base.name).asValue();
    }
};
