const std = @import("std");

/// Stack reference or primative value.
///
/// This type stores a stack reference to an object, or the contents of
/// a primitive type. Each VM thread's stack consists of an array of
/// these values, and they are generally passed around in the VM through
/// direct copying rather than as pointers, avoiding the need to track
/// memory used by them.
/// Implemented through basic NaN-boxing where the top sixteen bits are
/// used as a tag (`KrkValueType`) and the lower 32 or 48 bits contain
/// the various primitive types.
pub const KrkValue = packed struct(u64) {
    value: u64,

    pub const Type = enum(c_int) {
        boolean = 0xFFFC,
        integer = 0xFFFD,
        handler = 0xFFFE,
        none = 0xFFFF,
        kwargs = 0x7FFC,
        object = 0x7FFD,
        notimpl = 0x7FFE,
        float = 0x0,
    };

    extern "c" fn krk_valuesEqual(a: KrkValue, b: KrkValue) c_int;
    extern "c" fn krk_valuesSameOrEqual(a: KrkValue, b: KrkValue) c_int;
    extern "c" fn krk_parse_int(start: [*]const u8, width: usize, base: c_uint) KrkValue;
    extern "c" fn krk_parse_float(start: [*]const u8, width: usize) KrkValue;
    extern "c" fn krk_hashValue(value: KrkValue, hash_out: *u32) c_int;
    extern "c" fn krk_typeName(value: KrkValue) [*:0]const u8;
    extern "c" fn krk_operator_lt(a: KrkValue, b: KrkValue) KrkValue;
    extern "c" fn krk_operator_gt(a: KrkValue, b: KrkValue) KrkValue;
    extern "c" fn krk_operator_le(a: KrkValue, b: KrkValue) KrkValue;
    extern "c" fn krk_operator_ge(a: KrkValue, b: KrkValue) KrkValue;
    extern "c" fn krk_instanceSetAttribute_wrapper(owner: KrkValue, name: *KrkString, to: KrkValue) KrkValue;
    extern "c" fn krk_getType(value: KrkValue) *KrkClass;
    extern "c" fn krk_isInstanceOf(obj: KrkValue, class_type: *const KrkClass) c_int;
    extern "c" fn krk_callValue(callee: KrkValue, arg_count: c_int, callable_on_stack: c_int) c_int;
    extern "c" fn krk_isFalsey(value: KrkValue) c_int;
    extern "c" fn krk_valueGetAttribute(value: KrkValue, name: [*:0]const u8) KrkValue;
    extern "c" fn krk_valueGetAttribute_default(value: KrkValue, name: [*:0]const u8, default_val: KrkValue) KrkValue;
    extern "c" fn krk_valueSetAttribute(owner: KrkValue, name: [*:0]const u8, to: KrkValue) KrkValue;
    extern "c" fn krk_valueDelAttribute(owner: KrkValue, name: [*:0]const u8) KrkValue;
    extern "c" fn krk_valueAsNumber(value: KrkValue, out: *f64) c_int;
    extern "c" fn krk_unpackIterable(
        iterable: KrkValue,
        context: *anyopaque,
        callback: *const fn (
            context: *anyopaque,
            values: [*]const KrkValue,
            count: usize,
        ) callconv(.C) c_int,
    ) c_int;
    extern "c" fn krk_stringFromFormat(fmt: [*:0]const u8, ...) KrkValue;

    const mask_boolean: u64 = 0xFFFC000000000000;
    const mask_integer: u64 = 0xFFFD000000000000;
    const mask_handler: u64 = 0xFFFE000000000000;
    const mask_none: u64 = 0xFFFF000000000000;
    const mask_kwargs: u64 = 0x7FFC000000000000;
    const mask_object: u64 = 0x7FFD000000000000;
    const mask_notimpl: u64 = 0x7FFE000000000000;
    const mask_nan: u64 = 0x7FFC000000000000;
    const mask_low: u64 = 0x0000FFFFFFFFFFFF;

    /// Compare two values for equality.
    ///
    /// Performs a relaxed equality comparison between two values,
    /// check for equivalence by contents. This may call managed
    /// code to run `__eq__` methods.
    pub inline fn equal(a: KrkValue, b: KrkValue) bool {
        return krk_valuesEqual(a, b) == 1;
    }

    /// Compare two values by identity.
    ///
    /// Performs a strict comparison between two values, comparing
    /// their identities. For primitive values, this is generally
    /// the same as comparing by equality. For objects, this compares
    /// pointer values directly.
    pub inline fn same(a: KrkValue, b: KrkValue) bool {
        return a.value == b.value;
    }

    /// Compare two values by identity, then by equality.
    ///
    /// More efficient than just `KrkValue.same` followed by `KrkValue.equal`.
    pub inline fn sameOrEqual(a: KrkValue, b: KrkValue) bool {
        return krk_valuesSameOrEqual(a, b) == 1;
    }

    /// Parse a string into an integer.
    ///
    /// - `string` String to parse.
    ///
    /// return: A Kuroko integer value, or None if parsing fails.
    pub inline fn parseInt(string: []const u8, base: u32) KrkValue {
        return krk_parse_int(string, string.len, base);
    }

    /// Parse a string into a float.
    ///
    /// The approach we take here is to collect all of the digits left of the exponent
    /// (if present), convert them to a big int disregarding the radix point, then
    /// multiply or divide that by an appropriate power of ten based on the exponent
    /// and location of the radix point. The division step uses are `long.__truediv__`
    /// to get accurate conversions of fractions to floats.
    ///
    /// May raise exceptions if parsing fails, either here or in integer parsing.
    ///
    /// - `string` String to parse.
    ///
    /// return: A Kuroko float value, or None on exception.
    pub inline fn parseFloat(string: []const u8) KrkValue {
        return krk_parse_float(string, string.len);
    }

    pub fn stringFromFormat(fmt: [*:0]const u8, args: anytype) KrkValue {
        return @call(.auto, krk_stringFromFormat, .{fmt} ++ args);
    }

    /// Calculate the hash for a value.
    pub inline fn hashValue(v: KrkValue) ?u32 {
        var hash: u32 = undefined;
        if (krk_hashValue(v, KrkValue, &hash) == 0) {
            return hash;
        }
        return null;
    }

    /// Get the name of the type of a value.
    ///
    /// Obtains the C string representing the name of the class
    /// associated with the given value. Useful for crafting
    /// exception messages, such as those describing TypeErrors.
    ///
    /// return: Nul-terminated C string of the type.
    pub inline fn typeName(v: KrkValue) [*:0]const u8 {
        return krk_typeName(v);
    }

    pub inline fn operatorLT(a: KrkValue, b: KrkValue) KrkValue {
        return krk_operator_lt(a, b);
    }

    pub inline fn operatorGT(a: KrkValue, b: KrkValue) KrkValue {
        return krk_operator_gt(a, b);
    }

    pub inline fn operatorLE(a: KrkValue, b: KrkValue) KrkValue {
        return krk_operator_le(a, b);
    }

    pub inline fn operatorGE(a: KrkValue, b: KrkValue) KrkValue {
        return krk_operator_ge(a, b);
    }

    pub inline fn getType(value: KrkValue) *KrkClass {
        return krk_getType(value);
    }

    pub inline fn isInstanceOf(obj: KrkValue, class_type: *const KrkClass) bool {
        return krk_isInstanceOf(obj, class_type) != 0;
    }

    pub inline fn callValue(callee: KrkValue, arg_count: c_int, callable_on_stack: c_int) c_int {
        return krk_callValue(callee, arg_count, callable_on_stack);
    }

    /// Determine the truth of a value.
    ///
    /// Determines if a value represents a "falsey" value.
    /// Empty collections, 0-length strings, False, numeric 0,
    /// None, etc. are "falsey". Other values are generally "truthy".
    pub inline fn isFalsey(value: KrkValue) bool {
        return krk_isFalsey(value) == 1;
    }

    /// Obtain a property of an object by name.
    ///
    /// This is a convenience function that works in essentially the
    /// same way as the `OP_GET_PROPERTY` instruction.
    ///
    /// warning: As this function takes a C string, it will not work with
    /// attribute names that have nil bytes.
    ///
    /// `name` C-string of the property name to query.
    ///
    /// return: The requested property, or None with an `AttributeError`
    /// exception set in the current thread if the attribute was
    /// not found.
    pub inline fn getAttribute(value: KrkValue, name: [*:0]const u8) KrkValue {
        return krk_valueGetAttribute(value, name);
    }

    /// See `KrkValue.getAttribute`
    pub inline fn getAttributeDefault(value: KrkValue, name: [*:0]const u8, default_val: KrkValue) KrkValue {
        return krk_valueGetAttribute_default(value, name, default_val);
    }

    /// Set a property of an object by name.
    ///
    /// This is a convenience function that works in essentially the
    /// same way as the `OP_SET_PROPERTY` instruction.
    ///
    /// warning: As this function takes a C string, it will not work with
    /// attribute names that have nil bytes.
    ///
    /// - `owner` The owner of the property to modify.
    /// - `name` C-string of the property name to modify.
    /// - `to` The value to assign.
    ///
    /// return: The set value, or None with an `AttributeError`
    /// exception set in the current thread if the object can
    /// not have a property set.
    pub inline fn setAttribute(owner: KrkValue, name: [*:0]const u8, to: KrkValue) KrkValue {
        return krk_valueSetAttribute(owner, name, to);
    }

    /// Delete a property of an object by name.
    ///
    /// This is a convenience function that works in essentially the
    /// same way as the `OP_DEL_PROPERTY` instruction.
    ///
    /// warning: As this function takes a C string, it will not work with
    /// attribute names that have nil bytes.
    ///
    /// - `owner` The owner of the property to delete.
    /// - `name` C-string of the property name to delete.
    pub inline fn delAttribute(owner: KrkValue, name: [*:0]const u8) KrkValue {
        return krk_valueDelAttribute(owner, name);
    }

    /// Set an attribute of an instance object, bypassing `__setattr__`.
    ///
    /// This can be used to emulate the behavior of `super(object).__setattr__` for
    /// types that derive from KrkInstance and have a fields table, and is the internal
    /// mechanism by which `object.__setattr__()` performs this task.
    ///
    /// Does not bypass descriptors.
    ///
    /// - `owner` Instance object to set an attribute on.
    /// - `name` Name of the attribute.
    /// - `to` New value for the attribute.
    ///
    /// return: The value set, which is likely `to` but may be the returned value of a descriptor `__set__` method.
    pub inline fn setAttributeWrapper(owner: KrkValue, name: *KrkString, to: KrkValue) KrkValue {
        return krk_instanceSetAttribute_wrapper(owner, name, to);
    }

    pub inline fn unpackIterable(
        iterable: KrkValue,
        context: *anyopaque,
        callback: *const fn (
            context: *anyopaque,
            values: [*]const KrkValue,
            count: usize,
        ) callconv(.C) c_int,
    ) bool {
        return krk_unpackIterable(iterable, context, callback) == 1;
    }

    pub inline fn noneValue() KrkValue {
        return .{
            .value = mask_low | mask_none,
        };
    }

    pub inline fn notimplValue() KrkValue {
        return .{
            .value = mask_low | mask_notimpl,
        };
    }

    pub inline fn boolValue(v: bool) KrkValue {
        return .{
            .value = (@intFromBool(v) & mask_low) | mask_boolean,
        };
    }

    pub inline fn intValue(v: anytype) KrkValue {
        const _v: u64 = @intCast(v);
        return .{
            .value = (_v & mask_low) | mask_integer,
        };
    }

    pub inline fn kwargsValue(v: anytype) KrkValue {
        const _v: u64 = @intCast(v);
        return .{
            .value = _v | mask_kwargs,
        };
    }

    pub inline fn objectValue(v: *KrkObj) KrkValue {
        return .{
            .value = (@intFromPtr(v) & mask_low) | mask_object,
        };
    }

    pub inline fn floatValue(v: anytype) KrkValue {
        const _v: f64 = @floatCast(v);
        const krk_v: KrkValue = @bitCast(_v);
        return krk_v;
    }

    inline fn krk_ix(v: KrkValue) u64 {
        return v.value & mask_low;
    }

    inline fn krk_sx(v: KrkValue) u64 {
        return v.value & 0x800000000000;
    }

    pub inline fn asInt(v: KrkValue) i64 {
        if (krk_sx(v) != 0) {
            return @intCast(krk_ix(v) | mask_none);
        }
        return @intCast(krk_ix(v));
    }

    pub inline fn asBool(v: KrkValue) bool {
        return v.asInt() != 0;
    }

    pub inline fn asObject(v: KrkValue) *KrkObj {
        return @ptrFromInt(@as(usize, @intCast(v.value & mask_low)));
    }

    pub inline fn asFloat(v: KrkValue) f64 {
        return @bitCast(v);
    }

    pub inline fn asNumber(v: KrkValue) ?f64 {
        var result: f64 = undefined;
        if (krk_valueAsNumber(v, &result) == 0) {
            return null;
        }
        return result;
    }

    pub inline fn asString(v: KrkValue) *KrkString {
        return @ptrCast(v.asObject());
    }

    pub inline fn asStr(v: KrkValue) *KrkString {
        return @ptrCast(v.asObject());
    }

    pub inline fn asCString(v: KrkValue) [*:0]u8 {
        const string: *KrkString = @ptrCast(v.asObject());
        return string.chars;
    }

    pub inline fn asStriterator(v: KrkValue) *KrkInstance {
        return @ptrCast(v.asObject());
    }

    pub inline fn asBytes(v: KrkValue) *KrkBytes {
        return @ptrCast(v.asObject());
    }

    pub inline fn asNative(v: KrkValue) *KrkNative {
        return @ptrCast(v.asObject());
    }

    pub inline fn asClosure(v: KrkValue) *KrkClosure {
        return @ptrCast(v.asObject());
    }

    pub inline fn asClass(v: KrkValue) *KrkClass {
        return @ptrCast(v.asObject());
    }

    pub inline fn asInstance(v: KrkValue) *KrkInstance {
        return @ptrCast(v.asObject());
    }

    pub inline fn asBoundMethod(v: KrkValue) *KrkBoundMethod {
        return @ptrCast(v.asObject());
    }

    pub inline fn asTuple(v: KrkValue) *KrkTuple {
        return @ptrCast(v.asObject());
    }

    pub inline fn asList(v: KrkValue) *KrkValueArray {
        const list: *KrkList = @ptrCast(v.asObject());
        return &list.values;
    }

    pub inline fn asDict(v: KrkValue) *KrkTable {
        const dict: *KrkDict = @ptrCast(v.asObject());
        return &dict.entries;
    }

    pub inline fn asDictitems(v: KrkValue) *DictItems {
        return @ptrCast(v.asObject());
    }

    pub inline fn asDictkeys(v: KrkValue) *DictKeys {
        return @ptrCast(v.asObject());
    }

    pub inline fn asDictvalues(v: KrkValue) *DictValues {
        return @ptrCast(v.asObject());
    }

    pub inline fn asBytearray(v: KrkValue) *anyopaque {
        return @ptrCast(v.asObject());
    }

    pub inline fn asSlice(v: KrkValue) *KrkSlice {
        return @ptrCast(v.asObject());
    }

    pub inline fn asSet(v: KrkValue) *Set {
        return @ptrCast(v.asObject());
    }

    inline fn _getType(v: KrkValue) !Type {
        return switch (v.value >> 48) {
            @intFromEnum(Type.integer) => .integer,
            @intFromEnum(Type.boolean) => .boolean,
            @intFromEnum(Type.none) => .none,
            @intFromEnum(Type.handler) => .handler,
            @intFromEnum(Type.object) => .object,
            @intFromEnum(Type.kwargs) => .kwargs,
            @intFromEnum(Type.notimpl) => .notimpl,
            else => {
                if ((v.value & mask_nan) != mask_nan) {
                    return .float;
                }
                return error.UnknownType;
            },
        };
    }

    pub inline fn isInt(v: KrkValue) bool {
        const t = _getType(v) catch return false;
        return t == .integer;
    }

    pub inline fn isBool(v: KrkValue) bool {
        const t = _getType(v) catch return false;
        return t == .boolean;
    }

    pub inline fn isNone(v: KrkValue) bool {
        const t = _getType(v) catch return false;
        return t == .none;
    }

    pub inline fn isObject(v: KrkValue) bool {
        const t = _getType(v) catch return false;
        return t == .object;
    }

    pub inline fn isKwargs(v: KrkValue) bool {
        const t = _getType(v) catch return false;
        return t == .kwargs;
    }

    pub inline fn isNotimpl(v: KrkValue) bool {
        const t = _getType(v) catch return false;
        return t == .notimpl;
    }

    pub inline fn isFloat(v: KrkValue) bool {
        const t = _getType(v) catch return false;
        return t == .float;
    }

    pub inline fn isObjType(v: KrkValue, obj_type: KrkObj.Type) bool {
        return v.isObject() and v.asObject().obj_type == obj_type;
    }

    pub inline fn isString(v: KrkValue) bool {
        return isObjType(v, .string);
    }

    /// `isString` or isInstanceOf `strClass`
    pub inline fn isStr(v: KrkValue) bool {
        return isObjType(v, .string) or v.isInstanceOf(KrkVM.getInstance().base_classes.strClass);
    }

    pub inline fn isStriterator(v: KrkValue) bool {
        return v.isInstanceOf(KrkVM.getInstance().base_classes.striteratorClass);
    }

    pub inline fn isBytes(v: KrkValue) bool {
        return isObjType(v, .bytes);
    }

    pub inline fn isNative(v: KrkValue) bool {
        return isObjType(v, .native);
    }

    pub inline fn isClosure(v: KrkValue) bool {
        return isObjType(v, .closure);
    }

    pub inline fn isClass(v: KrkValue) bool {
        return isObjType(v, .class);
    }

    pub inline fn isInstance(v: KrkValue) bool {
        return isObjType(v, .instance);
    }

    pub inline fn isBoundMethod(v: KrkValue) bool {
        return isObjType(v, .bound_method);
    }

    pub inline fn isTuple(v: KrkValue) bool {
        return isObjType(v, .tuple);
    }

    pub inline fn isList(v: KrkValue) bool {
        const class = KrkVM.getInstance().base_classes.listClass;
        return v.isInstance() and
            (@intFromPtr(v.asInstance()._class) == @intFromPtr(class) or
                v.isInstanceOf(class));
    }

    pub inline fn isDict(v: KrkValue) bool {
        const class = KrkVM.getInstance().base_classes.dictClass;
        return v.isInstance() and
            (@intFromPtr(v.asInstance()._class) == @intFromPtr(class) or
                v.isInstanceOf(class));
    }

    pub inline fn isDictitems(v: KrkValue) bool {
        return v.isInstanceOf(KrkVM.getInstance().base_classes.dictitemsClass);
    }

    pub inline fn isDictkeys(v: KrkValue) bool {
        return v.isInstanceOf(KrkVM.getInstance().base_classes.dictkeysClass);
    }

    pub inline fn isDictvalues(v: KrkValue) bool {
        return v.isInstanceOf(KrkVM.getInstance().base_classes.dictvaluesClass);
    }

    pub inline fn isBytearray(v: KrkValue) bool {
        return v.isInstanceOf(KrkVM.getInstance().base_classes.bytearrayClass);
    }

    pub inline fn isSlice(v: KrkValue) bool {
        return v.isInstanceOf(KrkVM.getInstance().base_classes.sliceClass);
    }

    pub inline fn isSet(v: KrkValue) bool {
        return v.isInstanceOf(KrkVM.getInstance().base_classes.setClass);
    }
};

/// Flexible vector of stack references.
///
/// Value Arrays provide a resizable collection of values and are the
/// backbone of lists and tuples.
pub const KrkValueArray = extern struct {
    capacity: usize,
    count: usize,
    values: [*]KrkValue,

    extern "c" fn krk_initValueArray(array: *KrkValueArray) void;
    extern "c" fn krk_writeValueArray(array: *KrkValueArray, value: KrkValue) void;
    extern "c" fn krk_freeValueArray(array: *KrkValueArray) void;

    /// Initialize a value array.
    ///
    /// This should be called for any new value array, especially ones
    /// initialized in heap or stack space, to set up the capacity, count
    /// and initial value pointer.
    ///
    /// - `array` Value array to initialize.
    pub inline fn init(array: *KrkValueArray) void {
        krk_initValueArray(&array);
    }

    /// Add a value to a value array.
    ///
    /// Appends `value` to the end of the given array, adjusting count values
    /// and resizing as necessary.
    ///
    /// - `array` Array to append to.
    /// - `value` Value to append to array.
    pub inline fn append(array: *KrkValueArray, value: KrkValue) void {
        krk_writeValueArray(array, value);
    }

    /// Release relesources used by a value array.
    ///
    /// Frees the storage associated with a given value array and resets
    /// its capacity and count. Does not directly free resources associated
    /// with heap objects referenced by the values in this array: The GC
    /// is responsible for taking care of that.
    ///
    /// - `array` Array to release.
    pub inline fn deinit(array: *KrkValueArray) void {
        krk_freeValueArray(array);
    }
};

/// Map entry of instruction offsets to line numbers.
///
/// Each code object contains an array of line mappings, indicating
/// the start offset of each line. Since a line typically maps to
/// multiple opcodes, and spans of many lines may map to no opcodes
/// in the case of blank lines or docstrings, this array is stored
/// as a sequence of `<star_offset, line>` pairs rather than a simple
/// array of one or the other.
pub const KrkLineMap = extern struct {
    start_offset: usize,
    line: usize,
};

/// Opcode chunk of a code object.
///
/// Opcode chunks are internal to code objects and I'm not really
/// sure why we're still separating them from the `KrkCodeObjects`.
/// Stores four flexible arrays using three different formats:
/// - Code, representing opcodes and operands.
/// - Lines, representing offset-to-line mappings.
/// - Filename, the string name of the source file.
/// - Constants, an array of values referenced by the code object.
pub const KrkChunk = extern struct {
    count: usize,
    capacity: usize,
    code: [*]u8,
    lines_count: usize,
    lines_capacity: usize,
    lines: [*]KrkLineMap,
    filename: *KrkString,
    constants: KrkValueArray,

    extern "c" fn krk_initChunk(chunk: *KrkChunk) void;
    extern "c" fn krk_writeChunk(chunk: *KrkChunk, byte: u8, line: usize) void;
    extern "c" fn krk_freeChunk(chunk: *KrkChunk) void;
    extern "c" fn krk_addConstant(chunk: *KrkChunk, value: KrkValue) usize;
    extern "c" fn krk_emitConstant(chunk: *KrkChunk, ind: usize, line: usize) void;
    extern "c" fn krk_writeConstant(chunk: *KrkChunk, value: KrkValue, line: usize) usize;
    extern "c" fn krk_lineNumber(chunk: *KrkChunk, offset: usize) usize;

    /// Initialize an opcode chunk.
    pub inline fn init(chunk: *KrkChunk) void {
        krk_initChunk(&chunk);
    }

    /// Append a byte to an opcode chunk.
    pub inline fn write(chunk: *KrkChunk, byte: u8, line: usize) void {
        krk_writeChunk(chunk, byte, line);
    }

    /// Release the resources allocated to an opcode chunk.
    pub inline fn deinit(chunk: *KrkChunk) void {
        krk_freeChunk(chunk);
    }

    /// Add a new constant value to an opcode chunk.
    pub inline fn addConstant(chunk: *KrkChunk, value: KrkValue) usize {
        return krk_addConstant(chunk, value);
    }

    /// Write an `OP_CONSTANT(_LONG)` instruction.
    pub inline fn emitConstant(chunk: *KrkChunk, ind: usize, line: usize) void {
        krk_emitConstant(chunk, ind, line);
    }

    /// Add a new constant and write an instruction for it.
    pub inline fn writeConstant(chunk: *KrkChunk, value: KrkValue, line: usize) usize {
        return krk_writeConstant(chunk, value, line);
    }

    /// Obtain the line number for a byte offset into a bytecode chunk.
    ///
    /// Scans the line mapping table for the given chunk to find the
    /// correct line number from the original source file for the instruction
    /// at byte index 'offset'.
    ///
    /// - `chunk` Bytecode chunk containing the instruction.
    /// - `offset` Byte offset of the instruction to locate.
    ///
    /// return: Line number, 1-indexed.
    pub inline fn lineNumber(chunk: *KrkChunk, offset: usize) usize {
        return krk_lineNumber(chunk, offset);
    }
};

/// The most basic object type.
///
/// This is the base of all object types and contains
/// the core structures for garbage collection.
pub const KrkObj = extern struct {
    obj_type: Type,
    flags: u16,
    hash: u32,
    next: ?*KrkObj,

    /// Union tag for heap objects.
    ///
    /// Allows for quick identification of special types.
    pub const Type = enum(u16) {
        codeobject,
        native,
        closure,
        string,
        upvalue,
        class,
        instance,
        bound_method,
        tuple,
        bytes,
    };

    pub const flags_string_mask = 0x0003;
    pub const flags_string_ascii = 0x0000;
    pub const flags_string_ucs1 = 0x0001;
    pub const flags_string_ucs2 = 0x0002;
    pub const flags_string_ucs4 = 0x0003;

    pub const flags_codeobject_collects_args = 0x0001;
    pub const flags_codeobject_collects_kws = 0x0002;
    pub const flags_codeobject_is_generator = 0x0004;
    pub const flags_codeobject_is_coroutine = 0x0008;

    pub const flags_function_mask = 0x0003;
    pub const flags_function_is_class_method = 0x0001;
    pub const flags_function_is_static_method = 0x0002;

    pub const flags_no_inherit = 0x0200;
    pub const flags_second_chance = 0x0100;
    pub const flags_is_marked = 0x0010;
    pub const flags_in_repr = 0x0020;
    pub const flags_immortal = 0x0040;
    pub const flags_valid_hash = 0x0080;

    extern "c" fn krk_callDirect(callable: *KrkObj, arg_count: c_int) KrkValue;

    /// Call a closure or native function with `arg_count` arguments.
    ///
    /// Calls the closure or native `callable` with arguments from the
    /// top of the stack. `arg_count` arguments are popped from the stack
    /// and the return value of the call is returned.
    ///
    /// - `callable` Closure or native function.
    /// - `arg_count` Arguments to collect from the stack.
    /// return: The return value of the function.
    pub inline fn callDirect(callable: *KrkObj, arg_count: c_int) KrkValue {
        return krk_callDirect(callable, arg_count);
    }
};

/// Immutable sequence of Unicode codepoints.
pub const KrkString = extern struct {
    obj: KrkObj,
    length: usize,
    codes_length: usize,
    chars: [*:0]u8,
    codes: ?*anyopaque,

    extern "c" fn krk_takeString(chars: [*:0]u8, length: usize) *KrkString;
    extern "c" fn krk_takeStringVetted(chars: [*:0]u8, length: usize, codes_length: usize, flags: c_uint, hash: u32) *KrkString;
    extern "c" fn krk_copyString(chars: [*:0]const u8, length: usize) *KrkString;
    extern "c" fn krk_unicodeString(string: *KrkString) *anyopaque;
    extern "c" fn krk_unicodeCodepoint(string: *KrkString, index: usize) u32;
    extern "c" fn krk_codepointToBytes(value: i64, out: [*]u8) usize;

    /// Yield ownership of a C string to the GC and obtain a string object.
    ///
    /// Creates a string object represented by the characters in `chars` and of
    /// length `length`. The source string must be nil-terminated and must
    /// remain valid for the lifetime of the object, as its ownership is yielded
    /// to the GC. Useful for strings which were allocated on the heap by
    /// other mechanisms.
    ///
    /// `chars` must be a nil-terminated C string representing a UTF-8
    /// character sequence.
    ///
    /// - `chars` C string to take ownership of.
    ///
    /// return: A string object.
    pub inline fn takeString(chars: [*:0]u8) *KrkString {
        return krk_takeString(chars, std.mem.len(chars));
    }

    /// Like `takeString` but for when the caller has already calculated
    /// code lengths, hash, and string type.
    ///
    /// Creates a new string object in cases where the caller has already calculated
    /// codepoint length, expanded string type, and hash. Useful for functions that
    /// create strings from other KrkStrings, where it's easier to know these things
    /// without having to start from scratch.
    ///
    /// - `chars` C string to take ownership of.
    /// - `length` Length of the C string.
    /// - `codes_length` Length of the expected resulting KrkString in codepoints.
    /// - `flags` Compact type of the string, eg. UCS1, UCS2, UCS4...
    /// - `hash` Precalculated string hash.
    pub inline fn takeStringVetted(chars: [*:0]u8, length: usize, codes_length: usize, flags: c_uint, hash: u32) *KrkString {
        return krk_takeStringVetted(chars, length, codes_length, flags, hash);
    }

    /// Obtain a string object representation of the given C string.
    ///
    /// Converts the C string `chars` into a string object by checking the
    /// string table for it. If the string table does not have an equivalent
    /// string, a new one will be created by copying `chars`.
    ///
    /// `chars` must be a nil-terminated C string representing a UTF-8
    /// character sequence.
    ///
    /// - `chars`  C string to convert to a string object.
    ///
    /// return: A string object.
    pub inline fn copyString(chars: [*:0]const u8) *KrkString {
        return krk_copyString(chars, std.mem.len(chars));
    }

    /// Ensure that a codepoint representation of a string is available.
    ///
    /// Obtain an untyped pointer to the codepoint representation of a string.
    /// If the string does not have a codepoint representation allocated, it will
    /// be generated by this function and remain with the string for the duration
    /// of its lifetime.
    ///
    /// - `string` String to obtain the codepoint representation of.
    ///
    /// return: A pointer to the bytes of the codepoint representation.
    pub inline fn unicodeString(string: *KrkString) *anyopaque {
        return krk_unicodeString(string);
    }

    /// Obtain the codepoint at a given index in a string.
    ///
    /// This is a convenience function which ensures that a Unicode codepoint
    /// representation has been generated and returns the codepoint value at
    /// the requested index. If you need to find multiple codepoints, it
    /// is recommended that you use the KRK_STRING_FAST macro after calling
    /// krk_unicodeString instead.
    ///
    /// note: This function does not perform any bounds checking.
    ///
    /// - `string` String to index into.
    /// - `index` Offset of the codepoint to obtain.
    ///
    /// return: Integer representation of the codepoint at the requested index.
    pub inline fn unicodeCodepoint(string: *KrkString, index: usize) u32 {
        return krk_unicodeCodepoint(string, index);
    }

    /// Convert an integer codepoint to a UTF-8 byte representation.
    ///
    /// Converts a single codepoint to a sequence of bytes containing the
    /// UTF-8 representation. `out` must be allocated by the caller.
    ///
    /// - `value` Codepoint to encode.
    /// - `out` Array to write UTF-8 sequence into.
    ///
    /// return: The length of the UTF-8 sequence, in bytes.
    pub inline fn codepointToBytes(value: i64, out: [*]u8) usize {
        return krk_codepointToBytes(value, out);
    }

    pub inline fn asValue(string: *KrkString) KrkValue {
        return KrkValue.objectValue(&string.obj);
    }
};

/// Immutable sequence of bytes.
pub const KrkBytes = extern struct {
    obj: KrkObj,
    length: usize,
    bytes: [*]u8,

    extern "c" fn krk_newBytes(length: usize, source: [*]u8) *KrkBytes;

    /// Create a new byte array.
    ///
    /// Allocates a bytes object of the given size, optionally copying
    /// data from `source`.
    pub inline fn create(source: []u8) *KrkBytes {
        return krk_newBytes(source.len, source.ptr);
    }

    pub inline fn asValue(bytes: *KrkBytes) KrkValue {
        return KrkValue.objectValue(&bytes.obj);
    }
};

/// Storage for values referenced from nested functions.
pub const KrkUpvalue = extern struct {
    obj: KrkObj,
    location: c_int,
    closed: KrkValue,
    next: ?*KrkUpvalue,
    owner: *KrkThreadState,

    extern "c" fn krk_newUpvalue(slot: c_int) *KrkUpvalue;

    /// Create an upvalue slot.
    ///
    /// Upvalue slots hold references to values captured in closures.
    /// This function should only be used directly by the VM in the
    /// process of running compiled bytecode and creating function
    /// objects from code objects.
    pub inline fn create(slot: c_int) *KrkUpvalue {
        return krk_newUpvalue(slot);
    }

    pub inline fn asValue(upvalue: *KrkUpvalue) KrkValue {
        return KrkValue.objectValue(&upvalue.obj);
    }
};

/// Code object.
///
/// Contains the static data associated with a chunk of bytecode.
pub const KrkCodeObject = extern struct {
    obj: KrkObj,
    required_args: c_ushort,
    keyword_args: c_ushort,
    potential_positionals: c_ushort,
    total_arguments: c_ushort,
    upvalue_count: usize,
    chunk: KrkChunk,
    name: *KrkString,
    docstring: *KrkString,
    positional_arg_names: KrkValueArray,
    keyword_arg_names: KrkValueArray,
    local_name_capacity: usize,
    local_name_count: usize,
    local_names: [*]KrkLocalEntry,
    qualname: *KrkString,
    expressions_capacity: usize,
    expressions_count: usize,
    expressions: [*]KrkExpressionsMap,
    jump_targets: KrkValue,
    overlong_jumps: [*]KrkOverlongJump,
    overlong_jumps_capacity: usize,
    overlong_jumps_count: usize,

    /// Metadata on a local variable name in a function.
    ///
    /// This is used by the disassembler to print the names of
    /// locals when they are referenced by instructions.
    pub const KrkLocalEntry = extern struct {
        id: usize,
        birthday: usize,
        deathday: usize,
        name: *KrkString,
    };

    /// Map entry of opcode offsets to expressions spans.
    ///
    /// Used for printing tracebacks with underlined expressions.
    pub const KrkExpressionsMap = extern struct {
        bytecode_offset: u32,
        start: u8,
        mid_start: u8,
        mid_end: u8,
        end: u8,
    };

    pub const KrkOverlongJump = extern struct {
        instruction_offset: u32,
        intended_target: u16,
        original_opcode: u8,
    };

    extern "c" fn krk_newCodeObject() *KrkCodeObject;

    /// Create a new, uninitialized code object.
    ///
    /// The code object will have an empty bytecode chunk and
    /// no assigned names or docstrings. This is intended only
    /// to be used by a compiler directly.
    pub inline fn create() *KrkCodeObject {
        return krk_newCodeObject();
    }

    pub inline fn asValue(code: *KrkCodeObject) KrkValue {
        return KrkValue.objectValue(&code.obj);
    }
};

/// Function object.
///
/// Not to be confused with code objects, a closure is a single instance of a function.
pub const KrkClosure = extern struct {
    obj: KrkObj,
    function: *KrkCodeObject,
    upvalues: [*][*]KrkUpvalue,
    upvalue_count: usize,
    annotations: KrkValue,
    fields: KrkTable,
    globals_owner: KrkValue,
    globals_table: *KrkTable,

    extern "c" fn krk_newClosure(function: *KrkCodeObject, globals: KrkValue) *KrkClosure;
    extern "c" fn krk_buildGenerator(function: *KrkClosure, arguments: *KrkValue, arg_count: usize) *KrkInstance;

    /// Create a new function object.
    ///
    /// Function objects are the callable first-class objects representing
    /// functions in managed code. Each function object has an associated
    /// code object, which may be sured with other function objects, such
    /// as when a function is used to create a closure.
    ///
    /// - `function` Code object to assign to the new function object.
    pub inline fn create(function: *KrkCodeObject, globals: KrkValue) *KrkClosure {
        return krk_newClosure(function, globals);
    }

    /// Convert a function into a generator with the given arguments.
    ///
    /// Converts the function `function` to a generator object and provides it `arguments`
    /// (of length `arg_count`) as its initial arguments. The generator object is returned.
    ///
    /// - `function` Function to convert.
    /// - `arguments` Arguments to pass to the generator.
    /// - `arg_count` Number of arguments in `arguments`.
    ///
    /// return: A new generator object.
    pub inline fn buildGenerator(function: *KrkClosure, arguments: *KrkValue, arg_count: usize) *KrkInstance {
        return krk_buildGenerator(function, arguments, arg_count);
    }

    pub inline fn asValue(function: *KrkClosure) KrkValue {
        return KrkValue.objectValue(&function.obj);
    }
};

/// Type object.
///
/// Represents classes defined in user code as well as classes defined
/// by C extensions to represent method tables for new types.
pub const KrkClass = extern struct {
    obj: KrkObj,
    _class: *KrkClass,
    methods: KrkTable,
    name: *KrkString,
    filename: *KrkString,
    base: ?*KrkClass,
    alloc_size: usize,
    _ongcscan: KrkCleanupCallback,
    _ongcsweep: KrkCleanupCallback,
    subclasses: KrkTable,
    _getter: *KrkObj,
    _setter: *KrkObj,
    _reprer: *KrkObj,
    _tostr: *KrkObj,
    _call: *KrkObj,
    _init: *KrkObj,
    _eq: *KrkObj,
    _len: *KrkObj,
    _enter: *KrkObj,
    _exit: *KrkObj,
    _delitem: *KrkObj,
    _iter: *KrkObj,
    _getattr: *KrkObj,
    _dir: *KrkObj,
    _contains: *KrkObj,
    _descget: *KrkObj,
    _descset: *KrkObj,
    _classgetitem: *KrkObj,
    _hash: *KrkObj,
    _add: *KrkObj,
    _radd: *KrkObj,
    _iadd: *KrkObj,
    _sub: *KrkObj,
    _rsub: *KrkObj,
    _isub: *KrkObj,
    _mul: *KrkObj,
    _rmul: *KrkObj,
    _imul: *KrkObj,
    _or: *KrkObj,
    _ror: *KrkObj,
    _ior: *KrkObj,
    _xor: *KrkObj,
    _rxor: *KrkObj,
    _ixor: *KrkObj,
    _and: *KrkObj,
    _rand: *KrkObj,
    _iand: *KrkObj,
    _mod: *KrkObj,
    _rmod: *KrkObj,
    _imod: *KrkObj,
    _pow: *KrkObj,
    _rpow: *KrkObj,
    _ipow: *KrkObj,
    _lshift: *KrkObj,
    _rlshift: *KrkObj,
    _ilshift: *KrkObj,
    _rshift: *KrkObj,
    _rrshift: *KrkObj,
    _irshift: *KrkObj,
    _truediv: *KrkObj,
    _rtruediv: *KrkObj,
    _itruediv: *KrkObj,
    _floordiv: *KrkObj,
    _rfloordiv: *KrkObj,
    _ifloordiv: *KrkObj,
    _lt: *KrkObj,
    _gt: *KrkObj,
    _le: *KrkObj,
    _ge: *KrkObj,
    _invert: *KrkObj,
    _negate: *KrkObj,
    _set_name: *KrkObj,
    _matmul: *KrkObj,
    _rmatmul: *KrkObj,
    _imatmul: *KrkObj,
    _pos: *KrkObj,
    _setattr: *KrkObj,
    _format: *KrkObj,
    _new: *KrkObj,
    _bool: *KrkObj,
    cache_index: usize,

    pub const KrkCleanupCallback = ?*const fn (*KrkInstance) callconv(.C) void;

    extern "c" fn krk_newClass(name: *KrkString, base: ?*KrkClass) *KrkClass;
    extern "c" fn krk_runtimeError(classs: *KrkClass, fmt: [*:0]const u8, ...) KrkValue;
    extern "c" fn krk_bindMethod(class: *KrkClass, name: *KrkString) c_int;
    extern "c" fn krk_bindMethodSuper(base_class: *KrkClass, name: *KrkString, real_class: *KrkClass) c_int;
    extern "c" fn krk_makeClass(module: ?*KrkInstance, class: **KrkClass, name: [*:0]const u8, base: *KrkClass) *KrkClass;
    extern "c" fn krk_finalizeClass(class: *KrkClass) void;
    extern "c" fn krk_isSubClass(class: *const KrkClass, base: *const KrkClass) c_int;

    /// Create a new class object.
    ///
    /// Creates a new class with the give name and base class.
    /// Generally, you will want to use `krk_makeClass` instead,
    /// which handles binding the class to a module.
    pub inline fn create(name: *KrkString, base: ?*KrkClass) *KrkClass {
        return krk_newClass(name, base);
    }

    pub inline fn setDoc(class: *KrkClass, text: [*:0]const u8) void {
        class.methods.attachNamedObject("__doc__", @ptrCast(KrkString.copyString(text)));
    }

    /// Convenience function for creating new types.
    ///
    /// Creates a class object, setting its name to `name`, inheriting
    /// from `base`, and attaching it with its name to the fields table of the given `module`.
    ///
    /// - `module` Pointer to an instance for a module to attach to, or null to skip attaching.
    /// - `T` The struct type of the class to be create.
    /// - `name` Name of the new class.
    /// - `base` Pointer to class object to inherit from.
    ///
    /// return: A pointer to the class object.
    pub inline fn makeClass(module: ?*KrkInstance, T: type, name: [*:0]const u8, base: ?*KrkClass) *KrkClass {
        var class: *KrkClass = undefined;
        _ = krk_makeClass(
            module,
            &class,
            name,
            if (base == null) KrkVM.getInstance().base_classes.objectClass else base.?,
        );
        class.alloc_size = @sizeOf(T);
        return class;
    }

    pub inline fn asValue(class: *KrkClass) KrkValue {
        return KrkValue.objectValue(&class.obj);
    }

    /// Produce and raise an exception with a formatted message.
    ///
    /// Creates an instance of the given exception type, passing a formatted
    /// string to the initializer. All of the core exception types take an option
    /// string value to attach to the exception, but third-party exception types
    /// may have different initializer signatures and need separate initialization.
    ///
    /// The created exception object is attached to the current thread state and
    /// the `KrkFlags.thread_has_exception` flag is set.
    ///
    /// If the format string is exactly "%V", the first format argument will
    /// be attached the exception as the 'msg' attribute.
    ///
    /// No field width or precisions are supported on any conversion specifiers.
    ///
    /// Standard conversion specifiers 'c', 's', 'd', 'u' are available, and the
    /// 'd' and 'u' specifiers may have length modifiers of l, L, or z.
    ///
    /// Additional format specifiers are as follows:
    ///
    /// `%S` - Accepts one `KrkString*` to be printed in its entirety.
    ///
    /// `%R` - Accepts one `KrkValue` and calls repr on it.
    ///
    /// `%T` - Accepts one `KrkValue` and emits the name of its type.
    ///
    /// - `class` Class pointer for the exception type, eg. `krk_vm.exceptions->valueError`
    /// - `fmt` Format string.
    pub fn runtimeError(class: *KrkClass, fmt: [*:0]const u8, args: anytype) KrkValue {
        return @call(.auto, krk_runtimeError, .{ class, fmt } ++ args);
    }

    /// See `KrkTable.defineNative`
    pub inline fn bindMethod(class: *KrkClass, name: [*:0]const u8, method: KrkNativeFn) *KrkNative {
        return class.methods.defineNative(name, method);
    }

    /// See `KrkTable.defineNativeProperty`
    pub inline fn bindProperty(class: *KrkClass, name: [*:0]const u8, method: KrkNativeFn) *KrkNative {
        return class.methods.defineNativeProperty(name, method);
    }

    /// See `KrkTable.defineNativeStaticMethod`
    pub inline fn bindStaticMethod(class: *KrkClass, name: [*:0]const u8, method: KrkNativeFn) *KrkNative {
        return class.methods.defineNativeStaticMethod(name, method);
    }

    /// See `KrkTable.defineNativeClassMethod`
    pub inline fn bindClassMethod(class: *KrkClass, name: [*:0]const u8, method: KrkNativeFn) *KrkNative {
        return class.methods.defineNativeClassMethod(name, method);
    }

    /// Perform method binding on the stack.
    ///
    /// Performs attribute lookup from the class for `name`.
    /// If `name` is not a valid member, the binding fails.
    /// If `name` is a valid method, the method will be retrieved and
    /// bound to the instance on the top of the stack, replacing it
    /// with a `BoundMethod` object.
    /// If `name` is not a method, the unbound attribute is returned.
    /// If `name` is a descriptor, the `__get__` method is executed.
    ///
    /// - `name` String object with the name of the method to resolve.
    ///
    /// return: true if the method has been bound, false if binding failed.
    pub inline fn bindMethodOnStack(class: *KrkClass, name: *KrkString) bool {
        return krk_bindMethod(class, name) == 1;
    }

    /// Bind a method with `super()` semantics
    ///
    /// Allows binding potential class methods with the correct class object while
    /// searching from a base class. Used by the `super()` mechanism.
    ///
    /// - `baseClass` The superclass to begin searching from.
    /// - `name` The name of the member to look up.
    /// - `realClass` The class to bind if a class method is found.
    ///
    /// return: true if a member has been found, false if binding fails.
    pub inline fn bindMethodSuper(base_class: *KrkClass, name: *KrkString, real_class: *KrkClass) bool {
        return krk_bindMethodSuper(base_class, name, real_class) == 1;
    }

    /// Finalize a class by collecting pointers to core methods.
    ///
    /// Scans through the methods table of a class object to find special
    /// methods and assign them to the class object's pointer table so they
    /// can be referenced directly without performing hash lookups.
    pub inline fn finalizeClass(class: *KrkClass) void {
        return krk_finalizeClass(class);
    }

    pub inline fn isSubClass(class: *const KrkClass, base: *const KrkClass) bool {
        return krk_isSubClass(class, base) == 1;
    }
};

/// An object of a class.
///
/// Created by class initializers, instances are the standard type of objects
/// built by managed code. Not all objects are instances, but all instances are
/// objects, and all instances have well-defined class.
pub const KrkInstance = extern struct {
    obj: KrkObj,
    _class: *KrkClass,
    fields: KrkTable,

    extern "c" fn krk_newInstance(class: *KrkClass) *KrkInstance;

    /// Create a new instance of the given class.
    ///
    /// Handles allocation, but not `__init__`, of the new instance.
    /// Be sure to populate any fields expected by the class or call
    /// its `__init__` function (eg. with `krk_callStack`) as needed.
    pub inline fn create(class: *KrkClass) *KrkInstance {
        return krk_newInstance(class);
    }

    pub inline fn setDoc(instance: *KrkInstance, text: [*:0]const u8) void {
        instance.fields.attachNamedObject("__doc__", @ptrCast(KrkString.copyString(text)));
    }

    pub inline fn asValue(instance: *KrkInstance) KrkValue {
        return KrkValue.objectValue(&instance.obj);
    }

    pub inline fn bindFunction(module: *KrkInstance, name: [*:0]const u8, function: KrkNativeFn) *KrkNative {
        return module.fields.defineNative(name, function);
    }
};

/// A function that has been attached to an object to serve as a method.
///
/// When a bound method is called, its receiver is implicitly extracted as
/// the first argument. Bound methods are created whenever a method is retreived
/// from the class of a value.
pub const KrkBoundMethod = extern struct {
    obj: KrkObj,
    receiver: KrkValue,
    method: *KrkObj,

    extern "c" fn krk_newBoundMethod(receiver: KrkValue, method: *KrkObj) *KrkBoundMethod;

    /// Create a new bound method.
    ///
    /// Binds the callable specified by `method` to the value `receiver`
    /// and returns a `method` object. When a `method` object is called,
    /// `receiver` will automatically be provided as the first argument.
    pub inline fn create(receiver: KrkValue, method: *KrkObj) *KrkBoundMethod {
        return krk_newBoundMethod(receiver, method);
    }

    pub inline fn asValue(bound_method: *KrkBoundMethod) KrkValue {
        return KrkValue.objectValue(&bound_method.obj);
    }
};

pub const KrkNativeFn = ?*const fn (
    arg_count: c_int,
    args: [*]const KrkValue,
    has_kwargs: c_int,
) callconv(.C) KrkValue;

/// Managed binding to a C function.
///
/// Represents a C function that has been exposed to managed code.
pub const KrkNative = extern struct {
    obj: KrkObj,
    function: KrkNativeFn,
    name: [*:0]const u8,
    doc: [*:0]const u8,

    extern "c" fn krk_newNative(function: KrkNativeFn, name: [*:0]const u8, flags: c_int) *KrkNative;

    /// Create a native function binding object.
    ///
    /// Converts a C function pointer into a native binding object
    /// which can then be used in the same place a function object
    /// (`KrkClosure`) would be used.
    pub inline fn create(function: KrkNativeFn, name: [*:0]const u8, flags: c_int) *KrkNative {
        return krk_newNative(function, name, flags);
    }

    pub inline fn setDoc(native: *KrkNative, text: [*:0]const u8) void {
        native.doc = text;
    }

    pub inline fn asValue(native: *KrkNative) KrkValue {
        return KrkValue.objectValue(&native.obj);
    }
};

/// Immutable sequence of arbitrary values.
///
/// Tuples are fixed-length non-mutable collections of values intended
/// for use in situations where the flexibility of a list is not needed.
pub const KrkTuple = extern struct {
    obj: KrkObj,
    values: KrkValueArray,

    extern "c" fn krk_newTuple(length: usize) *KrkTuple;
    extern "c" fn krk_tuple_of(argc: c_int, argv: [*]const KrkValue, has_kw: c_int) KrkValue;

    /// Create a new tuple.
    ///
    /// Creates a tuple object with the request space preallocated.
    /// The actual length of the tuple must be updated after places
    /// values within it by setting `value.count`.
    pub inline fn create(length: usize) *KrkTuple {
        return krk_newTuple(length);
    }

    pub inline fn tupleOf(argc: c_int, argv: [*]const KrkValue, has_kw: bool) KrkValue {
        return krk_tuple_of(argc, argv, @intFromBool(has_kw));
    }

    pub inline fn asValue(tuple: *KrkTuple) KrkValue {
        return KrkValue.objectValue(&tuple.obj);
    }
};

/// Mutable array of values.
///
/// A list is a flexible array of values that can be extended, cleared,
/// sorted, rearranged, iterated over, etc.
pub const KrkList = extern struct {
    inst: KrkInstance,
    values: KrkValueArray,

    extern "c" fn krk_list_of(argc: c_int, argv: ?[*]const KrkValue, hasKw: c_int) KrkValue;

    pub inline fn listOf(argc: c_int, argv: ?[*]const KrkValue, has_kw: bool) KrkValue {
        return krk_list_of(argc, argv, @intFromBool(has_kw));
    }
};

/// Flexible mapping type.
///
/// Provides key-to-value mappings as a first-class object type.
pub const KrkDict = extern struct {
    inst: KrkInstance,
    entries: KrkTable,

    extern "c" fn krk_dict_of(argc: c_int, argv: ?[*]const KrkValue, has_kw: c_int) KrkValue;

    pub inline fn dictOf(argc: c_int, argv: ?[*]const KrkValue, has_kw: bool) KrkValue {
        return krk_dict_of(argc, argv, @intFromBool(has_kw));
    }
};

pub const DictItems = extern struct {
    inst: KrkInstance,
    dict: KrkValue,
    i: usize,
};

pub const DictKeys = extern struct {
    inst: KrkInstance,
    dict: KrkValue,
    i: usize,
};

pub const DictValues = extern struct {
    inst: KrkInstance,
    dict: KrkValue,
    i: usize,
};

/// Mutable unordered set of values.
pub const Set = extern struct {
    inst: KrkInstance,
    entries: KrkTable,

    extern "c" fn krk_set_of(argc: c_int, argv: ?[*]const KrkValue, has_kw: c_int) KrkValue;

    pub inline fn setOf(argc: c_int, argv: ?[*]const KrkValue, has_kw: bool) KrkValue {
        return krk_set_of(argc, argv, @intFromBool(has_kw));
    }
};

pub const ByteArray = extern struct {
    inst: KrkInstance,
    actual: KrkValue,
};

/// Representation of a loaded module.
pub const KrkModule = extern struct {
    const krk_dlRefType = ?*anyopaque;
    inst: KrkInstance,
    lib_handle: krk_dlRefType,
};

pub const KrkSlice = extern struct {
    inst: KrkInstance,
    start: KrkValue,
    end: KrkValue,
    step: KrkValue,

    extern "c" fn krk_slice_of(argc: c_int, argv: ?[*]const KrkValue, has_kw: c_int) KrkValue;

    pub inline fn sliceOf(argc: c_int, argv: ?[*]const KrkValue, has_kw: c_int) KrkValue {
        return krk_slice_of(argc, argv, @intFromBool(has_kw));
    }
};

/// Calls `__await__`
pub extern "c" fn krk_getAwaitable() c_int;

/// Special value for type hint expressions.
///
/// Returns a generic alias object. Bind this to a class's `__class_getitem__`
/// to allow for generic collection types to be used in type hints.
pub extern var krk_GenericAlias: KrkNativeFn;

fn hashString(chars: []const u8) u32 {
    var hash: u32 = 0;
    for (chars) |c| {
        hash = c + (hash << 6) + (hash << 16) - hash;
    }
    return hash;
}

/// Simple hash table of arbitrary keys to values.
pub const KrkTable = extern struct {
    count: usize,
    capacity: usize,
    used: usize,
    entries: [*]KrkTableEntry,
    indexes: [*]isize,

    /// One (key,value) pair in a table.
    pub const KrkTableEntry = extern struct {
        key: KrkValue,
        value: KrkValue,
    };

    extern "c" fn krk_initTable(table: *KrkTable) void;
    extern "c" fn krk_freeTable(table: *KrkTable) void;
    extern "c" fn krk_tableAddAll(from: *KrkTable, to: *KrkTable) void;
    extern "c" fn krk_tableFindString(table: *KrkTable, chars: [*]const u8, length: usize, hash: u32) ?*KrkString;
    extern "c" fn krk_tableSet(table: *KrkTable, key: KrkValue, value: KrkValue) c_int;
    extern "c" fn krk_tableGet(table: *KrkTable, key: KrkValue, value: *KrkValue) c_int;
    extern "c" fn krk_tableGet_fast(table: *KrkTable, str: *KrkString, value: *KrkValue) c_int;
    extern "c" fn krk_tableDelete(table: *KrkTable, key: KrkValue) c_int;
    extern "c" fn krk_tableDeleteExact(table: *KrkTable, key: KrkValue) c_int;
    extern "c" fn krk_tableAdjustCapacity(table: *KrkTable, capacity: usize) void;
    extern "c" fn krk_tableSetIfExists(table: *KrkTable, key: KrkValue, value: KrkValue) c_int;
    extern "c" fn krk_defineNative(table: *KrkTable, name: [*:0]const u8, function: KrkNativeFn) *KrkNative;
    extern "c" fn krk_defineNativeProperty(table: *KrkTable, name: [*:0]const u8, func: KrkNativeFn) *KrkNative;
    extern "c" fn krk_attachNamedValue(table: *KrkTable, name: [*:0]const u8, obj: KrkValue) void;
    extern "c" fn krk_attachNamedObject(table: *KrkTable, name: [*:0]const u8, obj: *KrkObj) void;

    /// Initialize a hash table.
    ///
    /// This should be called for any new hash table, especially ones
    /// initialized in heap or stack space, to set up the capacity, count
    /// and initial entries pointer.
    pub inline fn init(table: *KrkTable) void {
        krk_initTable(table);
    }

    /// Release resources associated with a hash table.
    ///
    /// Frees the entries array for the table and resets count and capacity.
    pub inline fn deinit(table: *KrkTable) void {
        krk_freeTable(table);
    }

    /// Add all key-value pairs from `src` into `dest`.
    ///
    /// Copies each key-value pair from one hash table to another. If a keyb
    /// from `src` already exists in `dest`, the existing value in 'to' will beis
    /// overwritten with the value from `src`.
    pub inline fn addAll(dest: *KrkTable, src: *KrkTable) void {
        krk_tableAddAll(src, dest);
    }

    /// Find a character sequence in the string interning table.
    ///
    /// Scans through the entries in a given table - usually vm.strings - to find
    /// an entry equivalent to the string specified by `chars` parameters
    pub inline fn findString(table: *KrkTable, chars: []const u8) ?*KrkString {
        return krk_tableFindString(table, chars.ptr, chars.len, hashString(chars));
    }

    /// Assign a value to a key in a table.
    ///
    /// Inserts the key-value pair specified by `key` and `value` into the hash
    /// table `table`, replacing any value that was already preseng with the
    /// same key.
    ///
    /// - `key` Key to assign.
    /// - `value`Value to assign to the key.
    pub inline fn set(table: *KrkTable, key: KrkValue, value: KrkValue) void {
        _ = krk_tableSet(table, key, value);
    }

    /// Obtain the value associated with a key in a table.
    ///
    /// Scans the table `table` for the key `key` and, if found, returns
    /// the associated value. If the key is not found, returns `null`.
    ///
    /// - `key` Key to look for.
    ///
    /// return: null if the key was not found, the associated value if it was.
    pub inline fn get(table: *KrkTable, key: KrkValue) ?KrkValue {
        var value: KrkValue = undefined;
        if (krk_tableGet(table, key, &value) == 1) {
            return value;
        }
        return null;
    }

    /// Obtain the value associated with a string key in a table.
    ///
    /// Same as `KrkTable.get()`, but only works for string keys. This is faster
    /// than using KrkTable.get() and should be used when referencing attribute
    /// tables or other places where keys are guaranteed to only be strings.
    ///
    /// - `str` Key to look for.
    ///
    /// return: null if the key was not found, the associated value if it was.
    pub inline fn getFast(table: *KrkTable, str: *KrkString) ?KrkValue {
        var value: KrkValue = undefined;
        if (krk_tableGet_fast(table, str, &value) == 1) {
            return value;
        }
        return null;
    }

    /// Remove a key from a hash table.
    ///
    /// Scans the table for the key and, if found, removes
    /// the entry, replacing it with a tombstone value.
    ///
    /// - `table` Table to delete from.
    /// - `key` Key to delete.
    ///
    /// return: true if the value was found and deleted, false if it was not present.
    pub inline fn delete(table: *KrkTable, key: KrkValue) bool {
        return krk_tableDelete(table, key) == 1;
    }

    /// Remove a key from a hash table, with identity lookup.
    ///
    /// Scans the table for the key and, if found, removes
    /// the entry, replacing it with a tombstone value.
    ///
    /// - `table` Table to delete from.
    /// - `key` Key to delete.
    ///
    /// return: true if the value was found and deleted, false if it was not present.
    pub inline fn deleteExact(table: *KrkTable, key: KrkValue) bool {
        return krk_tableDeleteExact(table, key) == 1;
    }

    /// Preset the size of a table.
    ///
    /// Reserves space for a large table.
    pub inline fn adjustCapacity(table: *KrkTable, capacity: usize) void {
        krk_tableAdjustCapacity(table, capacity);
    }

    /// Update the value of a table entry only if it is found.
    ///
    /// Searches the table for `key` and updates its value to `value` if found.
    /// If `key` is not found, it is not added to the table.
    ///
    /// - `key` Key to assign.
    /// - `value` Value to assign to the key.
    ///
    /// return: false if the key was not present, true if it was found and updated.
    pub inline fn setIfExists(table: *KrkTable, key: KrkValue, value: KrkValue) bool {
        return krk_tableSetIfExists(table, key, value) == 1;
    }

    /// Attach a native C function to an attribute table.
    ///
    /// Attaches the given native function pointer to an attribute table
    /// while managing the stack shuffling and boxing of both the name and
    /// the function object. If `name` begins with a '.', the native function
    /// is marked as a method. If `name` begins with a ':', the native function
    /// is marked as a dynamic property.
    ///
    /// - `table` Attribute table to attach to, such as `&someInstance->fields`.
    /// - `name` Nil-terminated C string with the name to assign.
    /// - `function` Native function pointer to attach.
    ///
    /// return: A pointer to the object representing the attached function.
    pub inline fn defineNative(table: *KrkTable, name: [*:0]const u8, function: KrkNativeFn) *KrkNative {
        return krk_defineNative(table, name, function);
    }

    /// Like `KrkTable.defineNative`, but add `KrkObj.flags_function_is_static_method` flag.
    pub inline fn defineNativeStaticMethod(table: *KrkTable, name: [*:0]const u8, function: KrkNativeFn) *KrkNative {
        const out = krk_defineNative(table, name, function);
        out.obj.flags |= KrkObj.flags_function_is_static_method;
        return out;
    }

    /// Like `KrkTable.defineNative`, but add `KrkObj.flags_function_is_class_method` flag.
    pub inline fn defineNativeClassMethod(table: *KrkTable, name: [*:0]const u8, function: KrkNativeFn) *KrkNative {
        const out = krk_defineNative(table, name, function);
        out.obj.flags |= KrkObj.flags_function_is_class_method;
        return out;
    }

    /// Attach a native dynamic property to an attribute table.
    ///
    /// Mostly the same as `KrkTable.defineNative`, but ensures the creation of a dynamic property.
    /// The intention of this function is to replace uses of defineNative with ":" names,
    /// and replace specialized methods with `KrkProperty*` objects.
    ///
    /// - `table` Attribute table to attach to, such as `&someInstance->fields`.
    /// - `name` Nil-terminated C string with the name to assign.
    /// - `function` Native function pointer to attach.
    ///
    /// return: A pointer to the property object created.
    pub inline fn defineNativeProperty(table: *KrkTable, name: [*:0]const u8, function: KrkNativeFn) *KrkNative {
        return krk_defineNativeProperty(table, name, function);
    }

    /// Attach a value to an attribute table.
    ///
    /// Manages the stack shuffling and boxing of the name string when attaching
    /// a value to an attribute table. Rather than using `KrkTable.set`, this is
    /// the preferred method of supplying fields to objects from C code.
    ///
    /// Note that since this inserts values directly into tables, it skips any
    /// mechanisms like `__setattr__` or descriptor `__set__`. If you need to support
    /// these mechanisms, use `KrkVM.setAttribute`. If you have an instance and would
    /// like to emulate the behavior of object.__setattr__, you may also wish to
    /// use @c krk_instanceSetAttribute_wrapper.
    ///
    /// warning: As this function takes a C string, it does not support setting attributes
    /// with names containing nil bytes. Use one of the other mechanisms if you
    /// do not have full control over the attribute names you are trying to set.
    ///
    /// - `table` Attribute table to attach to, such as `&someInstance->fields`.
    /// - `name` Nil-terminated C string with the name to assign.
    /// - `obj` Value to attach.
    pub inline fn attachNamedValue(table: *KrkTable, name: [*:0]const u8, obj: KrkValue) void {
        krk_attachNamedValue(table, name, obj);
    }

    /// Attach an object to an attribute table.
    ///
    /// Manages the stack shuffling and boxing of the name string when attaching
    /// a value to an attribute table. Rather than using `KrkTable.set`, this is
    /// the preferred method of supplying fields to objects from C code.
    ///
    /// This is a convenience wrapper around `KrkTable.attachNamedValue`.
    ///
    /// Note that since this inserts values directly into tables, it skips any
    /// mechanisms like `__setattr__` or descriptor `__set__`. If you need to support
    /// these mechanisms, use `KrkVM.setAttribute`. If you have an instance and would
    /// like to emulate the behavior of object.__setattr__, you may also wish to
    /// use @c krk_instanceSetAttribute_wrapper.
    ///
    /// warning: As this function takes a C string, it does not support setting attributes
    /// with names containing nil bytes. Use one of the other mechanisms if you
    /// do not have full control over the attribute names you are trying to set.
    ///
    /// - `table` Attribute table to attach to, such as `&someInstance->fields`.
    /// - `name` Nil-terminated C string with the name to assign.
    /// - `obj` Value to attach.
    pub inline fn attachNamedObject(table: *KrkTable, name: [*:0]const u8, obj: *KrkObj) void {
        krk_attachNamedObject(table, name, obj);
    }
};

/// Represents a managed call state in a VM thread.
///
/// For every managed function call, including the top-level module,
/// a call frame is added to the stack to track the running function,
/// the current opcode instruction, the offset into the stack, and
/// the valid globals table.
///
/// Call frames are used directly by the VM as the source of
/// opcodes and operands during execution, and are used by the exceptio
/// handler to roll back execution to the appropriate environment.
pub const KrkCallFrame = extern struct {
    closure: *KrkClosure,
    ip: [*]u8,
    slots: usize,
    out_slots: usize,
    globals: *KrkTable,
    globals_owner: KrkValue,
};

/// Table of basic exception types.
///
/// These are the core exception types, available in managed code
/// from the builtin namespace. A single instance of this struct
/// is attached to the global VM state so that C code can quickly
/// access these exception types for use with krk_runtimeException.
pub const Exceptions = extern struct {
    baseException: *KrkClass,
    typeError: *KrkClass,
    argumentError: *KrkClass,
    indexError: *KrkClass,
    keyError: *KrkClass,
    attributeError: *KrkClass,
    nameError: *KrkClass,
    importError: *KrkClass,
    ioError: *KrkClass,
    valueError: *KrkClass,
    keyboardInterrupt: *KrkClass,
    zeroDivisionError: *KrkClass,
    notImplementedError: *KrkClass,
    syntaxError: *KrkClass,
    assertionError: *KrkClass,
    OSError: *KrkClass,
    ThreadError: *KrkClass,
    Exception: *KrkClass,
    SystemError: *KrkClass,
};

/// Table of classes for built-in object types.
///
/// For use by C modules and within the VM, an instance of this struct
/// is attached to the global VM state. At VM initialization, each
/// built-in class is attached to this table, and the class values
/// stored here are used for integrated type checking with `KrkValue.isInstanceOf`.
///
/// note: As this and other tables are used directly by embedders, do not
/// reorder the layout of the individual class pointers, even if
/// it looks nicer. The ordering here is part of our library ABI.
pub const BaseClasses = extern struct {
    objectClass: *KrkClass,
    moduleClass: *KrkClass,
    typeClass: *KrkClass,
    intClass: *KrkClass,
    floatClass: *KrkClass,
    boolClass: *KrkClass,
    noneTypeClass: *KrkClass,
    strClass: *KrkClass,
    functionClass: *KrkClass,
    methodClass: *KrkClass,
    tupleClass: *KrkClass,
    bytesClass: *KrkClass,
    listiteratorClass: *KrkClass,
    rangeClass: *KrkClass,
    rangeiteratorClass: *KrkClass,
    striteratorClass: *KrkClass,
    tupleiteratorClass: *KrkClass,
    listClass: *KrkClass,
    dictClass: *KrkClass,
    dictitemsClass: *KrkClass,
    dictkeysClass: *KrkClass,
    bytesiteratorClass: *KrkClass,
    propertyClass: *KrkClass,
    codeobjectClass: *KrkClass,
    generatorClass: *KrkClass,
    notImplClass: *KrkClass,
    bytearrayClass: *KrkClass,
    dictvaluesClass: *KrkClass,
    sliceClass: *KrkClass,
    longClass: *KrkClass,
    mapClass: *KrkClass,
    zipClass: *KrkClass,
    filterClass: *KrkClass,
    enumerateClass: *KrkClass,
    HelperClass: *KrkClass,
    LicenseReaderClass: *KrkClass,
    CompilerStateClass: *KrkClass,
    CellClass: *KrkClass,
    setClass: *KrkClass,
    setiteratorClass: *KrkClass,
    ThreadClass: *KrkClass,
    LockClass: *KrkClass,
    ellipsisClass: *KrkClass,
};

pub const KrkFlags = packed struct(c_int) {
    thread_enable_tracing: bool = false,
    thread_enable_disassembly: bool = false,
    _pad_0: u1 = 0,
    thread_has_exception: bool = false,
    thread_single_step: bool = false,
    thread_signalled: bool = false,
    thread_defer_stack_free: bool = false,
    _pad_1: u1 = 0,
    global_enable_stress_gc: bool = false,
    global_gc_paused: bool = false,
    global_clean_output: bool = false,
    _pad_2: u1 = 0,
    global_report_gc_collects: bool = false,
    global_threads: bool = false,
    global_no_default_modules: bool = false,
    _pad_3: u17 = 0,
};

/// Execution state of a VM thread.
///
/// Each thread in the VM has its own local thread state, which contains
/// the thread's stack, stack pointer, call frame stack, a thread-specific
/// VM flags bitarray, and an exception state.
pub const KrkThreadState = extern struct {
    next: ?*KrkThreadState,
    frames: [*]KrkCallFrame,
    frame_count: usize,
    stack_size: usize,
    stack: [*]KrkValue,
    stack_top: *KrkValue,
    open_upvalues: [*]KrkUpvalue,
    exit_on_frame: isize,
    module: *KrkInstance,
    current_exception: KrkValue,
    flags: KrkFlags,
    maximum_call_depth: c_uint,
    stack_max: *KrkValue,
    scratch_space: [3]KrkValue,
};

pub const KrkVM = struct {
    /// Global VM state.
    ///
    /// This state is shared by all VM threads and stores the
    /// path to the VM binary, global execution flags, the
    /// string and module tables, tables of builtin types,
    /// and the state of the (shared) garbage collector.
    pub const KrkVMState = extern struct {
        global_flags: KrkFlags,
        binpath: [*:0]u8,
        strings: KrkTable,
        modules: KrkTable,
        builtins: *KrkInstance,
        system: *KrkInstance,
        special_method_names: [*]KrkValue,
        base_classes: *BaseClasses,
        exceptions: *Exceptions,
        objects: ?*KrkObj,
        bytes_allocated: usize,
        next_gc: usize,
        gray_count: usize,
        gray_capacity: usize,
        gray_stack: [*][*]KrkObj,
        threads: ?*KrkThreadState,
        dbg_state: ?*anyopaque,
    };

    /// Singleton instance of the shared VM state.
    extern var krk_vm: KrkVMState;

    /// Get the Singleton instance of the shared VM state.
    pub inline fn getInstance() *KrkVMState {
        return &krk_vm;
    }

    extern "c" fn krk_initVM(flags: KrkFlags) void;
    extern "c" fn krk_freeVM() void;
    extern "c" fn krk_resetStack() void;
    extern "c" fn krk_interpret(src: [*:0]const u8, from_file: [*:0]const u8) KrkValue;
    extern "c" fn krk_runfile(filename: [*:0]const u8, from_file: [*:0]const u8) KrkValue;
    extern "c" fn krk_push(value: KrkValue) void;
    extern "c" fn krk_pop() KrkValue;
    extern "c" fn krk_peek(distance: c_int) KrkValue;
    extern "c" fn krk_swap(distance: c_int) void;
    extern "c" fn krk_raiseException(base: KrkValue, cause: KrkValue) void;
    extern "c" fn krk_attachInnerException(inner_exception: KrkValue) void;
    extern "c" fn krk_getCurrentThread() *KrkThreadState;
    extern "c" fn krk_runNext() KrkValue;
    extern "c" fn krk_callStack(arg_count: c_int) KrkValue;
    extern "c" fn krk_dumpTraceback() void;
    extern "c" fn krk_startModule(name: [*:0]const u8) *KrkInstance;
    extern "c" fn krk_dirObject(argc: c_int, argv: [*]const KrkValue, hasKw: c_int) KrkValue;
    extern "c" fn krk_module_init_kuroko() void;
    extern "c" fn krk_module_init_threading() void;
    extern "c" fn krk_module_init_libs() void;
    extern "c" fn krk_loadModule(path: *KrkString, module_out: *KrkValue, run_as: *KrkString, parent: KrkValue) c_int;
    extern "c" fn krk_doRecursiveModuleLoad(name: *KrkString) c_int;
    extern "c" fn krk_importModule(name: *KrkString, runAs: *KrkString) c_int;
    extern "c" fn krk_addObjects() void;
    extern "c" fn krk_setMaximumRecursionDepth(max_depth: usize) void;
    extern "c" fn krk_callNativeOnStack(arg_count: usize, stack_args: [*]const KrkValue, has_kw: c_int, native: KrkNativeFn) KrkValue;
    extern "c" fn krk_getAttribute(name: *KrkString) c_int;
    extern "c" fn krk_setAttribute(name: *KrkString) c_int;
    extern "c" fn krk_delAttribute(name: *KrkString) c_int;

    /// Initialize the VM at program startup.
    ///
    /// All library users must call this exactly once on startup to create
    /// the built-in types, modules, and functions for the VM and prepare
    /// the string and module tables. Optionally, callers may set `vm.binpath`
    /// before calling krk_initVM to allow the VM to locate the interpreter
    /// binary and establish the default module paths.
    ///
    /// - `flags` Combination of global VM flags and initial thread flags.
    pub inline fn init(flags: KrkFlags) void {
        krk_initVM(flags);
    }

    /// Release resources from the VM.
    ///
    /// Generally, it is desirable to call this once before the hosting program exits.
    /// If a fresh VM state is needed, krk_freeVM should be called before a further
    /// call to krk_initVM is made. The resources released here can include allocated
    /// heap memory, FILE pointers or descriptors, or various other things which were
    /// initialized by C extension modules.
    pub inline fn deinit() void {
        krk_freeVM();
    }
    /// Reset the current thread's stack state to the top level.
    ///
    /// In a repl, this should be called before or after each iteration to clean up any
    /// remnant stack entries from an uncaught exception. It should not be called
    /// during normal execution by C extensions. Values on the stack may be lost
    /// to garbage collection after a call to `krk_resetStack`.
    pub inline fn resetStack() void {
        krk_resetStack();
    }

    /// Compile and execute a source code input.
    ///
    /// Compiles and executes the source code in `src` and returns the result
    /// of execution - generally the return value of a function body or the
    /// last value on the stack in a REPL expression. This is the lowest level
    /// call for most usecases, including execution of commands from a REPL or
    /// when executing a file.
    ///
    /// The string provided in `from_file` is used in exception tracebacks.
    ///
    /// - `src` Source code to compile and run.
    /// - `from_file` Path to the source file, or a representative string like "\<stdin>".
    ///
    /// return: The value of the executed code, which is either the value of an explicit `return`
    /// statement, or the last expression value from an executed statement.  If an uncaught
    /// exception occurred, this will be `None` and `krk_currentThread.flags` should
    /// indicate `KrkFlags.thread_has_exception` and `krk_currentThread.currentException`
    /// should contain the raised exception value.
    pub inline fn interpret(src: [*:0]const u8, from_file: [*:0]const u8) KrkValue {
        return krk_interpret(src, from_file);
    }

    /// Load and run a source file and return when execution completes.
    ///
    /// Loads and runs a source file. Can be used by interpreters to run scripts,
    /// either in the context of a new a module or as if they were continuations
    /// of the current module state (eg. as if they were lines entered on a repl)
    ///
    /// - `filename` Path to the source file to read and execute.
    /// - `from_file` Value to assign to `__file__`
    ///
    /// return: As with `krk_interpret`, an object representing the newly created module,
    /// or the final return value of the VM execution.
    pub inline fn runFile(filename: [*:0]const u8, from_file: [*:0]const u8) KrkValue {
        return krk_runfile(filename, from_file);
    }

    /// Push a stack value.
    ///
    /// Pushes a value onto the current thread's stack, triggering a
    /// stack resize if there is not enough space to hold the new value.
    ///
    /// - `value` Value to push.
    pub inline fn push(value: KrkValue) void {
        krk_push(value);
    }

    /// Pop the top of the stack.
    ///
    /// Removes and returns the value at the top of current thread's stack.
    /// Generally, it is preferably to leave values on the stack and use
    /// `KrkVM.peek` if the value is desired, as removing a value from the stack
    /// may result in it being garbage collected.
    ///
    /// return: The value previously at the top of the stack.
    pub inline fn pop() KrkValue {
        return krk_pop();
    }

    /// Peek down from the top of the stack.
    ///
    /// Obtains a value from the current thread's stack without modifying the stack.
    ///
    /// - `distance` How far down from the top of the stack to peek (0 = the top)
    ///
    /// return: The value from the stack.
    pub inline fn peek(distance: i32) KrkValue {
        return krk_peek(distance);
    }

    /// Swap the top of the stack of the value `distance` slots down.
    ///
    /// Exchanges the values at the top of the stack and `distance` slots from the top
    /// without removing or shuffling anything in between.
    ///
    /// - `distance` How from down from the top of the stack to swap (0 = the top)
    pub inline fn swap(distance: i32) void {
        krk_swap(distance);
    }

    /// Concatenate two strings.
    ///
    /// This is a convenience function which calls `str.__add__` on the top stack
    /// values. Generally, this should be avoided - use `StringBuilder` instead.
    pub inline fn addObjects() void {
        return krk_addObjects();
    }

    /// Raise an exception value.
    ///
    /// Implementation of the `OP_RAISE` and `OP_RAISE_FROM` instructions.
    ///
    /// If either of `base` or `cause` is a class, the class will be called to
    /// produce an instance, so exception classes may be used directly if desired.
    ///
    /// If @p cause is not `None` it will be attached as `__cause__` to the
    /// resulting exception object.
    ///
    /// A traceback is automatically attached.
    ///
    /// - `base` Exception object or class to raise.
    /// - `cause` Exception cause object or class to attach.
    pub inline fn raiseException(base: KrkValue, cause: KrkValue) void {
        krk_raiseException(base, cause);
    }

    /// Attach an inner exception to the current exception object.
    ///
    /// Sets the `__context__` of the current exception object.
    ///
    /// There must be a current exception, and it must be an instance object.
    ///
    /// - `innerException` __context__ to set.
    pub inline fn attachInnerException(inner_exception: KrkValue) void {
        krk_attachInnerException(inner_exception);
    }

    /// Get a pointer to the current thread state.
    ///
    /// Generally equivalent to `&krk_currentThread`, though `krk_currentThread`
    /// itself may be implemented as a macro that calls this function depending
    /// on the platform's thread support.
    ///
    /// return: Pointer to current thread's thread state.
    pub inline fn getCurrentThread() *KrkThreadState {
        return krk_getCurrentThread();
    }

    /// Continue VM execution until the next exit trigger.
    ///
    /// Resumes the VM dispatch loop, returning to the caller when
    /// the next exit trigger event happens. Generally, callers will
    /// want to set the current thread's exitOnFrame before calling
    /// `KrkVM.runNext`. Alternatively, see `KrkValue.callValue` which manages
    /// exit triggers automatically when calling function objects.
    ///
    /// return: Value returned by the exit trigger, generally the value
    /// returned by the inner function before the VM returned
    /// to the exit frame.
    pub inline fn runNext() KrkValue {
        return krk_runNext();
    }

    /// Call a callable on the stack with `arg_count` arguments.
    ///
    /// Calls the callable `arg_count` stack entries down from the top
    /// of the stack, passing `arg_count` arguments. Resumes execution
    /// of the VM for managed calls until they are completed. Pops
    /// all arguments and the callable from the stack and returns the
    /// return value of the call.
    ///
    /// - `arg_count` Arguments to collect from the stack.
    ///
    /// return: The return value of the function.
    pub inline fn callStack(arg_count: i32) KrkValue {
        return krk_callStack(arg_count);
    }

    /// If there is an active exception, print a traceback to `stderr`
    ///
    /// This function is exposed as a convenience for repl developers. Normally,
    /// the VM will call `krk_dumpTraceback()` itself if an exception is unhandled and no
    /// exit trigger is current set. The traceback is obtained from the exception
    /// object. If the exception object does not have a traceback, only the
    /// exception itself will be printed. The traceback printer will attempt to
    /// open source files to print faulting lines and may call into the VM if the
    /// exception object has a managed implementation of `__str__`.
    pub inline fn dumpTraceback() void {
        krk_dumpTraceback();
    }

    /// Set up a new module object in the current thread.
    ///
    /// Creates a new instance of the module type and attaches a `__builtins__`
    /// reference to its fields. The module becomes the current thread's
    /// main module, but is not directly attached to the module table.
    ///
    /// - `name` Name of the module, which is assigned to `__name__`.
    ///
    /// return: The instance object representing the module.
    pub inline fn startModule(name: [*:0]const u8) *KrkInstance {
        return krk_startModule(name);
    }

    /// Obtain a list of properties for an object.
    ///
    /// This is the native function bound to `object.__dir__`
    pub inline fn dirObject(argc: i32, argv: [*]const KrkValue, has_kw: bool) KrkValue {
        return krk_dirObject(argc, argv, @intFromBool(has_kw));
    }

    /// Load a module from a file with a specified name.
    ///
    /// This is generally called by the import mechanisms to load a single module and
    /// will establish a module context internally to load the new module into, return
    /// a KrkValue representing that module context.
    ///
    /// - `path` Dotted path of the module, used for file lookup.
    /// - `run_as` Name to attach to `__name__` for this module, different from `path`.
    /// - `parent` Parent module object, if loaded from a package.
    ///
    /// return: KrkValue representing that module context if the module was loaded, null if an `ImportError` occurred.
    pub inline fn loadModule(path: *KrkString, run_as: *KrkString, parent: KrkValue) ?KrkValue {
        var module: KrkValue = undefined;
        if (krk_loadModule(path, &module, run_as, parent) == 1) {
            return module;
        }
        return null;
    }

    ///  Load a module by a dotted name.
    ///
    /// Given a package identifier, attempt to the load module into the module table.
    /// This is a thin wrapper around `KrkVM.importModule()`.
    ///
    /// - `name` String object of the dot-separated package path to import.
    ///
    /// return: true if the module was loaded, false if an `ImportError` occurred.
    pub inline fn doRecursiveModuleLoad(name: *KrkString) bool {
        return krk_doRecursiveModuleLoad(name) == 1;
    }

    /// Load the dotted name `name` with the final element as `run_as`.
    ///
    /// If `name` was imported previously with a name different from `run_as`,
    /// it will be imported again with the new name; this may result in
    /// unexpected behaviour. Generally, `run_as` is used to specify that the
    /// module should be run as `__main__`.
    ///
    /// - `name` Dotted path name of a module.
    /// - `run_as` Alternative name to attach to `__name__` for the module.
    ///
    /// return: true on success, false on failure.
    pub inline fn importModule(name: *KrkString, run_as: *KrkString) bool {
        return krk_importModule(name, run_as) == 1;
    }

    /// Set the maximum recursion call depth.
    ///
    /// Must not be called while execution is in progress.
    pub inline fn setMaximumRecursionDepth(max_depth: usize) void {
        krk_setMaximumRecursionDepth(max_depth);
    }

    /// Call a native function using a reference to stack arguments safely.
    ///
    /// Passing the address of the stack to a native function directly would be unsafe:
    /// the stack can be reallocated at any time through pushes. To allow for native functions
    /// to be called with arguments from the stack safely, this wrapper holds on to a reference
    /// to the stack at the call time, unless one was already held by an outer call; if a
    /// held stack is reallocated, it will be freed when execution returns to the call
    /// to `KrkVM.callNativeOnStack` that holds it.
    pub inline fn callNativeOnStack(arg_count: usize, stack_args: [*]const KrkValue, has_kw: bool, native: KrkNativeFn) KrkValue {
        return krk_callNativeOnStack(arg_count, stack_args, @intFromBool(has_kw), native);
    }

    /// Implementation of the GET_PROPERTY instruction.
    ///
    /// Retrieves the attribute specifed by `name` from the value at the top of the
    /// stack. The top of the stack will be replaced with the resulting attribute value,
    /// if one is found, and true will be returned. Otherwise, false is returned and the stack
    /// remains unchanged. No exception is raised if the property is not found, allowing
    /// this function to be used in context where a default value is desired, but note
    /// that exceptions may be raised `__getattr__` methods or by descriptor `__get__` methods.
    ///
    /// - `name` Name of the attribute to look up.
    ///
    /// return: true if the attribute was found, false otherwise.
    pub inline fn getAttribute(name: *KrkString) bool {
        return krk_getAttribute(name) == 1;
    }

    /// Implementation of the SET_PROPERTY instruction.
    ///
    /// Sets the attribute specifed by `name` on the value second from top of the stack
    /// to the value at the top of the stack. Upon successful completion, true is returned
    /// the stack is reduced by one slot, and the top of the stack is the value set, which
    /// may be the result of a descriptor `__set__` method. If the owner object does not
    /// allow for attributes to be set, and no descriptor object is present, false will be
    /// returned and the stack remains unmodified. No exception is raised in this case,
    /// though exceptions may still be raised by `__setattr__` methods or descriptor
    /// `__set__` methods.
    ///
    /// - `name` Name of the attribute to set.
    ///
    /// return: true if the attribute could be set, false otherwise.
    pub inline fn setAttribute(name: *KrkString) c_int {
        return krk_setAttribute(name) == 1;
    }

    /// Implementation of the DEL_PROPERTY instruction.
    ///
    /// Attempts to delete the attribute specified by `name` from the value at the
    /// top of the stack, returning true and reducing the stack by one on success. If
    /// the attribute is not found or attribute deletion is not meaningful, false is
    /// returned and the stack remains unmodified, but no exception is raised.
    pub inline fn delAttribute(name: *KrkString) c_int {
        return krk_delAttribute(name) == 1;
    }

    /// Initialize the built-in 'kuroko' module.
    pub inline fn moduleInitKuroko() void {
        krk_module_init_kuroko();
    }

    /// Initialize the built-in 'threading' module.
    ///
    /// Not available if KRK_DISABLE_THREADS is set.
    pub inline fn moduleInitThreading() void {
        krk_module_init_threading();
    }

    /// Load all lib modules
    pub inline fn moduleInitLibs() void {
        krk_module_init_libs();
    }
};

// Get libc's stdout
pub extern "c" fn krk_getStdout() *std.c.FILE;

// Get libc's stderr
pub extern "c" fn krk_getStderr() *std.c.FILE;

/// Inline flexible string array.
pub const StringBuilder = extern struct {
    capacity: usize,
    length: usize,
    bytes: [*]u8,

    extern "c" fn krk_pushStringBuilder(sb: *StringBuilder, c: u8) void;
    extern "c" fn krk_pushStringBuilderStr(sb: *StringBuilder, str: [*]const u8, length: usize) void;
    extern "c" fn krk_pushStringBuilderFormat(sb: *StringBuilder, fmt: [*:0]const u8, ...) c_int;
    extern "c" fn krk_finishStringBuilder(sb: *StringBuilder) KrkValue;
    extern "c" fn krk_finishStringBuilderBytes(sb: *StringBuilder) KrkValue;
    extern "c" fn krk_discardStringBuilder(sb: *StringBuilder) void;

    /// Add a character to the end of a string builder.
    pub inline fn push(sb: *StringBuilder, c: u8) void {
        krk_pushStringBuilder(sb, c);
    }

    /// Append a string to the end of a string builder.
    pub inline fn pushString(sb: *StringBuilder, str: []const u8) void {
        krk_pushStringBuilderStr(sb, str.ptr, str.len);
    }

    /// Append a formatted string to the end of a string builder.
    /// return: true on success, false on failure.
    pub fn pushStringFormat(sb: *StringBuilder, fmt: [*:0]const u8, args: anytype) bool {
        return @call(.auto, krk_pushStringBuilderFormat, .{ sb, fmt } ++ args) == 1;
    }

    /// Finalize a string builder into a string object.
    ///
    /// Creates a string object from the contents of the string builder and
    /// frees the space allocated for the builder, returning a value representing
    /// the newly created string object.
    ///
    /// return: A value representing a string object.
    pub inline fn finish(sb: *StringBuilder) KrkValue {
        return krk_finishStringBuilder(sb);
    }

    /// Finalize a string builder in a bytes object.
    ///
    /// Converts the contents of a string builder into a bytes object and
    /// frees the space allocated for the builder.
    ///
    /// return: A value representing a bytes object.
    pub inline fn finishBytes(sb: *StringBuilder) KrkValue {
        return krk_finishStringBuilderBytes(sb);
    }

    /// Discard the contents of a string builder.
    ///
    /// Frees the resources allocated for the string builder without converting
    /// it to a string or bytes object. Call this when an error has been encountered
    /// and the contents of a string builder are no longer needed.
    pub inline fn discard(sb: *StringBuilder) void {
        _ = krk_discardStringBuilder(sb);
    }

    pub inline fn toString(sb: *StringBuilder) []const u8 {
        return sb.bytes[0..sb.length];
    }
};

extern fn krk_parseArgs_impl(
    method_name: [*:0]const u8,
    argc: c_int,
    argv: [*]const KrkValue,
    has_kw: c_int,
    format: [*:0]const u8,
    names: [*]const [*:0]const u8,
    ...,
) c_int;

/// Parse arguments to a function while accepting keyword arguments.
///
/// return: true on success, false on failure with an exception set.
pub fn parseArgs(
    method_name: [*:0]const u8,
    argc: c_int,
    argv: [*]const KrkValue,
    has_kw: c_int,
    format: [*:0]const u8,
    names: [*]const [*:0]const u8,
    values: anytype,
) bool {
    return @call(.auto, krk_parseArgs_impl, .{ method_name, argc, argv, has_kw, format, names } ++ values) == 1;
}

extern fn krk_exec_module(src: [*:0]const u8, module_name: [*:0]const u8) c_int;

/// Compile and execute a source code input as builtin module.
pub fn execModule(src: [*:0]const u8, module_name: [*:0]const u8) bool {
    return krk_exec_module(src, module_name) == 1;
}
