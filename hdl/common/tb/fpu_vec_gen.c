/* ===========================================================================
 * fpu_vec_gen.c  (X4 Zfinx, Stage 2a)  -- self-checking reference generator
 * ===========================================================================
 * Emits reference vectors for fpu_tb.vhd.  Reference method (gatekeeper
 * correction C4): x86 SSE single-precision (compile -msse2 -mfpmath=sse,
 * x87 FORBIDDEN) with fesetround / fetestexcept for correct rounding + IEEE
 * exception flags, and glibc fmaf for the fused multiply-add family.
 *
 * The four IEEE rounding modes (RNE/RTZ/RDN/RUP) come straight from hardware
 * SSE (correctly rounded, exact flags).  RMM (round-to-nearest ties-away) is
 * NOT an fesetround mode; for FADD/FSUB/FMUL its reference is computed with an
 * exact-double ties-away rounding (single op results are exact in double), and
 * for FDIV/FSQRT/FMA its reference is the RNE result (identical to RMM except
 * on exact ties, which are covered by DIRECTED tie vectors for the shared
 * round back-end).  All NaN results are canonicalized to 0x7FC00000.
 *
 * Line format (single-space separated, fixed width):
 *   K OO R AAAAAAAA BBBBBBBB CCCCCCCC RRRRRRRR FF
 *   K  = kind: 0 multi-cycle fpu, 1 combinational fpu_simple
 *   OO = op code (2-digit decimal)
 *   R  = rounding mode 0..4 (RNE RTZ RDN RUP RMM); ignored by fpu_simple
 *   A/B/C/RRRRRRRR = 8-hex operands + expected result
 *   FF = expected flags {NV,DZ,OF,UF,NX} as 2 hex (bit4..bit0)
 *
 * multi op codes : 0 FADD 1 FSUB 2 FMUL 3 FDIV 4 FSQRT 5 FMADD 6 FMSUB
 *                  7 FNMSUB 8 FNMADD 9 FCVT_W_S 10 FCVT_WU_S 11 FCVT_S_W 12 FCVT_S_WU
 * simple op codes: 0 FSGNJ 1 FSGNJN 2 FSGNJX 3 FEQ 4 FLT 5 FLE 6 FMIN 7 FMAX 8 FCLASS
 * ===========================================================================*/
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <math.h>
#include <fenv.h>
#pragma STDC FENV_ACCESS ON

/* op codes */
enum { FADD,FSUB,FMUL,FDIV,FSQRT,FMADD,FMSUB,FNMSUB,FNMADD,
       FCVT_W_S,FCVT_WU_S,FCVT_S_W,FCVT_S_WU };
enum { SGNJ,SGNJN,SGNJX,FEQ,FLT,FLE,FMIN,FMAX,FCLASS };

static FILE *out;
static long counts[64];

static float b2f(uint32_t b){ float f; memcpy(&f,&b,4); return f; }
static uint32_t f2b(float f){ uint32_t b; memcpy(&b,&f,4); return b; }

/* flags: bit4 NV, bit3 DZ, bit2 OF, bit1 UF, bit0 NX */
static int map_flags(int exc){
    int f=0;
    if(exc&FE_INVALID)   f|=0x10;
    if(exc&FE_DIVBYZERO) f|=0x08;
    if(exc&FE_OVERFLOW)  f|=0x04;
    if(exc&FE_UNDERFLOW) f|=0x02;
    if(exc&FE_INEXACT)   f|=0x01;
    return f;
}
static int set_rm(int rm){
    switch(rm){
        case 0: return fesetround(FE_TONEAREST);
        case 1: return fesetround(FE_TOWARDZERO);
        case 2: return fesetround(FE_DOWNWARD);
        case 3: return fesetround(FE_UPWARD);
        case 4: return fesetround(FE_TONEAREST); /* RMM handled specially */
        default:return fesetround(FE_TONEAREST);
    }
}
static void emit(int kind,int op,int rm,uint32_t a,uint32_t b,uint32_t c,
                 uint32_t res,int flags){
    fprintf(out,"%d %02d %d %08X %08X %08X %08X %02X\n",
            kind,op,rm,a,b,c,res,flags&0xFF);
    counts[op&63]++;
}

/* exact-double ties-away rounding to single, for FADD/FSUB/FMUL (their exact
 * math result is representable in double). Returns bits, sets *nx. */
static uint32_t round_ties_away_d2f(double e,int *nx){
    int save=fegetround();
    fesetround(FE_TOWARDZERO);
    float t=(float)e;                 /* toward-zero neighbor */
    fesetround(save);
    double dt=(double)t;
    if(e==dt){ *nx=0; return f2b(t); }
    *nx=1;
    float away = nextafterf(t, (t>=0)? (float)INFINITY : -(float)INFINITY);
    double da=(double)away;
    double dmid=(dt+da)/2.0;
    float r;
    if(e>0){
        if(e> dmid) r=away; else if(e<dmid) r=t; else r=away; /* tie -> away */
    }else{
        if(e< dmid) r=away; else if(e>dmid) r=t; else r=away; /* tie -> away */
    }
    /* overflow to inf keeps inexact set; underflow handled by nx */
    return f2b(r);
}

/* RISC-V after-rounding underflow: UF iff the ROUNDED result is subnormal or
 * zero AND inexact. x86 flags tininess before rounding, so recompute UF from
 * the result exponent field (matches the spec + RTL). */
static int fix_uf(uint32_t res,int flags){
    int nx=flags&0x01, expf=(res>>23)&0xFF;
    flags &= ~0x02;
    if(nx && expf==0) flags|=0x02;
    return flags;
}

/* one multi-cycle arithmetic vector (FADD..FNMADD) */
static void emit_arith(int op,int rm,uint32_t a,uint32_t b,uint32_t c){
    volatile float fa=b2f(a), fb=b2f(b), fc=b2f(c), fr=0.0f;
    uint32_t res; int flags;

    /* primary result+flags: hardware SSE. RMM uses the RNE hardware op as its
     * base (RMM==RNE except on exact ties, fixed up below). */
    set_rm((rm==4)?0:rm);
    feclearexcept(FE_ALL_EXCEPT);
    switch(op){
        case FADD:   fr=fa+fb; break;
        case FSUB:   fr=fa-fb; break;
        case FMUL:   fr=fa*fb; break;
        case FDIV:   fr=fa/fb; break;
        case FSQRT:  fr=sqrtf(fa); break;
        case FMADD:  fr=fmaf(fa,fb,fc); break;
        case FMSUB:  fr=fmaf(fa,fb,-fc); break;
        case FNMSUB: fr=fmaf(-fa,fb,fc); break;
        case FNMADD: fr=fmaf(-fa,fb,-fc); break;
    }
    int exc=fetestexcept(FE_ALL_EXCEPT);
    fesetround(FE_TONEAREST);
    res=f2b(fr);
    if(isnan(fr)) res=0x7FC00000;
    flags=map_flags(exc);

    /* RISC-V/Spike raise NV for a 0*inf product inside an FMA even when the
     * addend is a NaN; x86 fmaf suppresses it (NaN-priority). Force it here. */
    if(op>=FMADD && op<=FNMADD){
        if((fa==0.0f && isinf(fb)) || (isinf(fa) && fb==0.0f)){
            res=0x7FC00000; flags |= 0x10;
        }
    }

    /* RMM tie fix-up (all ops). The exact single-precision tie value is always
     * representable in double, so a double recompute detects it; on a tie RMM
     * rounds AWAY from zero (RNE rounds to even). */
    if(rm==4 && !isnan(fr) && !isinf(fr)){
        double da=(double)fa, db=(double)fb, dc=(double)fc, e=0.0;
        switch(op){
            case FADD:   e=da+db; break;
            case FSUB:   e=da-db; break;
            case FMUL:   e=da*db; break;
            case FDIV:   e=da/db; break;
            case FSQRT:  e=sqrt(da); break;
            case FMADD:  e=da*db+dc; break;
            case FMSUB:  e=da*db-dc; break;
            case FNMSUB: e=-da*db+dc; break;
            case FNMADD: e=-da*db-dc; break;
        }
        if(!isnan(e) && !isinf(e)){
            int save=fegetround(); fesetround(FE_TOWARDZERO);
            float tz=(float)e; fesetround(save);
            if((double)tz != e){
                float away=nextafterf(tz,(e>=0)?(float)INFINITY:-(float)INFINITY);
                double mid=((double)tz+(double)away)/2.0;
                if(e==mid){                 /* EXACT tie -> round away */
                    res=f2b(away);
                    flags &= ~0x04;
                    if(isinf(away)) flags|=0x04;   /* overflow */
                }
            }
        }
    }

    flags = fix_uf(res,flags);
    emit(0,op,rm,a,b,c,res,flags);
}

/* float -> int conversions with the RISC-V invalid table */
static void emit_f2i(int op,int rm,uint32_t a){
    int is_signed = (op==FCVT_W_S);
    float fa=b2f(a);
    uint32_t res; int flags=0;
    if(isnan(fa)){
        res = is_signed?0x7FFFFFFF:0xFFFFFFFF; flags=0x10; /* NV */
        emit(0,op,rm,a,0,0,res,flags); return;
    }
    if(isinf(fa)){
        if(fa>0) res = is_signed?0x7FFFFFFF:0xFFFFFFFF;
        else     res = is_signed?0x80000000u:0x00000000u;
        flags=0x10; emit(0,op,rm,a,0,0,res,flags); return;
    }
    float rf;
    int inexact;
    if(rm==4){
        /* RMM = round to nearest, ties away = C roundf() */
        rf = roundf(fa);
        inexact = (rf != fa) ? 1 : 0;
    }else{
        set_rm(rm); feclearexcept(FE_ALL_EXCEPT);
        rf = rintf(fa);                 /* round to integer per mode */
        inexact = fetestexcept(FE_INEXACT)?1:0;
        fesetround(FE_TONEAREST);
    }
    double rd=(double)rf;
    if(is_signed){
        if(rd > 2147483647.0){ res=0x7FFFFFFF; flags=0x10; }
        else if(rd < -2147483648.0){ res=0x80000000u; flags=0x10; }
        else { res=(uint32_t)(int32_t)rd; flags= inexact?0x01:0x00; }
    }else{
        if(rd > 4294967295.0){ res=0xFFFFFFFF; flags=0x10; }
        else if(rd < 0.0){ res=0x00000000u; flags=0x10; }
        else { res=(uint32_t)(uint64_t)rd; flags= inexact?0x01:0x00; }
    }
    emit(0,op,rm,a,0,0,res,flags);
}

/* int -> float conversions */
static void emit_i2f(int op,int rm,uint32_t a){
    int is_signed = (op==FCVT_S_W);
    set_rm(rm); feclearexcept(FE_ALL_EXCEPT);
    volatile float fr;
    if(is_signed) fr=(float)(int32_t)a; else fr=(float)(uint32_t)a;
    int exc=fetestexcept(FE_ALL_EXCEPT);
    fesetround(FE_TONEAREST);
    /* RMM: for int->float a tie is possible when |a| has >24 significant bits;
     * for those the RNE reference differs from RMM only on exact ties. Correct
     * via exact ties-away since integers are exact in double. */
    uint32_t res;
    if(rm==4){
        double e = is_signed?(double)(int32_t)a:(double)(uint32_t)a;
        int nx=0; res=round_ties_away_d2f(e,&nx);
        int flags = nx?0x01:0x00;
        emit(0,op,rm,a,0,0,res,flags); return;
    }
    res=f2b(fr);
    emit(0,op,rm,a,0,0,res,map_flags(exc));
}

/* combinational fpu_simple reference (matches RTL semantics) */
static int is_snan(uint32_t x){ uint32_t e=(x>>23)&0xFF,m=x&0x7FFFFF; return e==0xFF&&m!=0&&((x>>22)&1)==0; }
static int is_nan_b(uint32_t x){ uint32_t e=(x>>23)&0xFF,m=x&0x7FFFFF; return e==0xFF&&m!=0; }
static int is_inf_b(uint32_t x){ uint32_t e=(x>>23)&0xFF,m=x&0x7FFFFF; return e==0xFF&&m==0; }
static int is_zero_b(uint32_t x){ return (x&0x7FFFFFFF)==0; }
static int is_sub_b(uint32_t x){ uint32_t e=(x>>23)&0xFF,m=x&0x7FFFFF; return e==0&&m!=0; }

/* ordered less-than for non-NaN */
static int flt_lt(uint32_t a,uint32_t b){
    int sa=a>>31,sb=b>>31; uint32_t ma=a&0x7FFFFFFF,mb=b&0x7FFFFFFF;
    int bothz = is_zero_b(a)&&is_zero_b(b);
    if(sa&&!sb) return !bothz;
    if(!sa&&sb) return 0;
    if(!sa&&!sb) return ma<mb;
    return ma>mb;
}
static void emit_simple(int op,uint32_t a,uint32_t b){
    uint32_t res=0; int flags=0;
    int an=is_nan_b(a), bn=is_nan_b(b), as=is_snan(a), bs=is_snan(b);
    int bothz=is_zero_b(a)&&is_zero_b(b);
    int numeq = (a==b)||bothz;
    switch(op){
        case SGNJ:  res=(b&0x80000000u)|(a&0x7FFFFFFF); break;
        case SGNJN: res=((~b)&0x80000000u)|(a&0x7FFFFFFF); break;
        case SGNJX: res=((a^b)&0x80000000u)|(a&0x7FFFFFFF); break;
        case FEQ:
            if(an||bn){ res=0; if(as||bs) flags=0x10; }
            else res=numeq?1:0;
            break;
        case FLT:
            if(an||bn){ res=0; flags=0x10; }
            else res=flt_lt(a,b)?1:0;
            break;
        case FLE:
            if(an||bn){ res=0; flags=0x10; }
            else res=(flt_lt(a,b)||numeq)?1:0;
            break;
        case FMIN:
            if(an&&bn){ res=0x7FC00000; if(as||bs) flags=0x10; }
            else if(an){ res=b; if(as) flags=0x10; }
            else if(bn){ res=a; if(bs) flags=0x10; }
            else if(bothz&&((a>>31)!=(b>>31))) res=0x80000000u;
            else res=flt_lt(a,b)?a:b;
            break;
        case FMAX:
            if(an&&bn){ res=0x7FC00000; if(as||bs) flags=0x10; }
            else if(an){ res=b; if(as) flags=0x10; }
            else if(bn){ res=a; if(bs) flags=0x10; }
            else if(bothz&&((a>>31)!=(b>>31))) res=0x00000000u;
            else res=flt_lt(a,b)?b:a;
            break;
        case FCLASS:{
            int sa=a>>31; uint32_t cls=0;
            int inf=is_inf_b(a),zero=is_zero_b(a),sub=is_sub_b(a),nan=is_nan_b(a),sn=is_snan(a);
            int norm = !inf&&!zero&&!sub&&!nan;
            if(inf&&sa) cls|=1<<0;
            if(norm&&sa) cls|=1<<1;
            if(sub&&sa) cls|=1<<2;
            if(zero&&sa) cls|=1<<3;
            if(zero&&!sa) cls|=1<<4;
            if(sub&&!sa) cls|=1<<5;
            if(norm&&!sa) cls|=1<<6;
            if(inf&&!sa) cls|=1<<7;
            if(sn) cls|=1<<8;
            if(nan&&!sn) cls|=1<<9;
            res=cls; break; }
    }
    emit(1,op,0,a,b,0,res,flags);
}

/* ---- random helpers ---- */
static uint64_t rng=0x123456789abcdef0ULL;
static uint32_t rnd(){ rng^=rng<<13; rng^=rng>>7; rng^=rng<<17; return (uint32_t)(rng>>16); }
/* biased random float: mix of full-random and "interesting exponent" values */
static uint32_t rnd_f(){
    uint32_t r=rnd();
    int mode=r&7;
    uint32_t sign=(rnd()&1)<<31;
    uint32_t man = rnd()&0x7FFFFF;
    uint32_t e;
    switch(mode){
        case 0: e = rnd()%256; break;                 /* any incl inf/nan/sub */
        case 1: e = 1+rnd()%254; break;               /* normal */
        case 2: e = 0; break;                          /* subnormal/zero */
        case 3: e = 126+ (rnd()%4); break;            /* near 1.0 */
        case 4: e = 253+(rnd()%2); break;             /* huge (overflow prone) */
        case 5: e = 1+rnd()%20; break;                /* tiny (underflow prone) */
        case 6: return rnd();                          /* fully random 32-bit */
        default:e = 100+rnd()%40; break;
    }
    return sign|(e<<23)|man;
}

int main(int argc,char**argv){
    const char*path = (argc>1)?argv[1]:"fpu_vectors.txt";
    out=fopen(path,"w");
    if(!out){ perror("fopen"); return 1; }

    /* interesting single-precision constants */
    uint32_t K[]= {
        0x00000000,0x80000000,            /* +0 -0 */
        0x3F800000,0xBF800000,            /* +1 -1 */
        0x40000000,0xC0000000,            /* +2 -2 */
        0x3F000000,0x3FC00000,            /* 0.5 1.5 */
        0x7F800000,0xFF800000,            /* +inf -inf */
        0x7FC00000,0x7FBFFFFF,            /* qnan snan(0x7FBFFFFF? -> e=FF m!=0 bit22=0 =>snan) */
        0x7F800001,0xFF800001,            /* snan +/- */
        0x00000001,0x80000001,            /* smallest +/- subnormal */
        0x007FFFFF,0x807FFFFF,            /* largest subnormal +/- */
        0x00800000,0x80800000,            /* smallest normal +/- */
        0x7F7FFFFF,0xFF7FFFFF,            /* largest normal +/- FLT_MAX */
        0x34000000,0x33800000,            /* 2^-23 2^-24 (half-ulp of 1.0) */
        0x4B000000,0x4B7FFFFF,            /* 2^23, ~2^24 (int boundary) */
        0x4F000000,0x4F800000,            /* 2^31, 2^32 */
        0xCF000000,0x4EFFFFFF,            /* -2^31, near 2^31 */
        0x3FFFFFFF,0x3F800001,            /* just below/above 1.0 tie region */
        0x00000002,0x00000003             /* tiny subnormals */
    };
    int NK=sizeof(K)/sizeof(K[0]);
    /* curated subset for the non-RNE modes (bounds the cross-product volume) */
    uint32_t KS[]={0x00000000,0x80000000,0x3F800000,0xBF800000,0x40000000,
                   0x7F800000,0xFF800000,0x7FC00000,0x7F800001,0x00000001,
                   0x007FFFFF,0x00800000,0x7F7FFFFF,0x3F800001,0x4B000000,0x40490FDB};
    int NKS=sizeof(KS)/sizeof(KS[0]);

    /* ---- directed: FMA family. Full NK*NK at RNE; subset KS*KS at other modes ---- */
    for(int op=FADD;op<=FNMADD;op++)
      for(int rm=0;rm<5;rm++){
        if(rm==0){
            for(int i=0;i<NK;i++)for(int j=0;j<NK;j++){
                uint32_t c=(op>=FMADD)?K[(i+j)%NK]:0; emit_arith(op,rm,K[i],K[j],c);
            }
        }else{
            for(int i=0;i<NKS;i++)for(int j=0;j<NKS;j++){
                uint32_t c=(op>=FMADD)?KS[(i+j)%NKS]:0; emit_arith(op,rm,KS[i],KS[j],c);
            }
        }
      }

    /* ---- directed RMM ties on the shared round back-end (FADD, FMUL) ---- */
    /* tie = X + 0.5ulp(X); build via a=X, b=half-ulp(X) for a range of X */
    {
        uint32_t bases[]={0x3F800000,0x40000000,0x40400000,0x41200000,
                          0x3F800001,0x40000001,0x4B000000,0x00800000,
                          0xBF800000,0xC0000000};
        for(int i=0;i<10;i++){
            uint32_t X=bases[i];
            int e=(X>>23)&0xFF;
            if(e<2||e>250) continue;
            uint32_t halfulp = (uint32_t)(e-24)<<23; /* 2^(e-127-24) */
            for(int rm=0;rm<5;rm++){
                emit_arith(FADD,rm,X,halfulp,0);
                emit_arith(FADD,rm,X|0x80000000u,halfulp|0x80000000u,0);
            }
        }
    }

    /* ---- random FMA family ---- */
    for(int op=FADD;op<=FNMADD;op++)
      for(int rm=0;rm<5;rm++)
        for(int n=0;n<110;n++){
            uint32_t a=rnd_f(),b=rnd_f(),c=(op>=FMADD)?rnd_f():0;
            emit_arith(op,rm,a,b,c);
        }

    /* ---- FDIV / FSQRT directed + random (div/sqrt are the slow ops) ---- */
    for(int rm=0;rm<5;rm++){
        for(int i=0;i<NKS;i++)for(int j=0;j<NKS;j++) emit_arith(FDIV,rm,KS[i],KS[j],0);
        for(int i=0;i<NK;i++) emit_arith(FSQRT,rm,K[i],0,0);
        for(int n=0;n<130;n++){ emit_arith(FDIV,rm,rnd_f(),rnd_f(),0); }
        for(int n=0;n<160;n++){ uint32_t a=rnd_f()&0x7FFFFFFF; emit_arith(FSQRT,rm,a,0,0);}    /* positive */
        for(int n=0;n<24;n++){ emit_arith(FSQRT,rm,rnd_f()|0x80000000u,0,0);}                  /* negative -> NV */
    }

    /* ---- FCVT ---- */
    for(int rm=0;rm<5;rm++){
        for(int i=0;i<NK;i++){ emit_f2i(FCVT_W_S,rm,K[i]); emit_f2i(FCVT_WU_S,rm,K[i]); }
        for(int i=0;i<NK;i++){ emit_i2f(FCVT_S_W,rm,K[i]); emit_i2f(FCVT_S_WU,rm,K[i]); }
        uint32_t iv[]={0,1,0x7FFFFFFF,0x80000000u,0xFFFFFFFFu,0x00FFFFFF,0x01000000,
                       0x01000001,0x7F000000,0xFF000000,123456789u,0xDEADBEEFu,2147483647u};
        int NV=sizeof(iv)/sizeof(iv[0]);
        for(int i=0;i<NV;i++){ emit_i2f(FCVT_S_W,rm,iv[i]); emit_i2f(FCVT_S_WU,rm,iv[i]); }
        for(int n=0;n<150;n++){ uint32_t a=rnd_f(); emit_f2i(FCVT_W_S,rm,a); emit_f2i(FCVT_WU_S,rm,a); }
        for(int n=0;n<150;n++){ uint32_t a=rnd(); emit_i2f(FCVT_S_W,rm,a); emit_i2f(FCVT_S_WU,rm,a); }
    }

    /* ---- fpu_simple: directed + random (combinational, cheap) ---- */
    for(int op=SGNJ;op<=FCLASS;op++){
        for(int i=0;i<NK;i++)for(int j=0;j<NK;j++) emit_simple(op,K[i],K[j]);
        for(int n=0;n<120;n++) emit_simple(op,rnd_f(),rnd_f());
    }

    fclose(out);
    long total=0; for(int i=0;i<64;i++) total+=counts[i];
    fprintf(stderr,"fpu_vec_gen: wrote %ld vectors to %s\n",total,path);
    fprintf(stderr,"  per-op counts (multi 0..12, simple share codes 0..8):\n");
    const char*nm[]={"FADD/SGNJ","FSUB/SGNJN","FMUL/SGNJX","FDIV/FEQ","FSQRT/FLT",
                     "FMADD/FLE","FMSUB/FMIN","FNMSUB/FMAX","FNMADD/FCLASS",
                     "FCVT_W_S","FCVT_WU_S","FCVT_S_W","FCVT_S_WU"};
    for(int i=0;i<13;i++) fprintf(stderr,"    [%2d] %-14s %ld\n",i,nm[i],counts[i]);
    return 0;
}
