const std = @import("std");
const testing = std.testing;

const makeHex = @import("utils.zig").makeHex;

pub const Opcode = struct {
    pub const Prefix = enum(u8) {
        es = 0x26,
        cs = 0x2E,
        ss = 0x36,
        ds = 0x3E,
        fs = 0x64,
        gs = 0x65,
        opsz = 0x66,
        adsz = 0x67,
        lock = 0xF0,
        repn = 0xF2,
        rep = 0xF3,

        _,

        fn is_prefix(o: Prefix) bool {
            return switch (o) {
                _ => false,
                // zig fmt: off
                .es, .cs, .ss, .ds, .fs, .gs,
                .opsz, .adsz, .lock, .repn, .rep,
                => true,
                // zig fmt: on
            };
        }
    };

    pub const Op1 = enum(u8) {
        op2 = 0x0F,
        enter = 0xC8,
        grp3_8 = 0xF6,
        grp3_w = 0xF7,
        // op1_no
        pushes = 0x06,
        popes = 0x07,
        pushcs = 0x0E,
        pushss = 0x16,
        popss = 0x17,
        pushds = 0x1E,
        popds = 0x1F,
        daa = 0x27,
        das = 0x2F,
        aaa = 0x37,
        aas = 0x3F,
        inceax = 0x40,
        incecx = 0x41,
        incedx = 0x42,
        incebx = 0x43,
        incesp = 0x44,
        incebp = 0x45,
        incesi = 0x46,
        incedi = 0x47,
        deceax = 0x48,
        dececx = 0x49,
        decedx = 0x4A,
        decebx = 0x4B,
        decesp = 0x4C,
        decebp = 0x4D,
        decesi = 0x4E,
        decedi = 0x4F,
        pusheax = 0x50,
        pushecx = 0x51,
        pushedx = 0x52,
        pushebx = 0x53,
        pushesp = 0x54,
        pushebp = 0x55,
        pushesi = 0x56,
        pushedi = 0x57,
        popeax = 0x58,
        popecx = 0x59,
        popedx = 0x5A,
        popebx = 0x5B,
        popesp = 0x5C,
        popebp = 0x5D,
        popesi = 0x5E,
        popedi = 0x5F,
        pusha = 0x60,
        popa = 0x61,
        nop = 0x90,
        xchgecxeax = 0x91,
        xchgedxeax = 0x92,
        xchgebxeax = 0x93,
        xchgespeax = 0x94,
        xchgebpeax = 0x95,
        xchgesieax = 0x96,
        xchgedieax = 0x97,
        cwde = 0x98,
        cdq = 0x99,
        wait = 0x9B,
        pushf = 0x9C,
        popf = 0x9D,
        sahf = 0x9E,
        lahf = 0x9F,
        movs8 = 0xA4,
        movsw = 0xA5,
        cmps8 = 0xA6,
        cmpsw = 0xA7,
        stos8 = 0xAA,
        stosd = 0xAB,
        lods8 = 0xAC,
        lodsd = 0xAD,
        scas8 = 0xAE,
        scasd = 0xAF,
        ret = 0xC3,
        leave = 0xC9,
        retf = 0xCB,
        int3 = 0xCC,
        into = 0xCE,
        xlat = 0xD7,
        cmc = 0xF5,
        clc = 0xF8,
        stc = 0xF9,
        cli = 0xFA,
        sti = 0xFB,
        cld = 0xFC,
        std = 0xFD,
        // op1_i8
        addali = 0x04,
        orali = 0x0C,
        adcali = 0x14,
        sbbali = 0x1C,
        andali = 0x24,
        subali = 0x2C,
        xorali = 0x34,
        cmpali = 0x3C,
        pushi8 = 0x6A,
        testali = 0xA8,
        jo = 0x70,
        jno = 0x71,
        jb = 0x72,
        jnb = 0x73,
        jz = 0x74,
        jnz = 0x75,
        jna = 0x76,
        ja = 0x77,
        js = 0x78,
        jns = 0x79,
        jp = 0x7A,
        jnp = 0x7B,
        jl = 0x7C,
        jnl = 0x7D,
        jng = 0x7E,
        jg = 0x7F,
        movali = 0xB0,
        movcli = 0xB1,
        movdli = 0xB2,
        movbli = 0xB3,
        movahi = 0xB4,
        movchi = 0xB5,
        movdhi = 0xB6,
        movbhi = 0xB7,
        int = 0xCD,
        amx = 0xD4,
        adx = 0xD5,
        loopnz = 0xE0,
        loopz = 0xE1,
        loop = 0xE2,
        jcxz = 0xE3,
        jmpi8 = 0xEB,
        // op1_iw
        addeaxi = 0x05,
        oreaxi = 0x0D,
        adceaxi = 0x15,
        sbbeaxi = 0x1D,
        andeaxi = 0x25,
        subeaxi = 0x2D,
        xoreaxi = 0x35,
        cmpeaxi = 0x3D,
        pushiw = 0x68,
        testeaxi = 0xA9,
        moveaxi = 0xB8,
        movecxi = 0xB9,
        movedxi = 0xBA,
        movebxi = 0xBB,
        movespi = 0xBC,
        movebpi = 0xBD,
        movesii = 0xBE,
        movedii = 0xBF,
        call = 0xE8,
        jmpiw = 0xE9,
        // op1_iwi
        movalii = 0xA0,
        moveaxii = 0xA1,
        moviial = 0xA2,
        moviieax = 0xA3,
        // op1_i16
        reti16 = 0xC2,
        retfi16 = 0xCA,
        // op1_mrm
        addmr8 = 0x00,
        addmrw = 0x01,
        addrm8 = 0x02,
        addrmw = 0x03,
        ormr8 = 0x08,
        ormrw = 0x09,
        orrm8 = 0x0A,
        orrmw = 0x0B,
        adcmr8 = 0x10,
        adcmrw = 0x11,
        adcrm8 = 0x12,
        adcrmw = 0x13,
        sbbmr8 = 0x18,
        sbbmrw = 0x19,
        sbbrm8 = 0x1A,
        sbbrmw = 0x1B,
        andmr8 = 0x20,
        andmrw = 0x21,
        andrm8 = 0x22,
        andrmw = 0x23,
        submr8 = 0x28,
        submrw = 0x29,
        subrm8 = 0x2A,
        subrmw = 0x2B,
        xormr8 = 0x30,
        xormrw = 0x31,
        xorrm8 = 0x32,
        xorrmw = 0x33,
        cmpmr8 = 0x38,
        cmpmrw = 0x39,
        cmprm8 = 0x3A,
        cmprmw = 0x3B,
        arpl = 0x63,
        testmr8 = 0x84,
        testmrw = 0x85,
        xchgmr8 = 0x86,
        xchgmrw = 0x87,
        movmr8 = 0x88,
        movmrw = 0x89,
        movrm8 = 0x8A,
        movrmw = 0x8B,
        movms = 0x8C,
        lea = 0x8D,
        movsm = 0x8E,
        popm = 0x8F,
        shiftm18 = 0xD0,
        shiftm1w = 0xD1,
        shiftmcl8 = 0xD2,
        shiftmclw = 0xD3,
        fltblk1 = 0xD8,
        fltblk2 = 0xD9,
        fltblk3 = 0xDA,
        fltblk4 = 0xDB,
        fltblk5 = 0xDC,
        fltblk6 = 0xDD,
        fltblk7 = 0xDE,
        fltblk8 = 0xDF,
        miscm8 = 0xFE,
        miscmw = 0xFF,
        // op1_mrm_i8
        imulmi8 = 0x6B,
        alumi8 = 0x80,
        alumi8x = 0x82,
        alumi8s = 0x83,
        shiftmi8 = 0xC0,
        shiftmiw = 0xC1,
        movmi8 = 0xC6,
        // op1_mrm_iw
        imulmiw = 0x69,
        alumiw = 0x81,
        movmiw = 0xC7,

        _,

        const Classification = enum {
            unknown,
            op2,
            grp3,
            enter,
            op1_no,
            op1_i8,
            op1_iw,
            op1_iwi,
            op1_i16,
            op1_mrm,
            op1_mrm_i8,
            op1_mrm_iw,
        };

        fn classify(o: Op1) Classification {
            return switch (o) {
                _ => .unknown,
                .op2 => .op2,
                .grp3_8, .grp3_w => .grp3,
                .enter => .enter,

                // zig fmt: off
                .pushes, .popes, .pushcs, .pushss,
                .popss, .pushds, .popds, .daa,
                .das, .aaa, .aas, .inceax,
                .incecx, .incedx, .incebx, .incesp,
                .incebp, .incesi, .incedi, .deceax,
                .dececx, .decedx, .decebx, .decesp,
                .decebp, .decesi, .decedi, .pusheax,
                .pushecx, .pushedx, .pushebx, .pushesp,
                .pushebp, .pushesi, .pushedi, .popeax,
                .popecx, .popedx, .popebx, .popesp,
                .popebp, .popesi, .popedi, .pusha,
                .popa, .nop, .xchgecxeax, .xchgedxeax,
                .xchgebxeax, .xchgespeax, .xchgebpeax, .xchgesieax,
                .xchgedieax, .cwde, .cdq, .wait,
                .pushf, .popf, .sahf, .lahf,
                .movs8, .movsw, .cmps8, .cmpsw,
                .stos8, .stosd, .lods8, .lodsd,
                .scas8, .scasd, .ret, .leave,
                .retf, .int3, .into, .xlat,
                .cmc, .clc, .stc, .cli,
                .sti, .cld, .std,
                => .op1_no,

                .addali, .orali, .adcali, .sbbali,
                .andali, .subali, .xorali, .cmpali,
                .pushi8, .testali, .jo, .jno,
                .jb, .jnb, .jz, .jnz,
                .jna, .ja, .js, .jns,
                .jp, .jnp, .jl, .jnl,
                .jng, .jg, .movali, .movcli,
                .movdli, .movbli, .movahi, .movchi,
                .movdhi, .movbhi, .int, .amx,
                .adx, .loopnz, .loopz, .loop,
                .jcxz, .jmpi8,
                => .op1_i8,

                .addeaxi, .oreaxi, .adceaxi, .sbbeaxi,
                .andeaxi, .subeaxi, .xoreaxi, .cmpeaxi,
                .pushiw, .testeaxi, .moveaxi, .movecxi,
                .movedxi, .movebxi, .movespi, .movebpi,
                .movesii, .movedii, .call, .jmpiw,
                => .op1_iw,

                .movalii, .moveaxii, .moviial, .moviieax,
                => .op1_iwi,

                .reti16, .retfi16 => .op1_i16,

                .addmr8, .addmrw, .addrm8, .addrmw,
                .ormr8, .ormrw, .orrm8, .orrmw,
                .adcmr8, .adcmrw, .adcrm8, .adcrmw,
                .sbbmr8, .sbbmrw, .sbbrm8, .sbbrmw,
                .andmr8, .andmrw, .andrm8, .andrmw,
                .submr8, .submrw, .subrm8, .subrmw,
                .xormr8, .xormrw, .xorrm8, .xorrmw,
                .cmpmr8, .cmpmrw, .cmprm8, .cmprmw,
                .arpl, .testmr8, .testmrw, .xchgmr8,
                .xchgmrw, .movmr8, .movmrw, .movrm8,
                .movrmw, .movms, .lea, .movsm,
                .popm, .shiftm18, .shiftm1w, .shiftmcl8,
                .shiftmclw, .fltblk1, .fltblk2, .fltblk3,
                .fltblk4, .fltblk5, .fltblk6, .fltblk7,
                .fltblk8, .miscm8, .miscmw,
                => .op1_mrm,

                .imulmi8, .alumi8, .alumi8x, .alumi8s,
                .shiftmi8, .shiftmiw, .movmi8,
                => .op1_mrm_i8,

                .imulmiw, .alumiw, .movmiw => .op1_mrm_iw,

                // zig fmt: on
            };
        }
    };

    pub const Op2 = enum(u8) {
        // op2_no
        rdtsc = 0x31,
        rdpmd = 0x33,
        sysenter = 0x34,
        pushfs = 0xA0,
        popfs = 0xA1,
        cpuid = 0xA2,
        pushgs = 0xA8,
        popgs = 0xA9,
        rsm = 0xAA,
        bswapeax = 0xC8,
        bswapecx = 0xC9,
        bswapedx = 0xCA,
        bswapebx = 0xCB,
        bswapesp = 0xCC,
        bswapebp = 0xCD,
        bswapesi = 0xCE,
        bswapedi = 0xCF,
        emms = 0x77,
        // op2_iw
        joii = 0x80,
        jnoii = 0x81,
        jbii = 0x82,
        jnbii = 0x83,
        jzii = 0x84,
        jnzii = 0x85,
        jnaii = 0x86,
        jaii = 0x87,
        jsii = 0x88,
        jnsii = 0x89,
        jpii = 0x8A,
        jnpii = 0x8B,
        jlii = 0x8C,
        jnlii = 0x8D,
        jngii = 0x8E,
        jgii = 0x8F,
        // op2_mrm
        nop = 0x0D,
        hints1 = 0x18,
        hints2 = 0x19,
        hints3 = 0x1A,
        hints4 = 0x1B,
        hints5 = 0x1C,
        hints6 = 0x1D,
        hints7 = 0x1E,
        hints8 = 0x1F,
        cmovo = 0x40,
        cmovno = 0x41,
        cmovb = 0x42,
        cmovnb = 0x43,
        cmovz = 0x44,
        cmovnz = 0x45,
        cmovna = 0x46,
        cmova = 0x47,
        cmovs = 0x48,
        cmovns = 0x49,
        cmovp = 0x4A,
        cmovnp = 0x4B,
        cmovl = 0x4C,
        cmovnl = 0x4D,
        cmovng = 0x4E,
        cmovg = 0x4F,
        seto = 0x90,
        setno = 0x91,
        setb = 0x92,
        setnb = 0x93,
        setz = 0x94,
        setnz = 0x95,
        setna = 0x96,
        seta = 0x97,
        sets = 0x98,
        setns = 0x99,
        setp = 0x9A,
        setnp = 0x9B,
        setl = 0x9C,
        setnl = 0x9D,
        setng = 0x9E,
        setg = 0x9F,
        btmr = 0xA3,
        shldmrcl = 0xA5,
        bts = 0xAB,
        shrdmrcl = 0xAD,
        misc = 0xAE,
        imul = 0xAF,
        cmpxchg8 = 0xB0,
        cmpxchgw = 0xB1,
        movzx8 = 0xB6,
        movzxw = 0xB7,
        popcnt = 0xB8,
        btcrm = 0xBB,
        bsf = 0xBC,
        bsr = 0xBD,
        movsx8 = 0xBE,
        movsxw = 0xBF,
        xaddrm8 = 0xC0,
        xaddrmw = 0xC1,
        cmpxchg64 = 0xC7,
        movrm128 = 0x10,
        movmr128 = 0x11,
        movlrm = 0x12,
        movlmr = 0x13,
        unpckl = 0x14,
        unpckh = 0x15,
        movhrm = 0x16,
        movhmr = 0x17,
        movarm = 0x28,
        movamr = 0x29,
        cvtif64 = 0x2A,
        movnt = 0x2B,
        cvtft64 = 0x2C,
        cvtfi64 = 0x2D,
        ucomi = 0x2E,
        comi = 0x2F,
        movmsk = 0x50,
        sqrt = 0x51,
        rsqrt = 0x52,
        rcp = 0x53,
        and_ = 0x54,
        andn = 0x55,
        or_ = 0x56,
        xor = 0x57,
        add = 0x58,
        mul = 0x59,
        cvtff128 = 0x5A,
        cvtfi128 = 0x5B,
        sub = 0x5C,
        div = 0x5D,
        min = 0x5E,
        max = 0x5F,
        punpcklbw = 0x60,
        punpcklbd = 0x61,
        punpckldq = 0x62,
        packsswb = 0x63,
        pcmpgtb = 0x64,
        pcmpgtw = 0x65,
        pcmpgtd = 0x66,
        packuswb = 0x67,
        punpckhbw = 0x68,
        punpckhwd = 0x69,
        punpckhdq = 0x6A,
        packssdw = 0x6B,
        punpcklqdq = 0x6C,
        punpckhqdq = 0x6D,
        movdrm = 0x6E,
        movqrm = 0x6F,
        pcmpeqb = 0x74,
        pcmpeqw = 0x75,
        pcmpeqd = 0x76,
        movdmr = 0x7E,
        movqmr = 0x7F,
        movnti = 0xC3,
        addsub = 0xD0,
        psrlw = 0xD1,
        psrld = 0xD2,
        psrlq = 0xD3,
        paddq = 0xD4,
        pmullw = 0xD5,
        movqrr = 0xD6,
        pmovmskb = 0xD7,
        psubusb = 0xD8,
        psubusw = 0xD9,
        pminub = 0xDA,
        pand = 0xDB,
        paddusb = 0xDC,
        paddusw = 0xDD,
        pmaxub = 0xDE,
        pandn = 0xDF,
        pavgb = 0xE0,
        psraw = 0xE1,
        psrad = 0xE2,
        pavgw = 0xE3,
        pmulhuw = 0xE4,
        pmulhw = 0xE5,
        cvtq = 0xE6,
        movntq = 0xE7,
        psubsb = 0xE8,
        psubsw = 0xE9,
        pminsb = 0xEA,
        pminsw = 0xEB,
        paddsb = 0xEC,
        paddsw = 0xED,
        pmaxsw = 0xEE,
        pxor = 0xEF,
        lddqu = 0xF0,
        psllw = 0xF1,
        pslld = 0xF2,
        psllq = 0xF3,
        pmuludq = 0xF4,
        pmaddwd = 0xF5,
        psabdw = 0xF6,
        maskmovq = 0xF7,
        psubb = 0xF8,
        psubw = 0xF9,
        psubd = 0xFA,
        psubq = 0xFB,
        paddb = 0xFC,
        paddw = 0xFD,
        paddd = 0xFE,
        // op2_mrm_i8
        shldmri = 0xA4,
        shrdmri = 0xAC,
        btxmi = 0xBA,
        pshuf = 0x70,
        pswi = 0x71,
        psdi = 0x72,
        psqi = 0x73,
        cmpsi = 0xC2,
        pinsrw = 0xC4,
        pextrw = 0xC5,
        shuf = 0xC6,
        // op3 (unsupported)
        op3_1 = 0x38,
        op3_2 = 0x3A,
        op3dnow = 0x0F,

        _,

        const Classification = enum {
            unknown,
            op2_no,
            op2_iw,
            op2_mrm,
            op2_mrm_i8,
            op3,
        };

        fn classify(o: Op2) Classification {
            return switch (o) {
                _ => .unknown,

                // zig fmt: off
                .rdtsc, .rdpmd, .sysenter, .pushfs,
                .popfs, .cpuid, .pushgs, .popgs,
                .rsm, .bswapeax, .bswapecx, .bswapedx,
                .bswapebx, .bswapesp, .bswapebp, .bswapesi,
                .bswapedi, .emms,
                => .op2_no,

                .joii, .jnoii, .jbii, .jnbii,
                .jzii, .jnzii, .jnaii, .jaii,
                .jsii, .jnsii, .jpii, .jnpii,
                .jlii, .jnlii, .jngii, .jgii,
                => .op2_iw,

                .nop, .hints1, .hints2, .hints3,
                .hints4, .hints5, .hints6, .hints7,
                .hints8, .cmovo, .cmovno, .cmovb,
                .cmovnb, .cmovz, .cmovnz, .cmovna,
                .cmova, .cmovs, .cmovns, .cmovp,
                .cmovnp, .cmovl, .cmovnl, .cmovng,
                .cmovg, .seto, .setno, .setb,
                .setnb, .setz, .setnz, .setna,
                .seta, .sets, .setns, .setp,
                .setnp, .setl, .setnl, .setng,
                .setg, .btmr, .shldmrcl, .bts,
                .shrdmrcl, .misc, .imul, .cmpxchg8,
                .cmpxchgw, .movzx8, .movzxw, .popcnt,
                .btcrm, .bsf, .bsr, .movsx8,
                .movsxw, .xaddrm8, .xaddrmw, .cmpxchg64,
                .movrm128, .movmr128, .movlrm, .movlmr,
                .unpckl, .unpckh, .movhrm, .movhmr,
                .movarm, .movamr, .cvtif64, .movnt,
                .cvtft64, .cvtfi64, .ucomi, .comi,
                .movmsk, .sqrt, .rsqrt, .rcp,
                .and_, .andn, .or_, .xor,
                .add, .mul, .cvtff128, .cvtfi128,
                .sub, .div, .min, .max,
                .punpcklbw, .punpcklbd, .punpckldq, .packsswb,
                .pcmpgtb, .pcmpgtw, .pcmpgtd, .packuswb,
                .punpckhbw, .punpckhwd, .punpckhdq, .packssdw,
                .punpcklqdq, .punpckhqdq, .movdrm, .movqrm,
                .pcmpeqb, .pcmpeqw, .pcmpeqd, .movdmr,
                .movqmr, .movnti, .addsub, .psrlw,
                .psrld, .psrlq, .paddq, .pmullw,
                .movqrr, .pmovmskb, .psubusb, .psubusw,
                .pminub, .pand, .paddusb, .paddusw,
                .pmaxub, .pandn, .pavgb, .psraw,
                .psrad, .pavgw, .pmulhuw, .pmulhw,
                .cvtq, .movntq, .psubsb, .psubsw,
                .pminsb, .pminsw, .paddsb, .paddsw,
                .pmaxsw, .pxor, .lddqu, .psllw,
                .pslld, .psllq, .pmuludq, .pmaddwd,
                .psabdw, .maskmovq, .psubb, .psubw,
                .psubd, .psubq, .paddb, .paddw,
                .paddd,
                => .op2_mrm,

                .shldmri, .shrdmri, .btxmi, .pshuf,
                .pswi, .psdi, .psqi, .cmpsi,
                .pinsrw, .pextrw, .shuf,
                => .op2_mrm_i8,

                .op3_1, .op3_2, .op3dnow => .op3,
                // zig fmt: on
            };
        }
    };
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

pub fn x86_len(inst: [*]const u8) error{UnsupportedInstruction}!usize {
    var off: usize = 0;

    var operand_len: usize = 4;
    var address_len: usize = 4;

    // Offset past prefix bytes
    while (off < 14) {
        const o: Opcode.Prefix = @enumFromInt(inst[off]);
        if (!o.is_prefix()) break;
        switch (o) {
            .opsz => operand_len = 2,
            .adsz => address_len = 2,
            else => {},
        }
        off += 1;
    }

    const op1: Opcode.Op1 = @enumFromInt(inst[off]);
    return switch (op1.classify()) {
        .unknown => return error.UnsupportedInstruction,
        .op2 => {
            const op2: Opcode.Op2 = @enumFromInt(inst[off + 1]);
            return switch (op2.classify()) {
                .op3, .unknown => return error.UnsupportedInstruction,
                .op2_no => off + 2,
                .op2_iw => off + 2 + operand_len,
                .op2_mrm => off + 2 + mrmsib(inst[off + 2 ..], address_len),
                .op2_mrm_i8 => off + 3 + mrmsib(inst[off + 2 ..], address_len),
            };
        },
        .grp3 => {
            if (op1 == .grp3_8) operand_len = 1;
            if ((inst[off + 1] & 0x38) >= 0x10) operand_len = 0;
            return off + 1 + operand_len + mrmsib(inst[off + 1 ..], address_len);
        },
        .enter => off + 4,
        .op1_no => off + 1,
        .op1_i8 => off + 2,
        .op1_iw => off + 1 + operand_len,
        .op1_iwi => off + 1 + address_len,
        .op1_i16 => off + 3,
        .op1_mrm => off + 1 + mrmsib(inst[off + 1 ..], address_len),
        .op1_mrm_i8 => off + 2 + mrmsib(inst[off + 1 ..], address_len),
        .op1_mrm_iw => off + 1 + operand_len + mrmsib(inst[off + 1 ..], address_len),
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
