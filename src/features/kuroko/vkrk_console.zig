const std = @import("std");

const modules = @import("../../modules.zig");
const tier0 = modules.tier0;
const tier1 = modules.tier1;
const engine = modules.engine;

const kuroko = @import("kuroko");
const VM = kuroko.KrkVM;
const KrkValue = kuroko.KrkValue;
const KrkString = kuroko.KrkString;
const KrkList = kuroko.KrkList;
const KrkInstance = kuroko.KrkInstance;
const KrkClass = kuroko.KrkClass;

const str_utils = @import("../../utils/str_utils.zig");

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
        \\@brief Create a new ConVar. Use `find_var` to get existing cvar.
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
        \\@brief Create and register a new ConCommand. Use `find_command` to get existing command.
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

    fn __init__(argc: c_int, argv: [*]const KrkValue, has_kw: c_int) callconv(.C) KrkValue {
        var name: [*:0]const u8 = undefined;
        var default_value: KrkValue = undefined;
        var help_string: ?[*:0]const u8 = null;
        var flags: i32 = 0;
        var min_value: KrkValue = KrkValue.noneValue();
        var max_value: KrkValue = KrkValue.noneValue();

        if (!kuroko.parseArgs(
            "__init__",
            argc,
            argv,
            has_kw,
            ".sV|ziVV",
            &.{
                "name",
                "default_value",
                "help_string",
                "flags",
                "min_value",
                "max_value",
            },
            .{
                &name,
                &default_value,
                &help_string,
                &flags,
                &min_value,
                &max_value,
            },
        )) {
            return KrkValue.noneValue();
        }

        if (!isConVar(argv[0])) {
            return VM.getInstance().exceptions.typeError.runtimeError("__init__() expects ConVar, not '%T'", .{argv[0].value});
        }

        const self = asConVar(argv[0]);

        if (tier1.icvar.findVar(name) != null) {
            return VM.getInstance().exceptions.valueError.runtimeError("name already exists.", .{min_value.value});
        }
        var default_string: [*:0]const u8 = undefined;
        var buf: [32]u8 = undefined;
        if (default_value.isString()) {
            default_string = default_value.asString().chars;
        } else if (default_value.isInt()) {
            const val = default_value.asInt();
            default_string = std.fmt.bufPrintZ(&buf, "{d}", .{val}) catch "";
        } else if (default_value.isFloat()) {
            const val: f32 = @floatCast(default_value.asFloat());
            default_string = std.fmt.bufPrintZ(&buf, "{d}", .{val}) catch "";
        } else {
            return VM.getInstance().exceptions.typeError.runtimeError("name expects str, int, or float, not '%T'", .{default_value.value});
        }

        if (help_string == null) {
            help_string = "";
        }

        var f_min: ?f32 = null;
        if (min_value.isFloat()) {
            f_min = @floatCast(min_value.asFloat());
        } else if (min_value.isInt()) {
            f_min = @floatFromInt(min_value.asInt());
        } else if (!min_value.isNone()) {
            return VM.getInstance().exceptions.typeError.runtimeError("min_value expects int or float, not '%T'", .{min_value.value});
        }

        var f_max: ?f32 = null;
        if (max_value.isFloat()) {
            f_max = @floatCast(max_value.asFloat());
        } else if (max_value.isInt()) {
            f_max = @floatFromInt(max_value.asInt());
        } else if (!max_value.isNone()) {
            return VM.getInstance().exceptions.typeError.runtimeError("max_value expects int or float, not '%T'", .{max_value.value});
        }

        const dyn_cvar = DynConVar.create(
            .{
                .name = name,
                .default_value = default_string,
                .flags = @bitCast(flags),
                .help_string = help_string.?,
                .min_value = f_min,
                .max_value = f_max,
                .change_callback = null,
            },
        ) catch unreachable;
        dyn_cvar.register();

        self.cvar = &dyn_cvar.cvar;
        return KrkValue.noneValue();
    }

    fn __repr__(argc: c_int, argv: [*]const KrkValue, has_kw: c_int) callconv(.C) KrkValue {
        _ = has_kw;
        if (argc != 1) {
            return VM.getInstance().exceptions.argumentError.runtimeError("__repr__() takes no arguments (%d given)", .{argc - 1});
        }

        if (!isConVar(argv[0])) {
            return VM.getInstance().exceptions.typeError.runtimeError("__repr__() expects ConVar, not '%T'", .{argv[0].value});
        }

        const self = asConVar(argv[0]);
        return KrkValue.stringFromFormat("<ConVar %s at %p>", .{ self.cvar.base1.name, @intFromPtr(self) });
    }

    fn get_name(argc: c_int, argv: [*]const KrkValue, has_kw: c_int) callconv(.C) KrkValue {
        _ = has_kw;
        if (argc != 1) {
            return VM.getInstance().exceptions.argumentError.runtimeError("get_name() takes no arguments (%d given)", .{argc - 1});
        }

        if (!isConVar(argv[0])) {
            return VM.getInstance().exceptions.typeError.runtimeError("get_name() expects ConVar, not '%T'", .{argv[0].value});
        }

        const self = asConVar(argv[0]);
        return KrkString.copyString(self.cvar.base1.name).asValue();
    }

    fn get_default(argc: c_int, argv: [*]const KrkValue, has_kw: c_int) callconv(.C) KrkValue {
        _ = has_kw;
        if (argc != 1) {
            return VM.getInstance().exceptions.argumentError.runtimeError("get_default() takes no arguments (%d given)", .{argc - 1});
        }

        if (!isConVar(argv[0])) {
            return VM.getInstance().exceptions.typeError.runtimeError("get_default() expects ConVar, not '%T'", .{argv[0].value});
        }

        const self = asConVar(argv[0]);
        return KrkString.copyString(self.cvar.default_value).asValue();
    }

    fn set_value(argc: c_int, argv: [*]const KrkValue, has_kw: c_int) callconv(.C) KrkValue {
        _ = has_kw;
        if (argc != 2) {
            return VM.getInstance().exceptions.argumentError.runtimeError("set_value() takes exactly 1 argument (%d given)", .{argc - 1});
        }

        if (!isConVar(argv[0])) {
            return VM.getInstance().exceptions.typeError.runtimeError("set_value() expects ConVar, not '%T'", .{argv[0].value});
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

        if (!isConVar(argv[0])) {
            return VM.getInstance().exceptions.typeError.runtimeError("get_string() expects ConVar, not '%T'", .{argv[0].value});
        }

        const self = asConVar(argv[0]);
        return KrkString.copyString(self.cvar.getString()).asValue();
    }

    fn get_float(argc: c_int, argv: [*]const KrkValue, has_kw: c_int) callconv(.C) KrkValue {
        _ = has_kw;
        if (argc != 1) {
            return VM.getInstance().exceptions.argumentError.runtimeError("get_float() takes no arguments (%d given)", .{argc - 1});
        }

        if (!isConVar(argv[0])) {
            return VM.getInstance().exceptions.typeError.runtimeError("get_float() expects ConVar, not '%T'", .{argv[0].value});
        }

        const self = asConVar(argv[0]);
        return KrkValue.floatValue(self.cvar.getFloat());
    }

    fn get_int(argc: c_int, argv: [*]const KrkValue, has_kw: c_int) callconv(.C) KrkValue {
        _ = has_kw;
        if (argc != 1) {
            return VM.getInstance().exceptions.argumentError.runtimeError("get_int() takes no arguments (%d given)", .{argc - 1});
        }

        if (!isConVar(argv[0])) {
            return VM.getInstance().exceptions.typeError.runtimeError("get_int() expects ConVar, not '%T'", .{argv[0].value});
        }

        const self = asConVar(argv[0]);
        return KrkValue.intValue(self.cvar.getInt());
    }

    fn get_bool(argc: c_int, argv: [*]const KrkValue, has_kw: c_int) callconv(.C) KrkValue {
        _ = has_kw;
        if (argc != 1) {
            return VM.getInstance().exceptions.argumentError.runtimeError("get_bool() takes no arguments (%d given)", .{argc - 1});
        }

        if (!isConVar(argv[0])) {
            return VM.getInstance().exceptions.typeError.runtimeError("get_bool() expects ConVar, not '%T'", .{argv[0].value});
        }

        const self = asConVar(argv[0]);
        return KrkValue.boolValue(self.cvar.getBool());
    }
};

const ConCommand = extern struct {
    inst: KrkInstance,
    command: ?*tier1.ConCommand,

    flags: i32 = 0,
    completion_callback: KrkValue,

    var class: *KrkClass = undefined;

    fn isConCommand(v: KrkValue) bool {
        return v.isInstanceOf(class);
    }

    fn asConCommand(v: KrkValue) *ConCommand {
        return @ptrCast(v.asObject());
    }

    fn createCommand(self: KrkValue, callback: KrkValue, flags: i32, completion_callback: KrkValue) KrkValue {
        const inst = asConCommand(self);
        const v_name = callback.getAttribute("__name__");
        if (v_name.isNone()) {
            return KrkValue.noneValue();
        }
        const name = v_name.asString().chars;

        const v_doc = callback.getAttributeDefault("__doc__", KrkValue.noneValue());
        var help_string: [*:0]const u8 = "";
        if (v_doc.isString()) {
            help_string = v_doc.asString().chars;
        }

        const dyn_cmd = DynConCommand.create(.{
            .name = name,
            .help_string = help_string,
            .flags = @bitCast(flags),
            .callback = callback,
            .completion_callback = completion_callback,
        }) catch unreachable;
        dyn_cmd.register();

        inst.command = &dyn_cmd.cmd;
        return self;
    }

    fn __init__(argc: c_int, argv: [*]const KrkValue, has_kw: c_int) callconv(.C) KrkValue {
        var callback: KrkValue = KrkValue.noneValue();
        var completion: KrkValue = KrkValue.noneValue();
        var flags: i32 = 0;

        if (!kuroko.parseArgs(
            "__init__",
            argc,
            argv,
            has_kw,
            ".|ViV",
            &.{
                "callback",
                "flags",
                "completion",
            },
            .{
                &callback,
                &flags,
                &completion,
            },
        )) {
            return KrkValue.noneValue();
        }

        if (!isConCommand(argv[0])) {
            return VM.getInstance().exceptions.typeError.runtimeError("__init__() expects ConCommand, not '%T'", .{argv[0].value});
        }

        const inst = asConCommand(argv[0]);
        if (callback.isNone()) {
            inst.flags = flags;
            inst.completion_callback = completion;
            return KrkValue.noneValue();
        }

        const result = createCommand(argv[0], callback, flags, completion);
        if (VM.getCurrentThread().flags.thread_has_exception) {
            return result;
        }
        return KrkValue.noneValue();
    }

    fn __call__(argc: c_int, argv: [*]const KrkValue, has_kw: c_int) callconv(.C) KrkValue {
        _ = has_kw;
        if (argc < 1) {
            return VM.getInstance().exceptions.argumentError.runtimeError("__call__() required self", .{});
        }

        if (!isConCommand(argv[0])) {
            return VM.getInstance().exceptions.typeError.runtimeError("__call__() expects ConCommand, not '%T'", .{argv[0].value});
        }

        const self = asConCommand(argv[0]);
        if (self.command == null) {
            if (argc != 2) {
                return VM.getInstance().exceptions.argumentError.runtimeError("__call__() should be use as a decorator when ConCommand is not initialized", .{});
            }
            return createCommand(argv[0], argv[1], self.flags, self.completion_callback);
        }

        const command = self.command.?;

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

    fn __repr__(argc: c_int, argv: [*]const KrkValue, has_kw: c_int) callconv(.C) KrkValue {
        _ = has_kw;
        if (argc != 1) {
            return VM.getInstance().exceptions.argumentError.runtimeError("__repr__() takes no arguments (%d given)", .{argc - 1});
        }

        if (!isConCommand(argv[0])) {
            return VM.getInstance().exceptions.typeError.runtimeError("__repr__() expects ConCommand, not '%T'", .{argv[0].value});
        }

        const self = asConCommand(argv[0]);
        if (self.command) |command| {
            return KrkValue.stringFromFormat("<ConCommand %s at %p>", .{ command.base.name, @intFromPtr(self) });
        }

        return KrkValue.stringFromFormat("<ConCommand decorator at %p>", .{@intFromPtr(self)});
    }

    fn get_name(argc: c_int, argv: [*]const KrkValue, has_kw: c_int) callconv(.C) KrkValue {
        _ = has_kw;
        if (argc != 1) {
            return VM.getInstance().exceptions.argumentError.runtimeError("get_name() takes no arguments (%d given)", .{argc - 1});
        }

        if (!isConCommand(argv[0])) {
            return VM.getInstance().exceptions.typeError.runtimeError("get_name() expects ConCommand, not '%T'", .{argv[0].value});
        }

        const self = asConCommand(argv[0]);
        if (self.command) |command| {
            return KrkString.copyString(command.base.name).asValue();
        }

        return VM.getInstance().exceptions.Exception.runtimeError("ConCommand not initialized", .{});
    }
};

const DynConVar = struct {
    cvar: tier1.ConVar,
    next: ?*DynConVar = null,

    var vars: ?*DynConVar = null;

    fn create(cvar: tier1.ConVar.Data) !*DynConVar {
        const copy_name = try tier0.allocator.dupeZ(u8, std.mem.span(cvar.name));
        errdefer tier0.allocator.free(copy_name);
        const copy_default = try tier0.allocator.dupeZ(u8, std.mem.span(cvar.default_value));
        errdefer tier0.allocator.free(copy_default);
        const copy_help = try tier0.allocator.dupeZ(u8, std.mem.span(cvar.help_string));
        errdefer tier0.allocator.free(copy_help);

        var copy_cvar: tier1.ConVar.Data = cvar;
        copy_cvar.name = copy_name;
        copy_cvar.default_value = copy_default;
        copy_cvar.help_string = copy_help;

        const result = try tier0.allocator.create(DynConVar);
        result.* = .{
            .cvar = tier1.ConVar.init(copy_cvar),
        };

        return result;
    }

    fn register(self: *DynConVar) void {
        self.cvar.register();

        self.next = DynConVar.vars;
        DynConVar.vars = self;
    }

    fn deinit(self: *DynConVar) void {
        if (self.cvar.string_value) |s| {
            tier0.allocator.free(std.mem.span(s));
            self.cvar.string_value = null;
        }
        tier0.allocator.free(std.mem.span(self.cvar.base1.name));
        tier0.allocator.free(std.mem.span(self.cvar.base1.help_string));
        tier0.allocator.free(std.mem.span(self.cvar.default_value));
    }
};

const DynConCommand = struct {
    cmd: tier1.ConCommand,
    callback: KrkValue,
    completion_callback: KrkValue,
    next: ?*DynConCommand = null,

    var cmds: ?*DynConCommand = null;

    fn findDynConCommand(name: []const u8) ?*DynConCommand {
        var it = cmds;
        while (it) |command| : (it = command.next) {
            if (std.mem.eql(u8, name, std.mem.span(command.cmd.base.name))) {
                return command;
            }
        }

        return null;
    }

    fn vkrkCommandCallback(args: *const tier1.CCommand) callconv(.C) void {
        if (args.argc < 1) {
            std.log.warn("vkrk: No command name.", .{});
            return;
        }

        const name = std.mem.span(args.argv[0]);
        if (findDynConCommand(name)) |command| {
            VM.push(command.callback);

            const list = KrkList.listOf(0, null, false);
            VM.push(list);

            var i: u32 = 0;
            while (i < args.argc) : (i += 1) {
                list.asList().append(KrkString.copyString(args.argv[i]).asValue());
            }

            _ = VM.callStack(1);
            VM.resetStack();
        } else {
            std.log.warn("vkrk: Unknown command.", .{});
        }
    }

    const CommandCompletionContext = extern struct {
        commands: *[tier1.ConCommand.completion_max_items][tier1.ConCommand.completion_item_length]u8,
        count: u32 = 0,
    };

    fn commandCompletionUnpackCallback(
        context: *anyopaque,
        values: [*]const KrkValue,
        count: usize,
    ) callconv(.C) c_int {
        const completion: *align(1) CommandCompletionContext = @ptrCast(context);
        var i: usize = 0;
        while (i < count) : (i += 1) {
            const value = values[i];
            if (!value.isString()) {
                std.log.warn("vkrk: Command completion expects to return an iterable of strings.", .{});
                return 1;
            }

            if (completion.count >= tier1.ConCommand.completion_max_items) {
                return 1;
            }

            const s = std.mem.span(value.asString().chars);
            str_utils.copyToBufferZ(u8, &completion.commands[completion.count], s);
            completion.count += 1;
        }

        return 0;
    }

    fn vkrkCommandCompletionCallback(
        partial: [*:0]const u8,
        commands: *[tier1.ConCommand.completion_max_items][tier1.ConCommand.completion_item_length]u8,
    ) callconv(.C) c_int {
        const line = std.mem.span(partial);
        const name = if (std.mem.indexOf(u8, line, " ")) |index| line[0..index] else line;
        if (findDynConCommand(name)) |command| {
            if (!command.completion_callback.isNone()) {
                return 0;
            }
            VM.push(command.completion_callback);
            VM.push(KrkString.copyString(partial).asValue());
            const result = VM.callStack(1);
            var context: CommandCompletionContext = .{
                .commands = commands,
            };
            _ = result.unpackIterable(&context, commandCompletionUnpackCallback);
            VM.resetStack();
            return @intCast(context.count);
        } else {
            std.log.warn("vkrk: Unknown command to complete.", .{});
        }

        return 0;
    }

    fn create(command: struct {
        name: [*:0]const u8,
        help_string: [*:0]const u8,
        flags: tier1.FCvar = .{},
        callback: KrkValue,
        completion_callback: KrkValue,
    }) !*DynConCommand {
        const copy_name = try tier0.allocator.dupeZ(u8, std.mem.span(command.name));
        errdefer tier0.allocator.free(copy_name);
        const copy_help = try tier0.allocator.dupeZ(u8, std.mem.span(command.help_string));
        errdefer tier0.allocator.free(copy_help);

        const completion_callback: ?tier1.ConCommand.CommandCompletionCallbackFn = if (command.completion_callback.isNone()) null else vkrkCommandCompletionCallback;

        const copy_cmd: tier1.ConCommand.Data = .{
            .name = copy_name,
            .help_string = copy_help,
            .flags = command.flags,
            .command_callback = vkrkCommandCallback,
            .completion_callback = completion_callback,
        };

        const result = try tier0.allocator.create(DynConCommand);
        result.* = .{
            .cmd = tier1.ConCommand.init(copy_cmd),
            .callback = command.callback,
            .completion_callback = command.completion_callback,
        };

        return result;
    }

    fn register(self: *DynConCommand) void {
        self.cmd.register();

        self.next = DynConCommand.cmds;
        DynConCommand.cmds = self;
    }

    fn deinit(self: *DynConCommand) void {
        tier0.allocator.free(std.mem.span(self.cmd.base.name));
        tier0.allocator.free(std.mem.span(self.cmd.base.help_string));
    }
};

pub fn destroyDynCommands() void {
    var cvar = DynConVar.vars;
    while (cvar) |curr| {
        tier1.icvar.unregisterConCommand(@ptrCast(&curr.cvar));
        curr.deinit();

        cvar = curr.next;
        tier0.allocator.destroy(curr);
    }

    var command = DynConCommand.cmds;
    while (command) |curr| {
        tier1.icvar.unregisterConCommand(@ptrCast(&curr.cmd));
        curr.deinit();

        command = curr.next;
        tier0.allocator.destroy(curr);
    }
}
