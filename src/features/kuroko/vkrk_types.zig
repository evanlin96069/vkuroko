const std = @import("std");
const sdk = @import("sdk");

const vkrk = @import("kuroko.zig");

const game_detection = @import("../../utils/game_detection.zig");
const entlist = @import("../entlist.zig");
const playerio = @import("../playerio.zig");

const kuroko = @import("kuroko");
const VM = kuroko.KrkVM;
const KrkValue = kuroko.KrkValue;
const KrkString = kuroko.KrkString;
const KrkInstance = kuroko.KrkInstance;
const KrkClass = kuroko.KrkClass;
const KrkList = kuroko.KrkList;

fn getFloat(value: KrkValue) ?f32 {
    if (!value.isFloat()) {
        const ty = value.getType();
        VM.push(value);
        if (!ty.bindMethodOnStack(KrkString.copyString("__float__"))) {
            VM.pop();
            return null;
        }
        const result: f32 = @floatCast(VM.callStack(0).asFloat());
        VM.resetStack();
        return result;
    } else {
        return @floatCast(value.asFloat());
    }
}

pub const Vector = struct {
    var class: *KrkClass = undefined;

    pub fn create(vec: sdk.Vector) KrkValue {
        const inst = KrkInstance.create(class);
        VM.push(inst.asValue());
        inst.fields.attachNamedValue("x", KrkValue.floatValue(vec.x));
        inst.fields.attachNamedValue("y", KrkValue.floatValue(vec.y));
        inst.fields.attachNamedValue("z", KrkValue.floatValue(vec.z));
        return VM.pop();
    }
};

pub const QAngle = struct {
    var class: *KrkClass = undefined;

    pub fn create(ang: sdk.QAngle) KrkValue {
        const inst = KrkInstance.create(class);
        VM.push(inst.asValue());
        inst.fields.attachNamedValue("x", KrkValue.floatValue(ang.x));
        inst.fields.attachNamedValue("y", KrkValue.floatValue(ang.y));
        inst.fields.attachNamedValue("z", KrkValue.floatValue(ang.z));
        return VM.pop();
    }
};

pub const VMatrix = struct {
    var class: *KrkClass = undefined;

    pub fn create(mat: *const sdk.VMatrix) KrkValue {
        const inst = KrkInstance.create(class);
        VM.push(inst.asValue());

        const list = KrkList.listOf(0, null, false);
        VM.push(list);
        var i: u32 = 0;
        while (i < 4) : (i += 1) {
            var j: u32 = 0;
            while (j < 4) : (j += 1) {
                list.asList().append(KrkValue.floatValue(mat.m[i][j]));
            }
        }
        _ = VM.pop();
        inst.fields.attachNamedValue("data", list);
        return VM.pop();
    }
};

pub fn bindAttributes(module: *KrkInstance) void {
    _ = VM.interpret(@embedFile("scripts/types.krk"), vkrk.module_name);

    Vector.class = module.fields.get(KrkString.copyString("Vector").asValue()).?.asClass();
    QAngle.class = module.fields.get(KrkString.copyString("QAngle").asValue()).?.asClass();
    VMatrix.class = module.fields.get(KrkString.copyString("VMatrix").asValue()).?.asClass();
}
