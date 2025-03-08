const std = @import("std");
const testing = std.testing;

const makeHex = @import("utils.zig").makeHex;

pub const Opcode = struct {
    pub const Prefixes = struct {
        pub const es = 0x26;
        pub const cs = 0x2E;
        pub const ss = 0x36;
        pub const ds = 0x3E;
        pub const fs = 0x64;
        pub const gs = 0x65;
        pub const opsz = 0x66;
        pub const adsz = 0x67;
        pub const lock = 0xF0;
        pub const repn = 0xF2;
        pub const rep = 0xF3;
    };

    const Op1No = struct {
        pub const pushes = 0x06;
        pub const popes = 0x07;
        pub const pushcs = 0x0E;
        pub const pushss = 0x16;
        pub const popss = 0x17;
        pub const pushds = 0x1E;
        pub const popds = 0x1F;
        pub const daa = 0x27;
        pub const das = 0x2F;
        pub const aaa = 0x37;
        pub const aas = 0x3F;
        pub const inceax = 0x40;
        pub const incecx = 0x41;
        pub const incedx = 0x42;
        pub const incebx = 0x43;
        pub const incesp = 0x44;
        pub const incebp = 0x45;
        pub const incesi = 0x46;
        pub const incedi = 0x47;
        pub const deceax = 0x48;
        pub const dececx = 0x49;
        pub const decedx = 0x4A;
        pub const decebx = 0x4B;
        pub const decesp = 0x4C;
        pub const decebp = 0x4D;
        pub const decesi = 0x4E;
        pub const decedi = 0x4F;
        pub const pusheax = 0x50;
        pub const pushecx = 0x51;
        pub const pushedx = 0x52;
        pub const pushebx = 0x53;
        pub const pushesp = 0x54;
        pub const pushebp = 0x55;
        pub const pushesi = 0x56;
        pub const pushedi = 0x57;
        pub const popeax = 0x58;
        pub const popecx = 0x59;
        pub const popedx = 0x5A;
        pub const popebx = 0x5B;
        pub const popesp = 0x5C;
        pub const popebp = 0x5D;
        pub const popesi = 0x5E;
        pub const popedi = 0x5F;
        pub const pusha = 0x60;
        pub const popa = 0x61;
        pub const nop = 0x90;
        pub const xchgecxeax = 0x91;
        pub const xchgedxeax = 0x92;
        pub const xchgebxeax = 0x93;
        pub const xchgespeax = 0x94;
        pub const xchgebpeax = 0x95;
        pub const xchgesieax = 0x96;
        pub const xchgedieax = 0x97;
        pub const cwde = 0x98;
        pub const cdq = 0x99;
        pub const wait = 0x9B;
        pub const pushf = 0x9C;
        pub const popf = 0x9D;
        pub const sahf = 0x9E;
        pub const lahf = 0x9F;
        pub const movs8 = 0xA4;
        pub const movsw = 0xA5;
        pub const cmps8 = 0xA6;
        pub const cmpsw = 0xA7;
        pub const stos8 = 0xAA;
        pub const stosd = 0xAB;
        pub const lods8 = 0xAC;
        pub const lodsd = 0xAD;
        pub const scas8 = 0xAE;
        pub const scasd = 0xAF;
        pub const ret = 0xC3;
        pub const leave = 0xC9;
        pub const retf = 0xCB;
        pub const int3 = 0xCC;
        pub const into = 0xCE;
        pub const xlat = 0xD7;
        pub const cmc = 0xF5;
        pub const clc = 0xF8;
        pub const stc = 0xF9;
        pub const cli = 0xFA;
        pub const sti = 0xFB;
        pub const cld = 0xFC;
        pub const std = 0xFD;
    };
    const Op1I8 = struct {
        pub const addali = 0x04;
        pub const orali = 0x0C;
        pub const adcali = 0x14;
        pub const sbbali = 0x1C;
        pub const andali = 0x24;
        pub const subali = 0x2C;
        pub const xorali = 0x34;
        pub const cmpali = 0x3C;
        pub const pushi8 = 0x6A;
        pub const testali = 0xA8;
        pub const jo = 0x70;
        pub const jno = 0x71;
        pub const jb = 0x72;
        pub const jnb = 0x73;
        pub const jz = 0x74;
        pub const jnz = 0x75;
        pub const jna = 0x76;
        pub const ja = 0x77;
        pub const js = 0x78;
        pub const jns = 0x79;
        pub const jp = 0x7A;
        pub const jnp = 0x7B;
        pub const jl = 0x7C;
        pub const jnl = 0x7D;
        pub const jng = 0x7E;
        pub const jg = 0x7F;
        pub const movali = 0xB0;
        pub const movcli = 0xB1;
        pub const movdli = 0xB2;
        pub const movbli = 0xB3;
        pub const movahi = 0xB4;
        pub const movchi = 0xB5;
        pub const movdhi = 0xB6;
        pub const movbhi = 0xB7;
        pub const int = 0xCD;
        pub const amx = 0xD4;
        pub const adx = 0xD5;
        pub const loopnz = 0xE0;
        pub const loopz = 0xE1;
        pub const loop = 0xE2;
        pub const jcxz = 0xE3;
        pub const jmpi8 = 0xEB;
    };
    const Op1IW = struct {
        pub const addeaxi = 0x05;
        pub const oreaxi = 0x0D;
        pub const adceaxi = 0x15;
        pub const sbbeaxi = 0x1D;
        pub const andeaxi = 0x25;
        pub const subeaxi = 0x2D;
        pub const xoreaxi = 0x35;
        pub const cmpeaxi = 0x3D;
        pub const pushiw = 0x68;
        pub const testeaxi = 0xA9;
        pub const moveaxi = 0xB8;
        pub const movecxi = 0xB9;
        pub const movedxi = 0xBA;
        pub const movebxi = 0xBB;
        pub const movespi = 0xBC;
        pub const movebpi = 0xBD;
        pub const movesii = 0xBE;
        pub const movedii = 0xBF;
        pub const call = 0xE8;
        pub const jmpiw = 0xE9;
    };
    const Op1IWI = struct {
        pub const movalii = 0xA0;
        pub const moveaxii = 0xA1;
        pub const moviial = 0xA2;
        pub const moviieax = 0xA3;
    };
    const Op1I16 = struct {
        pub const reti16 = 0xC2;
        pub const retfi16 = 0xCA;
    };
    const Op1Mrm = struct {
        pub const addmr8 = 0x00;
        pub const addmrw = 0x01;
        pub const addrm8 = 0x02;
        pub const addrmw = 0x03;
        pub const ormr8 = 0x08;
        pub const ormrw = 0x09;
        pub const orrm8 = 0x0A;
        pub const orrmw = 0x0B;
        pub const adcmr8 = 0x10;
        pub const adcmrw = 0x11;
        pub const adcrm8 = 0x12;
        pub const adcrmw = 0x13;
        pub const sbbmr8 = 0x18;
        pub const sbbmrw = 0x19;
        pub const sbbrm8 = 0x1A;
        pub const sbbrmw = 0x1B;
        pub const andmr8 = 0x20;
        pub const andmrw = 0x21;
        pub const andrm8 = 0x22;
        pub const andrmw = 0x23;
        pub const submr8 = 0x28;
        pub const submrw = 0x29;
        pub const subrm8 = 0x2A;
        pub const subrmw = 0x2B;
        pub const xormr8 = 0x30;
        pub const xormrw = 0x31;
        pub const xorrm8 = 0x32;
        pub const xorrmw = 0x33;
        pub const cmpmr8 = 0x38;
        pub const cmpmrw = 0x39;
        pub const cmprm8 = 0x3A;
        pub const cmprmw = 0x3B;
        pub const arpl = 0x63;
        pub const testmr8 = 0x84;
        pub const testmrw = 0x85;
        pub const xchgmr8 = 0x86;
        pub const xchgmrw = 0x87;
        pub const movmr8 = 0x88;
        pub const movmrw = 0x89;
        pub const movrm8 = 0x8A;
        pub const movrmw = 0x8B;
        pub const movms = 0x8C;
        pub const lea = 0x8D;
        pub const movsm = 0x8E;
        pub const popm = 0x8F;
        pub const shiftm18 = 0xD0;
        pub const shiftm1w = 0xD1;
        pub const shiftmcl8 = 0xD2;
        pub const shiftmclw = 0xD3;
        pub const fltblk1 = 0xD8;
        pub const fltblk2 = 0xD9;
        pub const fltblk3 = 0xDA;
        pub const fltblk4 = 0xDB;
        pub const fltblk5 = 0xDC;
        pub const fltblk6 = 0xDD;
        pub const fltblk7 = 0xDE;
        pub const fltblk8 = 0xDF;
        pub const miscm8 = 0xFE;
        pub const miscmw = 0xFF;
    };
    const Op1MrmI8 = struct {
        pub const imulmi8 = 0x6B;
        pub const alumi8 = 0x80;
        pub const alumi8x = 0x82;
        pub const alumi8s = 0x83;
        pub const shiftmi8 = 0xC0;
        pub const shiftmiw = 0xC1;
        pub const movmi8 = 0xC6;
    };
    const Op1MrmIW = struct {
        pub const imulmiw = 0x69;
        pub const alumiw = 0x81;
        pub const movmiw = 0xC7;
    };

    pub const Op1 = struct {
        pub usingnamespace Op1No;
        pub usingnamespace Op1I8;
        pub usingnamespace Op1IW;
        pub usingnamespace Op1IWI;
        pub usingnamespace Op1I16;
        pub usingnamespace Op1Mrm;
        pub usingnamespace Op1MrmI8;
        pub usingnamespace Op1MrmIW;

        const enter = 0xC8;
        const crazy8 = 0xF6;
        const crazyw = 0xF7;
    };

    const Op2No = struct {
        pub const rdtsc = 0x31;
        pub const rdpmd = 0x33;
        pub const sysenter = 0x34;
        pub const pushfs = 0xA0;
        pub const popfs = 0xA1;
        pub const cpuid = 0xA2;
        pub const pushgs = 0xA8;
        pub const popgs = 0xA9;
        pub const rsm = 0xAA;
        pub const bswapeax = 0xC8;
        pub const bswapecx = 0xC9;
        pub const bswapedx = 0xCA;
        pub const bswapebx = 0xCB;
        pub const bswapesp = 0xCC;
        pub const bswapebp = 0xCD;
        pub const bswapesi = 0xCE;
        pub const bswapedi = 0xCF;
        pub const emms = 0x77;
    };
    const Op2IW = struct {
        pub const joii = 0x80;
        pub const jnoii = 0x81;
        pub const jbii = 0x82;
        pub const jnbii = 0x83;
        pub const jzii = 0x84;
        pub const jnzii = 0x85;
        pub const jnaii = 0x86;
        pub const jaii = 0x87;
        pub const jsii = 0x88;
        pub const jnsii = 0x89;
        pub const jpii = 0x8A;
        pub const jnpii = 0x8B;
        pub const jlii = 0x8C;
        pub const jnlii = 0x8D;
        pub const jngii = 0x8E;
        pub const jgii = 0x8F;
    };
    const Op2Mrm = struct {
        pub const nop = 0x0D;
        pub const hints1 = 0x18;
        pub const hints2 = 0x19;
        pub const hints3 = 0x1A;
        pub const hints4 = 0x1B;
        pub const hints5 = 0x1C;
        pub const hints6 = 0x1D;
        pub const hints7 = 0x1E;
        pub const hints8 = 0x1F;
        pub const cmovo = 0x40;
        pub const cmovno = 0x41;
        pub const cmovb = 0x42;
        pub const cmovnb = 0x43;
        pub const cmovz = 0x44;
        pub const cmovnz = 0x45;
        pub const cmovna = 0x46;
        pub const cmova = 0x47;
        pub const cmovs = 0x48;
        pub const cmovns = 0x49;
        pub const cmovp = 0x4A;
        pub const cmovnp = 0x4B;
        pub const cmovl = 0x4C;
        pub const cmovnl = 0x4D;
        pub const cmovng = 0x4E;
        pub const cmovg = 0x4F;
        pub const seto = 0x90;
        pub const setno = 0x91;
        pub const setb = 0x92;
        pub const setnb = 0x93;
        pub const setz = 0x94;
        pub const setnz = 0x95;
        pub const setna = 0x96;
        pub const seta = 0x97;
        pub const sets = 0x98;
        pub const setns = 0x99;
        pub const setp = 0x9A;
        pub const setnp = 0x9B;
        pub const setl = 0x9C;
        pub const setnl = 0x9D;
        pub const setng = 0x9E;
        pub const setg = 0x9F;
        pub const btmr = 0xA3;
        pub const shldmrcl = 0xA5;
        pub const bts = 0xAB;
        pub const shrdmrcl = 0xAD;
        pub const misc = 0xAE;
        pub const imul = 0xAF;
        pub const cmpxchg8 = 0xB0;
        pub const cmpxchgw = 0xB1;
        pub const movzx8 = 0xB6;
        pub const movzxw = 0xB7;
        pub const popcnt = 0xB8;
        pub const btcrm = 0xBB;
        pub const bsf = 0xBC;
        pub const bsr = 0xBD;
        pub const movsx8 = 0xBE;
        pub const movsxw = 0xBF;
        pub const xaddrm8 = 0xC0;
        pub const xaddrmw = 0xC1;
        pub const cmpxchg64 = 0xC7;
        pub const movrm128 = 0x10;
        pub const movmr128 = 0x11;
        pub const movlrm = 0x12;
        pub const movlmr = 0x13;
        pub const unpckl = 0x14;
        pub const unpckh = 0x15;
        pub const movhrm = 0x16;
        pub const movhmr = 0x17;
        pub const movarm = 0x28;
        pub const movamr = 0x29;
        pub const cvtif64 = 0x2A;
        pub const movnt = 0x2B;
        pub const cvtft64 = 0x2C;
        pub const cvtfi64 = 0x2D;
        pub const ucomi = 0x2E;
        pub const comi = 0x2F;
        pub const movmsk = 0x50;
        pub const sqrt = 0x51;
        pub const rsqrt = 0x52;
        pub const rcp = 0x53;
        pub const and_ = 0x54;
        pub const andn = 0x55;
        pub const or_ = 0x56;
        pub const xor = 0x57;
        pub const add = 0x58;
        pub const mul = 0x59;
        pub const cvtff128 = 0x5A;
        pub const cvtfi128 = 0x5B;
        pub const sub = 0x5C;
        pub const div = 0x5D;
        pub const min = 0x5E;
        pub const max = 0x5F;
        pub const punpcklbw = 0x60;
        pub const punpcklbd = 0x61;
        pub const punpckldq = 0x62;
        pub const packsswb = 0x63;
        pub const pcmpgtb = 0x64;
        pub const pcmpgtw = 0x65;
        pub const pcmpgtd = 0x66;
        pub const packuswb = 0x67;
        pub const punpckhbw = 0x68;
        pub const punpckhwd = 0x69;
        pub const punpckhdq = 0x6A;
        pub const packssdw = 0x6B;
        pub const punpcklqdq = 0x6C;
        pub const punpckhqdq = 0x6D;
        pub const movdrm = 0x6E;
        pub const movqrm = 0x6F;
        pub const pcmpeqb = 0x74;
        pub const pcmpeqw = 0x75;
        pub const pcmpeqd = 0x76;
        pub const movdmr = 0x7E;
        pub const movqmr = 0x7F;
        pub const movnti = 0xC3;
        pub const addsub = 0xD0;
        pub const psrlw = 0xD1;
        pub const psrld = 0xD2;
        pub const psrlq = 0xD3;
        pub const paddq = 0xD4;
        pub const pmullw = 0xD5;
        pub const movqrr = 0xD6;
        pub const pmovmskb = 0xD7;
        pub const psubusb = 0xD8;
        pub const psubusw = 0xD9;
        pub const pminub = 0xDA;
        pub const pand = 0xDB;
        pub const paddusb = 0xDC;
        pub const paddusw = 0xDD;
        pub const pmaxub = 0xDE;
        pub const pandn = 0xDF;
        pub const pavgb = 0xE0;
        pub const psraw = 0xE1;
        pub const psrad = 0xE2;
        pub const pavgw = 0xE3;
        pub const pmulhuw = 0xE4;
        pub const pmulhw = 0xE5;
        pub const cvtq = 0xE6;
        pub const movntq = 0xE7;
        pub const psubsb = 0xE8;
        pub const psubsw = 0xE9;
        pub const pminsb = 0xEA;
        pub const pminsw = 0xEB;
        pub const paddsb = 0xEC;
        pub const paddsw = 0xED;
        pub const pmaxsw = 0xEE;
        pub const pxor = 0xEF;
        pub const lddqu = 0xF0;
        pub const psllw = 0xF1;
        pub const pslld = 0xF2;
        pub const psllq = 0xF3;
        pub const pmuludq = 0xF4;
        pub const pmaddwd = 0xF5;
        pub const psabdw = 0xF6;
        pub const maskmovq = 0xF7;
        pub const psubb = 0xF8;
        pub const psubw = 0xF9;
        pub const psubd = 0xFA;
        pub const psubq = 0xFB;
        pub const paddb = 0xFC;
        pub const paddw = 0xFD;
        pub const paddd = 0xFE;
    };
    const Op2MrmI8 = struct {
        pub const shldmri = 0xA4;
        pub const shrdmri = 0xAC;
        pub const btxmi = 0xBA;
        pub const pshuf = 0x70;
        pub const pswi = 0x71;
        pub const psdi = 0x72;
        pub const psqi = 0x73;
        pub const cmpsi = 0xC2;
        pub const pinsrw = 0xC4;
        pub const pextrw = 0xC5;
        pub const shuf = 0xC6;
    };

    pub const Op2 = struct {
        pub usingnamespace Op2No;
        pub usingnamespace Op2IW;
        pub usingnamespace Op2Mrm;
        pub usingnamespace Op2MrmI8;
    };

    pub const op2_byte = 0x0F;
    pub const op3_1 = 0x38;
    pub const op3_2 = 0x3A;
    pub const op3dnow = 0x0F;
};

// Constructs a ModRM byte
pub fn modrm(mod: u8, reg: u8, rm: u8) u8 {
    return mod << 6 | reg << 3 | rm;
}

fn mrmsib(b: [*]const u8, address_len: usize) usize {
    if (address_len == 4 or b[0] & 0xC0 != 0) {
        const sib: usize = if (address_len == 4 and b[0] < 0xC0 and (b[0] & 7) == 4) 1 else 0;
        if ((b[0] & 0xC0) == 0x40) {
            return 2 + sib;
        }
        if ((b[0] & 0xC0) == 0x00) {
            if ((b[0] & 7) != 5) {
                if (sib == 1 and (b[1] & 7) == 5) {
                    return if (b[0] & 0x40 != 0) 3 else 6;
                }
                return 1 + sib;
            }
            return 1 + address_len + sib;
        }
        if ((b[0] & 0xC0) == 0x80) {
            return 1 + address_len + sib;
        }
    }
    if (address_len == 2 and (b[0] & 0xC7) == 0x06) {
        return 3;
    }
    return 1;
}

fn is_field(comptime T: type, byte: u8) bool {
    @setEvalBranchQuota(100000);
    for (@typeInfo(T).@"struct".decls) |decl| {
        const decl_ptr = &@field(T, decl.name);
        if (decl_ptr.* == byte) {
            return true;
        }
    }
    return false;
}

pub fn x86_len(address: [*]const u8) !usize {
    var b = address;

    var prefix_len: usize = 0;
    var operand_len: usize = 4;
    var address_len: usize = 4;

    // prefixes
    while (prefix_len < 14 and switch (b[0]) {
        inline 0x00...0xFF => |byte| blk: {
            break :blk comptime is_field(Opcode.Prefixes, byte);
        },
    }) : ({
        prefix_len += 1;
        b += 1;
    }) {
        if (b[0] == Opcode.Prefixes.opsz) {
            operand_len = 2;
        } else if (b[0] == Opcode.Prefixes.adsz) {
            address_len = 2;
        }
    }

    // opcode
    return switch (b[0]) {
        Opcode.op2_byte => switch (b[1]) {
            Opcode.op3_1,
            Opcode.op3_2,
            Opcode.op3dnow,
            => error.UnsupportedInstruction,
            inline else => |byte| blk: {
                if (comptime is_field(Opcode.Op2No, byte)) {
                    break :blk prefix_len + 2;
                }
                if (comptime is_field(Opcode.Op2IW, byte)) {
                    break :blk prefix_len + 2 + operand_len;
                }
                if (comptime is_field(Opcode.Op2Mrm, byte)) {
                    break :blk prefix_len + 2 + mrmsib(b + 2, address_len);
                }
                if (comptime is_field(Opcode.Op2MrmI8, byte)) {
                    operand_len = 1;
                    break :blk prefix_len + 2 + operand_len + mrmsib(b + 2, address_len);
                }
                break :blk error.UnsupportedInstruction;
            },
        },
        inline else => |byte| blk: {
            if (comptime is_field(Opcode.Op1No, byte)) {
                break :blk prefix_len + 1;
            }
            if (comptime is_field(Opcode.Op1I8, byte)) {
                operand_len = 1;
                break :blk prefix_len + 1 + operand_len;
            }
            if (comptime is_field(Opcode.Op1IW, byte)) {
                break :blk prefix_len + 1 + operand_len;
            }
            if (comptime is_field(Opcode.Op1IWI, byte)) {
                break :blk prefix_len + 1 + address_len;
            }
            if (comptime is_field(Opcode.Op1I16, byte)) {
                break :blk prefix_len + 3;
            }
            if (comptime is_field(Opcode.Op1Mrm, byte)) {
                break :blk prefix_len + 1 + mrmsib(b + 1, address_len);
            }
            if (comptime is_field(Opcode.Op1MrmI8, byte)) {
                operand_len = 1;
                break :blk prefix_len + 1 + operand_len + mrmsib(b + 1, address_len);
            }
            if (comptime is_field(Opcode.Op1MrmIW, byte)) {
                break :blk prefix_len + 1 + operand_len + mrmsib(b + 1, address_len);
            }
            if (byte == Opcode.Op1.enter) {
                break :blk prefix_len + 4;
            }
            if (byte == Opcode.Op1.crazy8 or byte == Opcode.Op1.crazyw) {
                if (byte == Opcode.Op1.crazy8) {
                    operand_len = 1;
                }

                if ((b[1] & 0x38) >= 0x10) {
                    operand_len = 0;
                }

                break :blk prefix_len + 1 + operand_len + mrmsib(b + 1, address_len);
            }
            break :blk error.UnsupportedInstruction;
        },
    };
}

test "Simple x86 instruction lengths" {
    const nop = makeHex("90");
    try testing.expectEqual(1, try x86_len(nop.ptr));
    const push_eax = makeHex("50");
    try testing.expectEqual(1, try x86_len(push_eax.ptr));
    const mov_eax = makeHex("B8 78 56 34 12");
    try testing.expectEqual(5, try x86_len(mov_eax.ptr));
    const add_mem_eax = makeHex("00 00");
    try testing.expectEqual(2, try x86_len(add_mem_eax.ptr));
    const mov_ax = makeHex("66 B8 34 12");
    try testing.expectEqual(4, try x86_len(mov_ax.ptr));
    const add_mem_disp32 = makeHex("00 80 78 56 34 12");
    try testing.expectEqual(6, try x86_len(add_mem_disp32.ptr));
    const add_eax_imm = makeHex("05 78 56 34 12");
    try testing.expectEqual(5, try x86_len(add_eax_imm.ptr));
}

test "The \"crazy\" instructions should be given correct lengths" {
    const test8 = makeHex("F6 05 12 34 56 78 12");
    try testing.expectEqual(7, try x86_len(test8.ptr));
    const test16 = makeHex("66 F7 05 12 34 56 78 12");
    try testing.expectEqual(9, try x86_len(test16.ptr));
    const test32 = makeHex("F7 05 12 34 56 78 12 34 56 78");
    try testing.expectEqual(10, try x86_len(test32.ptr));
    const not8 = makeHex("F6 15 12 34 56 78");
    try testing.expectEqual(6, try x86_len(not8.ptr));
    const not16 = makeHex("66 F7 15 12 34 56 78");
    try testing.expectEqual(7, try x86_len(not16.ptr));
    const not32 = makeHex("F7 15 12 34 56 78");
    try testing.expectEqual(6, try x86_len(not32.ptr));
}

test "SIB bytes should be decoded correctly" {
    const fstp = makeHex("D9 1C 24");
    try testing.expectEqual(3, try x86_len(fstp.ptr));
}

test "mov AL, moff8 instructions should be decoded correctly" {
    const mov_moff8_al = makeHex("A2 DA 78 B4 0D");
    try testing.expectEqual(5, try x86_len(mov_moff8_al.ptr));
    const mov_al_moff8 = makeHex("A0 28 DF 5C 66");
    try testing.expectEqual(5, try x86_len(mov_al_moff8.ptr));
}

test "16-bit MRM instructions should be decoded correctly" {
    const fiadd_off16 = makeHex("67 DA 06 DF 11");
    try testing.expectEqual(5, try x86_len(fiadd_off16.ptr));
    const fld_tword = makeHex("67 DB 2E 99 C4");
    try testing.expectEqual(5, try x86_len(fld_tword.ptr));
    const add_off16_bl = makeHex("67 00 1E F5 BB");
    try testing.expectEqual(5, try x86_len(add_off16_bl.ptr));
}
