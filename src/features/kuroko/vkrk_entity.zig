const std = @import("std");

const vkrk = @import("kuroko.zig");

const game_detection = @import("../../utils/game_detection.zig");
const entlist = @import("../entlist.zig");
const playerio = @import("../playerio.zig");
const datamap = @import("../datamap.zig");

const modules = @import("../../modules.zig");
const client = modules.client;

const sdk = @import("sdk");

const kuroko = @import("kuroko");
const VM = kuroko.KrkVM;
const KrkValue = kuroko.KrkValue;
const KrkString = kuroko.KrkString;
const KrkClass = kuroko.KrkClass;
const KrkInstance = kuroko.KrkInstance;
const KrkList = kuroko.KrkList;
const KrkTuple = kuroko.KrkTuple;

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

pub const Entity = extern struct {
    inst: KrkInstance,
    index: u32,
    is_server: bool,

    var class: *KrkClass = undefined;

    fn isEntity(v: KrkValue) bool {
        return v.isInstanceOf(class);
    }

    fn asEntity(v: KrkValue) *Entity {
        return @ptrCast(v.asObject());
    }

    fn resolveEntity(self: *const Entity) ?*anyopaque {
        if (self.is_server) {
            if (entlist.server_list.getEntity(self.index)) |ent| {
                return @ptrCast(ent);
            }
        } else {
            if (entlist.client_list.getEntity(self.index)) |ent| {
                return @ptrCast(ent);
            }
        }
        return null;
    }

    fn getClassName(self: *const Entity) ?[*:0]const u8 {
        if (self.is_server) {
            if (entlist.server_list.getEntity(self.index)) |ent| {
                const name = entlist.server_list.getNetworkClassName(ent);
                if (name[0] == 0) return null;
                return name;
            }
        } else {
            if (entlist.client_list.getEntity(self.index)) |ent| {
                const name = entlist.client_list.getNetworkClassName(ent);
                if (name[0] == 0) return null;
                return name;
            }
        }
        return null;
    }

    fn readFieldValue(field_type: sdk.DataMap.FieldType, ptr: *anyopaque, offset: usize) KrkValue {
        switch (field_type) {
            .float, .time => {
                const val = datamap.getField(f32, ptr, offset);
                return KrkValue.floatValue(val.*);
            },
            .integer, .tick, .model_index, .material_index => {
                const val = datamap.getField(c_int, ptr, offset);
                return KrkValue.intValue(val.*);
            },
            .boolean => {
                const val = datamap.getField(bool, ptr, offset);
                return KrkValue.boolValue(val.*);
            },
            .short => {
                const val = datamap.getField(c_short, ptr, offset);
                return KrkValue.intValue(val.*);
            },
            .character => {
                const val = datamap.getField(u8, ptr, offset);
                return KrkValue.intValue(val.*);
            },
            .vector, .position_vector => {
                const val = datamap.getField(sdk.Vector, ptr, offset);
                return vkrk_types.Vector.create(val.*);
            },
            .ehandle => {
                const val = datamap.getField(sdk.CBaseHandle, ptr, offset);
                if (val.isValid()) {
                    return KrkValue.intValue(val.getEntryIndex());
                }
                return KrkValue.noneValue();
            },
            .color32 => {
                const val = datamap.getField(sdk.Color, ptr, offset);
                const tuple = KrkTuple.create(4);
                VM.push(tuple.asValue());
                tuple.values.values[0] = KrkValue.intValue(val.r);
                tuple.values.values[1] = KrkValue.intValue(val.g);
                tuple.values.values[2] = KrkValue.intValue(val.b);
                tuple.values.values[3] = KrkValue.intValue(val.a);
                tuple.values.count = 4;
                return VM.pop();
            },
            .vector2d => {
                const base: [*]u8 = @ptrCast(ptr);
                const aligned: *const [2]f32 = @ptrCast(@alignCast(base + offset));
                const tuple = KrkTuple.create(2);
                VM.push(tuple.asValue());
                tuple.values.values[0] = KrkValue.floatValue(aligned[0]);
                tuple.values.values[1] = KrkValue.floatValue(aligned[1]);
                tuple.values.count = 2;
                return VM.pop();
            },
            else => {
                return KrkValue.noneValue();
            },
        }
    }

    fn writeFieldValue(field_type: sdk.DataMap.FieldType, ptr: *anyopaque, offset: usize, value: KrkValue) KrkValue {
        switch (field_type) {
            .float, .time => {
                if (value.isFloat()) {
                    datamap.getField(f32, ptr, offset).* = @floatCast(value.asFloat());
                    return KrkValue.noneValue();
                } else if (value.isInt()) {
                    datamap.getField(f32, ptr, offset).* = @floatFromInt(value.asInt());
                    return KrkValue.noneValue();
                }
                return VM.getInstance().exceptions.typeError.runtimeError("Expected float, got '%T'", .{value.value});
            },
            .integer, .tick, .model_index, .material_index => {
                if (value.isInt()) {
                    const int_val = std.math.cast(c_int, value.asInt()) orelse {
                        return VM.getInstance().exceptions.valueError.runtimeError("Integer value out of range", .{});
                    };
                    datamap.getField(c_int, ptr, offset).* = int_val;
                    return KrkValue.noneValue();
                }
                return VM.getInstance().exceptions.typeError.runtimeError("Expected int, got '%T'", .{value.value});
            },
            .boolean => {
                if (value.isBool()) {
                    datamap.getField(bool, ptr, offset).* = value.asBool();
                    return KrkValue.noneValue();
                }
                return VM.getInstance().exceptions.typeError.runtimeError("Expected bool, got '%T'", .{value.value});
            },
            .short => {
                if (value.isInt()) {
                    const int_val = std.math.cast(c_short, value.asInt()) orelse {
                        return VM.getInstance().exceptions.valueError.runtimeError("Integer value out of range for short", .{});
                    };
                    datamap.getField(c_short, ptr, offset).* = int_val;
                    return KrkValue.noneValue();
                }
                return VM.getInstance().exceptions.typeError.runtimeError("Expected int, got '%T'", .{value.value});
            },
            .character => {
                if (value.isInt()) {
                    const int_val = std.math.cast(u8, value.asInt()) orelse {
                        return VM.getInstance().exceptions.valueError.runtimeError("Integer value out of range for character", .{});
                    };
                    datamap.getField(u8, ptr, offset).* = int_val;
                    return KrkValue.noneValue();
                }
                return VM.getInstance().exceptions.typeError.runtimeError("Expected int, got '%T'", .{value.value});
            },
            .vector, .position_vector => {
                if (value.isInstanceOf(vkrk_types.Vector.class)) {
                    const x = value.getAttribute("x");
                    const y = value.getAttribute("y");
                    const z = value.getAttribute("z");
                    if (x.isFloat() and y.isFloat() and z.isFloat()) {
                        const field = datamap.getField(sdk.Vector, ptr, offset);
                        field.x = @floatCast(x.asFloat());
                        field.y = @floatCast(y.asFloat());
                        field.z = @floatCast(z.asFloat());
                        return KrkValue.noneValue();
                    }
                }
                return VM.getInstance().exceptions.typeError.runtimeError("Expected Vector, got '%T'", .{value.value});
            },
            else => {
                return VM.getInstance().exceptions.typeError.runtimeError("Cannot write to field of this type", .{});
            },
        }
    }

    fn __init__(argc: c_int, argv: [*]const KrkValue, has_kw: c_int) callconv(.c) KrkValue {
        var index: c_int = undefined;
        var i_is_server: c_int = 1;

        if (!kuroko.parseArgs(
            "__init__",
            argc,
            argv,
            has_kw,
            ".i|p",
            &.{ "index", "is_server" },
            .{ &index, &i_is_server },
        )) {
            return KrkValue.noneValue();
        }

        if (!isEntity(argv[0])) {
            return VM.getInstance().exceptions.typeError.runtimeError("Expected Entity instance", .{});
        }

        const self = asEntity(argv[0]);
        self.index = std.math.cast(u32, index) orelse {
            return VM.getInstance().exceptions.valueError.runtimeError("Entity index out of range", .{});
        };
        self.is_server = (i_is_server != 0);

        return KrkValue.noneValue();
    }

    fn __repr__(argc: c_int, argv: [*]const KrkValue, has_kw: c_int) callconv(.c) KrkValue {
        _ = has_kw;
        if (argc < 1 or !isEntity(argv[0])) {
            return VM.getInstance().exceptions.typeError.runtimeError("Expected Entity instance", .{});
        }

        const self = asEntity(argv[0]);
        if (self.getClassName()) |name| {
            return KrkValue.stringFromFormat("Entity(index=%u, class='%s')", .{ self.index, name });
        }
        return KrkValue.stringFromFormat("Entity(index=%u)", .{self.index});
    }

    fn get_index(argc: c_int, argv: [*]const KrkValue, has_kw: c_int) callconv(.c) KrkValue {
        _ = has_kw;
        if (argc < 1 or !isEntity(argv[0])) {
            return VM.getInstance().exceptions.typeError.runtimeError("Expected Entity instance", .{});
        }
        return KrkValue.intValue(asEntity(argv[0]).index);
    }

    fn get_class_name(argc: c_int, argv: [*]const KrkValue, has_kw: c_int) callconv(.c) KrkValue {
        _ = has_kw;
        if (argc < 1 or !isEntity(argv[0])) {
            return VM.getInstance().exceptions.typeError.runtimeError("Expected Entity instance", .{});
        }
        const self = asEntity(argv[0]);
        if (self.getClassName()) |name| {
            return KrkString.copyString(name).asValue();
        }
        return KrkValue.noneValue();
    }

    fn is_valid(argc: c_int, argv: [*]const KrkValue, has_kw: c_int) callconv(.c) KrkValue {
        _ = has_kw;
        if (argc < 1 or !isEntity(argv[0])) {
            return VM.getInstance().exceptions.typeError.runtimeError("Expected Entity instance", .{});
        }
        return KrkValue.boolValue(asEntity(argv[0]).resolveEntity() != null);
    }

    fn get_field(argc: c_int, argv: [*]const KrkValue, has_kw: c_int) callconv(.c) KrkValue {
        var field_name: [*:0]const u8 = undefined;
        var class_name_val = KrkValue.noneValue();

        if (!kuroko.parseArgs(
            "get_field",
            argc,
            argv,
            has_kw,
            ".s|V",
            &.{ "field_name", "class_name" },
            .{ &field_name, &class_name_val },
        )) {
            return KrkValue.noneValue();
        }

        if (!isEntity(argv[0])) {
            return VM.getInstance().exceptions.typeError.runtimeError("Expected Entity instance", .{});
        }

        const self = asEntity(argv[0]);
        const ent_ptr = self.resolveEntity() orelse {
            return VM.getInstance().exceptions.valueError.runtimeError("Entity is no longer valid", .{});
        };

        const is_server = self.is_server;

        // Determine class name: from argument or from entity
        var resolved_class_name: [*:0]const u8 = undefined;
        if (!class_name_val.isNone()) {
            if (class_name_val.isString()) {
                resolved_class_name = class_name_val.asString().chars;
            } else {
                return VM.getInstance().exceptions.typeError.runtimeError("class_name must be a string", .{});
            }
        } else {
            resolved_class_name = self.getClassName() orelse {
                return VM.getInstance().exceptions.valueError.runtimeError("Cannot determine entity class name", .{});
            };
        }

        const info = datamap.getFieldInfo(
            std.mem.span(resolved_class_name),
            std.mem.span(field_name),
            is_server,
        ) orelse {
            return KrkValue.noneValue();
        };

        return readFieldValue(info.field_type, ent_ptr, info.offset);
    }

    fn set_field(argc: c_int, argv: [*]const KrkValue, has_kw: c_int) callconv(.c) KrkValue {
        var field_name: [*:0]const u8 = undefined;
        var value: KrkValue = undefined;
        var class_name_val = KrkValue.noneValue();

        if (!kuroko.parseArgs(
            "set_field",
            argc,
            argv,
            has_kw,
            ".sV|V",
            &.{ "field_name", "value", "class_name" },
            .{ &field_name, &value, &class_name_val },
        )) {
            return KrkValue.noneValue();
        }

        if (!isEntity(argv[0])) {
            return VM.getInstance().exceptions.typeError.runtimeError("Expected Entity instance", .{});
        }

        const self = asEntity(argv[0]);
        const ent_ptr = self.resolveEntity() orelse {
            return VM.getInstance().exceptions.valueError.runtimeError("Entity is no longer valid", .{});
        };

        const is_server = self.is_server;

        var resolved_class_name: [*:0]const u8 = undefined;
        if (!class_name_val.isNone()) {
            if (class_name_val.isString()) {
                resolved_class_name = class_name_val.asString().chars;
            } else {
                return VM.getInstance().exceptions.typeError.runtimeError("class_name must be a string", .{});
            }
        } else {
            resolved_class_name = self.getClassName() orelse {
                return VM.getInstance().exceptions.valueError.runtimeError("Cannot determine entity class name", .{});
            };
        }

        const info = datamap.getFieldInfo(
            std.mem.span(resolved_class_name),
            std.mem.span(field_name),
            is_server,
        ) orelse {
            return VM.getInstance().exceptions.valueError.runtimeError("Field '%s' not found in '%s'", .{ field_name, resolved_class_name });
        };

        return writeFieldValue(info.field_type, ent_ptr, info.offset, value);
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

    if (entlist.feature.loaded and datamap.feature.loaded) {
        Entity.class = KrkClass.makeClass(module, Entity, "Entity", null);
        Entity.class.setDoc(
            \\@brief Represents a game entity.
            \\
            \\Provides access to entity fields via the datamap system.
        );
        Entity.class.alloc_size = @sizeOf(Entity);
        Entity.class.bindMethod("__init__", Entity.__init__).setDoc(
            \\@brief Create an Entity wrapper.
            \\@arguments index, is_server=True
        );
        _ = Entity.class.bindMethod("__repr__", Entity.__repr__);
        Entity.class.bindMethod("get_index", Entity.get_index).setDoc(
            \\@brief Get the entity index.
        );
        Entity.class.bindMethod("get_class_name", Entity.get_class_name).setDoc(
            \\@brief Get the network class name of the entity.
        );
        Entity.class.bindMethod("is_valid", Entity.is_valid).setDoc(
            \\@brief Check if the entity is still valid.
        );
        Entity.class.bindMethod("get_field", Entity.get_field).setDoc(
            \\@brief Read a datamap field value.
            \\@arguments field_name, class_name=None
            \\@return The field value, or `None` if the field type is unsupported.
        );
        Entity.class.bindMethod("set_field", Entity.set_field).setDoc(
            \\@brief Write a datamap field value.
            \\@arguments field_name, value, class_name=None
        );
        Entity.class.finalizeClass();

        module.bindFunction("get_entity", get_entity).setDoc(
            \\@brief Get an entity by index.
            \\@arguments index, is_server=True
            \\@return `Entity` if found, `None` if invalid.
        );

        module.bindFunction("get_entities", get_entities).setDoc(
            \\@brief Get all valid entities.
            \\@arguments is_server=True
            \\@return List of `Entity` objects.
        );
    }
}

fn get_player(argc: c_int, argv: [*]const KrkValue, has_kw: c_int) callconv(.c) KrkValue {
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

fn get_portals(argc: c_int, argv: [*]const KrkValue, has_kw: c_int) callconv(.c) KrkValue {
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
        const value = PortalInfo.create(portal);
        VM.push(value);
        list.asList().append(value);
        _ = VM.pop();
    }
    _ = VM.pop();
    return list;
}

fn createEntityInstance(index: u32, is_server: bool) KrkValue {
    const inst = KrkInstance.create(Entity.class);
    VM.push(inst.asValue());
    const ent: *Entity = @ptrCast(inst);
    ent.index = index;
    ent.is_server = is_server;
    return VM.pop();
}

fn get_entity(argc: c_int, argv: [*]const KrkValue, has_kw: c_int) callconv(.c) KrkValue {
    var index: c_int = undefined;
    var i_is_server: c_int = 1;

    if (!kuroko.parseArgs(
        "get_entity",
        argc,
        argv,
        has_kw,
        "i|p",
        &.{ "index", "is_server" },
        .{ &index, &i_is_server },
    )) {
        return KrkValue.noneValue();
    }

    const u_index = std.math.cast(u32, index) orelse {
        return KrkValue.noneValue();
    };
    const is_server = (i_is_server != 0);

    // Check entity exists
    if (is_server) {
        if (entlist.server_list.getEntity(u_index) == null) {
            return KrkValue.noneValue();
        }
    } else {
        if (entlist.client_list.getEntity(u_index) == null) {
            return KrkValue.noneValue();
        }
    }

    return createEntityInstance(u_index, is_server);
}

fn get_entities(argc: c_int, argv: [*]const KrkValue, has_kw: c_int) callconv(.c) KrkValue {
    var i_is_server: c_int = 1;

    if (!kuroko.parseArgs(
        "get_entities",
        argc,
        argv,
        has_kw,
        "|p",
        &.{"is_server"},
        .{&i_is_server},
    )) {
        return KrkValue.noneValue();
    }

    const list = KrkList.listOf(0, null, false);
    VM.push(list);

    const is_server = (i_is_server != 0);

    if (is_server) {
        var i: u32 = 0;
        const max_ent: u32 = sdk.MAX_EDICTS;
        while (i < max_ent) : (i += 1) {
            if (entlist.server_list.getEntity(i) != null) {
                const ent_val = createEntityInstance(i, is_server);
                VM.push(ent_val);
                list.asList().append(ent_val);
                _ = VM.pop();
            }
        }
    } else {
        const max_ent = client.entlist.getHighestEntityIndex() orelse {
            _ = VM.pop();
            return list;
        };
        var i: u32 = 0;
        while (i < max_ent) : (i += 1) {
            if (entlist.client_list.getEntity(i) != null) {
                const ent_val = createEntityInstance(i, is_server);
                VM.push(ent_val);
                list.asList().append(ent_val);
                _ = VM.pop();
            }
        }
    }

    _ = VM.pop();
    return list;
}
