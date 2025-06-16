const std = @import("std");
const builtin = @import("builtin");

pub const VCallConv = switch (@import("builtin").os.tag) {
    .windows => std.builtin.CallingConventionVCallConv,
    else => std.builtin.CallingConvention.C,
};

pub fn CUtlMemory(T: anytype) type {
    return extern struct {
        memory: [*]T,
        allocation_count: c_int,
        grow_size: c_int,
    };
}

pub fn CUtlVector(T: anytype) type {
    return extern struct {
        memory: CUtlMemory(T),
        size: c_uint,
        element: [*]T,
    };
}

pub const IServerPluginCallbacks = extern struct {
    _vt: *align(@alignOf(*anyopaque)) const anyopaque,
};

pub const CPlugin = extern struct {
    name: [128]u8,
    disable: bool,
    plugin: *IServerPluginCallbacks,
    plugin_interface_version: c_int,
    plugin_module: *anyopaque,
};

pub const CServerPlugin = extern struct {
    _vt: [*]*const anyopaque,
    plugins: CUtlVector(*CPlugin),
    plugin_helper_check: *anyopaque,
};

pub const MAX_EDICT_BITS = 11;
pub const MAX_EDICTS = 1 << MAX_EDICT_BITS;

pub const NUM_ENT_ENTRY_BITS = MAX_EDICT_BITS + 1;
pub const NUM_ENT_ENTRIES = 1 << NUM_ENT_ENTRY_BITS;
pub const ENT_ENTRY_MASK = NUM_ENT_ENTRIES - 1;
pub const INVALID_EHANDLE_INDEX = 0xFFFFFFFF;
pub const NUM_SERIAL_NUM_BITS = 32 - NUM_ENT_ENTRY_BITS;

pub const CBaseHandle = extern struct {
    index: c_ulong = INVALID_EHANDLE_INDEX,

    pub fn isValid(self: *const CBaseHandle) bool {
        return self.index != INVALID_EHANDLE_INDEX;
    }

    pub fn getEntryIndex(self: *const CBaseHandle) c_int {
        return @intCast(self.index & ENT_ENTRY_MASK);
    }

    pub fn getSerialNumber(self: *const CBaseHandle) c_int {
        return self.index >> NUM_ENT_ENTRY_BITS;
    }
};

pub const ClientClass = extern struct {
    createFn: *anyopaque,
    createEventFn: *anyopaque,
    network_name: [*:0]const u8,
    recv_table: *anyopaque,
    next: *ClientClass,
    class_id: c_int,

    pub fn getName(self: *ClientClass) [*:0]const u8 {
        return self.network_name;
    }
};

pub const IClientEntity = extern struct {
    _vt_IClientUnknown: [*]*const anyopaque,
    _vt_IClientRenderable: [*]*const anyopaque,
    _vt_IClientNetworkable: [*]*const anyopaque,
    _vt_IClientThinkable: [*]*const anyopaque,

    const VTIndexIClientUnknown = struct {
        const getRefEHandle = 2;
    };

    const VTIndexIClientNetworkable = struct {
        const getClientClass = 2;
    };

    pub fn getRefEHandle(self: *const IClientEntity) *const CBaseHandle {
        const _getRefEHandle: *const fn (this: *const anyopaque) callconv(VCallConv) *const CBaseHandle = @ptrCast(self._vt_IClientUnknown[VTIndexIClientUnknown.getRefEHandle]);
        return _getRefEHandle(self);
    }

    pub fn getClientClass(self: *const IClientEntity) *ClientClass {
        const _getClientClass: *const fn (this: *const anyopaque) callconv(VCallConv) *ClientClass = @ptrCast(self._vt_IClientNetworkable[VTIndexIClientNetworkable.getClientClass]);
        return _getClientClass(self);
    }
};

pub const ServerClass = extern struct {
    network_name: [*:0]const u8,
    send_table: *anyopaque,
    next: *ServerClass,
    class_id: c_int,

    pub fn getName(self: *ServerClass) [*:0]const u8 {
        return self.network_name;
    }
};

pub const IServerEntity = extern struct {
    _vt: [*]*const anyopaque,

    const VTIndex = struct {
        const getRefEHandle = 2;
    };

    pub fn getRefEHandle(self: *const IServerEntity) *const CBaseHandle {
        const _getRefEHandle: *const fn (this: *const anyopaque) callconv(VCallConv) *const CBaseHandle = @ptrCast(self._vt[VTIndex.getRefEHandle]);
        return _getRefEHandle(self);
    }
};

pub const Edict = extern struct {
    const FEdict = packed struct(c_uint) {
        changed: bool = false,
        free: bool = false,
        full: bool = false,
        always: bool = false,
        dont_send: bool = false,
        pvs_check: bool = false,
        pending_dormant_check: bool = false,
        dirty_pvs_information: bool = false,
        full_edict_changed: bool = false,
        _pad_0: u23,
    };

    state_flags: FEdict,
    network_serial_number: c_int,
    networkable: *anyopaque,
    unknown: *IServerEntity,
    freetime: f32,

    pub fn getOffsetField(self: *Edict, comptime T: type, offset: usize) *T {
        const addr: [*]const u8 = @ptrCast(self.unknown);
        return @ptrCast(addr + offset);
    }

    pub fn getIServerEntity(self: *Edict) ?*IServerEntity {
        if (self.state_flags.full) {
            return self.unknown;
        }
        return null;
    }
};

pub const DataMap = extern struct {
    data_desc: [*]TypeDescription,
    data_num_fields: c_int,
    data_class_name: [*:0]const u8,
    base_map: ?*DataMap,
    chains_validated: bool,
    packed_offsets_computed: bool,
    packed_size: c_int,

    const FieldType = enum(c_int) {
        none = 0, // No type or value
        float, // Any floating point value
        string, // A string ID (return from ALLOC_STRING)
        vector, // Any vector, QAngle, or AngularImpulse
        quaternion, // A quaternion
        integer, // Any integer or enum
        boolean, // boolean, implemented as an int, I may use this as a hint for compression
        short, // 2 byte integer
        character, // a byte
        color32, // 8-bit per channel r,g,b,a (32bit color)
        embedded, // an embedded object with a datadesc, recursively traverse and embedded class/structure based on an additional typedescription
        custom, // special type that contains function pointers to it's read/write/parse functions

        classptr, // CBaseEntity *
        ehandle, // Entity handle
        edict, // edict_t *

        position_vector, // A world coordinate (these are fixed up across level transitions automagically)
        time, // a floating point time (these are fixed up automatically too!)
        tick, // an integer tick count( fixed up similarly to time)
        model_name, // Engine string that is a model name (needs precache)
        sound_name, // Engine string that is a sound name (needs precache)

        input, // a list of inputed data fields (all derived from CMultiInputVar)
        function, // A class function pointer (Think, Use, etc)

        vmatrix, // a vmatrix (output coords are NOT worldspace)

        // NOTE: Use float arrays for local transformations that don't need to be fixed up.
        vmatrix_worldspace, // A VMatrix that maps some local space to world space (translation is fixed up on level transitions)
        matrix3x4_worldspace, // matrix3x4_t that maps some local space to world space (translation is fixed up on level transitions)

        interval, // a start and range floating point interval ( e.g., 3.2->3.6 == 3.2 and 0.4 )
        model_index, // a model index
        material_index, // a material index (using the material precache string table)

        vector2d, // 2 floats
    };

    const TypeDescription = extern struct {
        field_type: FieldType,
        field_name: [*:0]const u8,
        field_offset: [2]c_int,
        field_size: c_ushort,
        flags: c_short,
        external_name: [*:0]const u8,
        save_restore_ops: *anyopaque,
        inputFunc: *anyopaque,
        td: *DataMap,
        field_size_in_bytes: c_int,
        override_field: *TypeDescription,
        override_count: c_int,
        field_tolerance: f32,
    };
};

pub const Color = packed struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8 = 255,
};

pub const Vector = extern struct {
    x: f32 = 0.0,
    y: f32 = 0.0,
    z: f32 = 0.0,

    pub fn add(a: Vector, b: Vector) Vector {
        return Vector{
            .x = a.x + b.x,
            .y = a.y + b.y,
            .z = a.z + b.z,
        };
    }

    pub fn subtract(a: Vector, b: Vector) Vector {
        return Vector{
            .x = a.x - b.x,
            .y = a.y - b.y,
            .z = a.z - b.z,
        };
    }

    pub fn scale(v: Vector, n: f32) Vector {
        return Vector{
            .x = v.x * n,
            .y = v.y * n,
            .z = v.z * n,
        };
    }

    pub fn eql(a: Vector, b: Vector) bool {
        return (a.x == b.x) and (a.y == b.y) and (a.z == b.z);
    }

    pub fn lerp(a: Vector, b: Vector, t: f32) Vector {
        var res: Vector = undefined;
        res.x = a.x + (b.x - a.x) * t;
        res.y = a.y + (b.y - a.y) * t;
        res.z = a.z + (b.z - a.z) * t;
        return res;
    }

    pub fn dotProduct(a: Vector, b: Vector) f32 {
        return a.x * b.x + a.y * b.y + a.z * b.z;
    }

    pub fn transform(v: Vector, m: Matrix3x4) Vector {
        var res: Vector = undefined;
        res.x = dotProduct(v, Vector{ .x = m.mat_val[0][0], .y = m.mat_val[0][1], .z = m.mat_val[0][2] }) + m.mat_val[0][3];
        res.y = dotProduct(v, Vector{ .x = m.mat_val[1][0], .y = m.mat_val[1][1], .z = m.mat_val[1][2] }) + m.mat_val[1][3];
        res.z = dotProduct(v, Vector{ .x = m.mat_val[2][0], .y = m.mat_val[2][1], .z = m.mat_val[2][2] }) + m.mat_val[2][3];
        return res;
    }

    pub fn clear(self: *Vector) void {
        self.x = 0.0;
        self.y = 0.0;
        self.z = 0.0;
    }

    pub fn getlengthSqr(self: *const Vector) f32 {
        return self.x * self.x + self.y * self.y + self.z * self.z;
    }

    pub fn getlength(self: *const Vector) f32 {
        return @sqrt(self.x * self.x + self.y * self.y + self.z * self.z);
    }

    pub fn getlength2D(self: *const Vector) f32 {
        return @sqrt(self.x * self.x + self.y * self.y);
    }

    pub fn normalize(self: *const Vector) Vector {
        const length = self.getlength();
        if (length == 0) return self.*;
        return self.scale(1 / length);
    }
};

const VectorAligned = extern struct {
    base: Vector,
    w: f32 = 0.0,
};

pub const QAngle = Vector;

pub const Matrix3x4 = extern struct {
    mat_val: [3][4]f32,
};

pub const VMatrix = extern struct {
    m: [4][4]f32,
};

pub const Ray = extern struct {
    start: VectorAligned,
    delta: VectorAligned,
    start_offset: VectorAligned,
    extents: VectorAligned,
    is_ray: bool,
    is_swept: bool,

    pub fn init(self: *Ray, start: Vector, end: Vector) void {
        self.delta.base = Vector.subtract(end, start);

        self.is_swept = (self.delta.base.getlengthSqr() != 0);

        self.extents.base.clear();
        self.is_ray = true;

        self.start_offset.base.clear();
        self.start.base = start;
    }
};

const Surface = extern struct {
    name: [*:0]u8,
    surface_props: c_short,
    flags: c_ushort,
};

const Plane = extern struct {
    normal: Vector,
    dist: f32,
    plane_type: u8,
    sign_bits: u8,
    pad: u16,
};

pub const Trace = extern struct {
    startpos: Vector,
    endpos: Vector,
    plane: Plane,
    fraction: f32,
    content: c_int,
    disp_flags: c_ushort,
    all_solid: bool,
    start_solid: bool,

    fraction_left_solid: f32,
    surface: Surface,
    hit_group: c_int,
    physics_bone: c_short,
    ent: ?*anyopaque,
    hitbox: c_int,
};

pub const ITraceFilter = extern struct {
    _vt: *align(@alignOf(*anyopaque)) const anyopaque = undefined,

    pub const VTable = extern struct {
        shouldHitEntity: *const fn (_: *anyopaque, server_entity: *anyopaque, contents_mask: c_int) callconv(VCallConv) bool,
        getTraceType: *const fn (_: *anyopaque) callconv(VCallConv) c_int,
    };
};

pub const CCollisionPropertyV1 = extern struct {
    _vt: [*]*const anyopaque,

    outer: *anyopaque,

    mins: Vector,
    maxs: Vector,
    radius: f32,

    solid_flags: c_ushort,

    partition: c_ushort,
    surround_type: u8,

    solid_type: u8,
    trigger_bloat: u8,

    specified_surrounding_mins: Vector,
    specified_surrounding_maxs: Vector,

    surrounding_mins: Vector,
    surrounding_maxs: Vector,

    const VTIndex = struct {
        const getCollisionOrigin = 8;
        const getCollisionAngles = 9;
        const collisionToWorldTransform = 10;
    };

    fn getCollisionOrigin(self: *CCollisionPropertyV1) Vector {
        const _getCollisionOrigin: *const fn (this: *anyopaque) callconv(VCallConv) *Vector = @ptrCast(self._vt[VTIndex.getCollisionOrigin]);
        return _getCollisionOrigin(self).*;
    }

    fn getCollisionAngles(self: *CCollisionPropertyV1) QAngle {
        const _getCollisionAngles: *const fn (this: *anyopaque) callconv(VCallConv) *QAngle = @ptrCast(self._vt[VTIndex.getCollisionAngles]);
        return _getCollisionAngles(self).*;
    }

    fn collisionToWorldTransform(self: *CCollisionPropertyV1) Matrix3x4 {
        const _collisionToWorldTransform: *const fn (this: *anyopaque) callconv(VCallConv) *const Matrix3x4 = @ptrCast(self._vt[VTIndex.collisionToWorldTransform]);
        return _collisionToWorldTransform(self).*;
    }

    pub fn isSolid(self: *CCollisionPropertyV1) bool {
        const solid_none = 0;
        const not_solid = 4;
        return (self.solid_type != solid_none) and ((self.solid_flags & not_solid) == 0);
    }

    fn isBoundsDefinedInEntitySpace(self: *CCollisionPropertyV1) bool {
        const force_world_aliged = 64;
        const solid_bbox = 2;
        const solid_none = 0;
        return ((self.solid_flags & force_world_aliged) == 0) and
            (self.solid_type != solid_bbox) and (self.solid_type != solid_none);
    }

    pub fn worldSpaceCenter(self: *CCollisionPropertyV1) Vector {
        const obb_center = Vector.lerp(self.mins, self.maxs, 0.5);
        if (!self.isBoundsDefinedInEntitySpace() or self.getCollisionAngles().eql(QAngle{ .x = 0, .y = 0, .z = 0 })) {
            return Vector.add(obb_center, self.getCollisionOrigin());
        }
        return Vector.transform(obb_center, self.collisionToWorldTransform());
    }
};

pub const CCollisionPropertyV2 = extern struct {
    _vt: [*]*const anyopaque,

    outer: *anyopaque,

    mins_pre_scaled: Vector,
    maxs_pre_scaled: Vector,
    mins: Vector,
    maxs: Vector,
    radius: f32,

    solid_flags: c_ushort,

    partition: c_ushort,
    surround_type: u8,

    solid_type: u8,
    trigger_bloat: u8,

    specified_surrounding_mins_pre_scaled: Vector,
    specified_surrounding_maxs_pre_scaled: Vector,
    specified_surrounding_mins: Vector,
    specified_surrounding_maxs: Vector,

    surrounding_mins: Vector,
    surrounding_maxs: Vector,

    const VTIndex = struct {
        const getCollisionOrigin = 10;
        const getCollisionAngles = 11;
        const collisionToWorldTransform = 12;
    };

    fn getCollisionOrigin(self: *CCollisionPropertyV2) Vector {
        const _getCollisionOrigin: *const fn (this: *anyopaque) callconv(VCallConv) *Vector = @ptrCast(self._vt[VTIndex.getCollisionOrigin]);
        return _getCollisionOrigin(self).*;
    }

    fn getCollisionAngles(self: *CCollisionPropertyV2) QAngle {
        const _getCollisionAngles: *const fn (this: *anyopaque) callconv(VCallConv) *QAngle = @ptrCast(self._vt[VTIndex.getCollisionAngles]);
        return _getCollisionAngles(self).*;
    }

    fn collisionToWorldTransform(self: *CCollisionPropertyV2) Matrix3x4 {
        const _collisionToWorldTransform: *const fn (this: *anyopaque) callconv(VCallConv) *const Matrix3x4 = @ptrCast(self._vt[VTIndex.collisionToWorldTransform]);
        return _collisionToWorldTransform(self).*;
    }

    pub fn isSolid(self: *CCollisionPropertyV2) bool {
        const solid_none = 0;
        const not_solid = 4;
        return (self.solid_type != solid_none) and ((self.solid_flags & not_solid) == 0);
    }

    fn isBoundsDefinedInEntitySpace(self: *CCollisionPropertyV2) bool {
        const force_world_aliged = 64;
        const solid_bbox = 2;
        const solid_none = 0;
        return ((self.solid_flags & force_world_aliged) == 0) and
            (self.solid_type != solid_bbox) and (self.solid_type != solid_none);
    }

    pub fn worldSpaceCenter(self: *CCollisionPropertyV2) Vector {
        const obb_center = Vector.lerp(self.mins, self.maxs, 0.5);
        if (!self.isBoundsDefinedInEntitySpace() or self.getCollisionAngles().eql(QAngle{ .x = 0, .y = 0, .z = 0 })) {
            return Vector.add(obb_center, self.getCollisionOrigin());
        }
        return Vector.transform(obb_center, self.collisionToWorldTransform());
    }
};

pub const CUserCmd = extern struct {
    vt: *anyopaque,
    command_number: c_int,
    tick_count: c_int,
    view_angles: QAngle,
    forward_move: f32,
    side_move: f32,
    up_move: f32,
    buttons: c_int,
    impluse: u8,
    weapon_select: c_int,
    weapon_subtype: c_int,
    random_seed: c_int,
    mouse_dx: c_short,
    mouse_dy: c_short,
    has_been_predicted: bool,
};

pub const CMoveData = extern struct {
    flages: u8,

    player_handle: CBaseHandle,

    impluse_command: c_int,
    view_angles: QAngle,
    abs_view_angles: QAngle,
    buttons: c_int,
    old_buttons: c_int,
    forward_move: f32,
    side_move: f32,
    up_move: f32,

    max_speed: f32,
    client_max_speed: f32,

    velocity: Vector,
    angles: QAngle,
    old_angles: QAngle,

    out_step_height: f32,
    out_wish_vel: Vector,
    out_jump_vel: Vector,

    constraint_center: Vector,
    constraint_radius: f32,
    constraint_width: f32,
    constraint_speed_factor: f32,

    abs_origin: Vector,
};
