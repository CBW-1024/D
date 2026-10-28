// iPadSpoof - 独立 iPad 四层伪装（型号/名字/model/hw.machine）
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <dlfcn.h>

typedef void *id; typedef void *SEL; typedef void *Class; typedef void *IMP; typedef void *Method;
typedef signed char BOOL;
#define YES 1
#define NO 0

extern Class objc_getClass(const char *);
extern SEL sel_registerName(const char *);
extern Method class_getInstanceMethod(Class, SEL);
extern IMP method_getImplementation(Method);
extern IMP method_setImplementation(Method, IMP);
extern void *objc_msgSend(void *, SEL, ...);
extern int sysctlbyname(const char *, void *, size_t *, void *, size_t);
extern int usleep(unsigned int);
extern int pthread_create(void**,void*,void*(*)(void*),void*);

static const char *kMachines[] = {
    "iPad5,1",
    "iPad5,2",
    "iPad6,3",
    "iPad6,4",
    "iPad6,7",
    "iPad6,8",
    "iPad6,11",
    "iPad6,12",
    "iPad7,1",
    "iPad7,2",
    "iPad7,3",
    "iPad7,4",
    "iPad7,5",
    "iPad7,6",
    "iPad7,11",
    "iPad7,12",
    "iPad8,1",
    "iPad8,2",
    "iPad8,3",
    "iPad8,4",
    "iPad8,5",
    "iPad8,6",
    "iPad8,7",
    "iPad8,8",
    "iPad11,1",
    "iPad11,2",
    "iPad11,3",
    "iPad11,4",
    "iPad12,1",
    "iPad12,2",
    "iPad13,4",
    "iPad13,5",
    "iPad13,6",
    "iPad13,7",
    "iPad13,8",
    "iPad13,9",
    "iPad13,10",
    "iPad13,11",
    "iPad14,1",
    "iPad14,2",
    "iPad13,16",
    "iPad13,17",
    "iPad13,18",
    "iPad13,19",
    "iPad14,3",
    "iPad14,4",
    "iPad14,5",
    "iPad14,6",
    "iPad16,3",
    "iPad16,4",
    "iPad16,5",
    "iPad16,6"
};
static const int kMachinesCount = (int)(sizeof(kMachines)/sizeof(kMachines[0]));
static const char *kModels[] = {
    "J96AP",
    "J97AP",
    "J127AP",
    "J128AP",
    "J98aAP",
    "J99aAP",
    "J71sAP",
    "J72sAP",
    "J120AP",
    "J121AP",
    "J207AP",
    "J208AP",
    "J71bAP",
    "J72bAP",
    "J171AP",
    "J172AP",
    "J317AP",
    "J317xAP",
    "J318AP",
    "J318xAP",
    "J320AP",
    "J320xAP",
    "J321AP",
    "J321xAP",
    "J210AP",
    "J211AP",
    "J217AP",
    "J218AP",
    "J181AP",
    "J182AP",
    "J517AP",
    "J517xAP",
    "J518AP",
    "J518xAP",
    "J522AP",
    "J522xAP",
    "J523AP",
    "J523xAP",
    "J310AP",
    "J311AP",
    "J407AP",
    "J408AP",
    "J271AP",
    "J272AP",
    "J617AP",
    "J618AP",
    "J620AP",
    "J621AP",
    "J717AP",
    "J718AP",
    "J720AP",
    "J721AP"
};
static const int kModelsCount = (int)(sizeof(kModels)/sizeof(kModels[0]));
static const int kMinIos[] = {9,9,9,9,9,9,10,10,10,10,10,10,11,11,13,13,12,12,12,12,12,12,12,12,12,12,12,12,15,15,14,14,14,14,14,14,14,14,15,15,15,15,16,16,16,16,16,16,17,17,17,17};

static const char *kNames[] = {
    "iPad",
    "iPad Pro",
    "iPad Air",
    "iPad mini",
    "我的iPad",
    "工作iPad",
    "家里iPad",
    "客厅iPad",
    "卧室iPad",
    "公司iPad",
    "备用iPad",
    "测试iPad",
    "小号iPad",
    "大号iPad",
    "出差iPad",
    "随身iPad",
    "iPad (2)",
    "iPad (3)",
    "iPad (4)",
    "iPad-工作",
    "iPad-家用",
    "iPad 2023",
    "iPad 2024",
    "iPad Pro (11-inch)",
    "iPad Pro (12.9-inch)",
    "iPad Air (5th generation)",
    "iPad mini (6th generation)",
    "iCloud 的 iPad",
    "直播 iPad",
    "客服 iPad",
    "运营 iPad",
    "测试机 iPad",
    "备用机 iPad",
    "小号 iPad",
    "张三的iPad",
    "李四的iPad",
    "王五的iPad",
    "iPadmini",
    "iPadAir",
    "iPadPro",
    "老王的iPad",
    "公司的iPad",
    "家里的iPad",
    "书房的iPad",
    "车上的iPad",
    "孩子的iPad",
    "老婆的iPad",
    "工作用iPad",
    "娱乐iPad",
    "看剧iPad",
    "网课iPad",
    "会议iPad",
    "前台iPad",
    "展厅iPad",
    "门店iPad",
    "仓库iPad",
    "财务iPad",
    "客服2号iPad",
    "测试2号iPad",
    "备用2号iPad",
    "iPad 1",
    "iPad 2",
    "iPad 3",
    "iPad 4",
    "iPad 5",
    "iPad 6",
    "iPad 7",
    "iPad 8",
    "iPad 9",
    "iPad 10",
    "iPad 11",
    "iPad 12",
    "iPad 13",
    "iPad 14",
    "iPad 15",
    "iPad 16",
    "iPad 17",
    "iPad 18",
    "iPad 19",
    "iPad 20",
    "iPad 21",
    "iPad 22",
    "iPad 23",
    "iPad 24",
    "iPad 25"
};
static const int kNameCount = (int)(sizeof(kNames)/sizeof(kNames[0]));

static int g_idx = -1;
static char g_name[32];
static int g_name_done = 0;
static IMP o_model=0,o_lmodel=0,o_name=0,o_dev=0;

static void cfg(char *out,int n,const char *f){ const char *h=getenv("HOME"); if(!h){out[0]=0;return;} snprintf(out,n,"%s/Documents/%s",h,f); }
static void rd(const char *f,char *b,int n){ char p[600]; cfg(p,sizeof(p),f); b[0]=0; FILE *fp=fopen(p,"r"); if(!fp)return; if(!fgets(b,n,fp))b[0]=0; fclose(fp); size_t l=strlen(b); while(l&&(b[l-1]=='\n'||b[l-1]=='\r'))b[--l]=0; }
static void wr(const char *f,const char *v){ char p[600]; cfg(p,sizeof(p),f); FILE *fp=fopen(p,"w"); if(fp){fprintf(fp,"%s\n",v);fclose(fp);} }
static void logl(const char *m){ char p[600]; cfg(p,sizeof(p),"ipadspoof.log"); if(!p[0])return; FILE *fp=fopen(p,"a"); if(fp){fprintf(fp,"%s\n",m);fclose(fp);} }

static int ios_major(void){ char v[32]; size_t n=sizeof(v); if(sysctlbyname("kern.osproductversion",v,&n,0,0)==0) return atoi(v); return 15; }
static int min_idx(void){ int m=ios_major(); if(m>=26)return 46; if(m>=18)return 36; if(m==17)return 28; if(m==16)return 22; return 20; }
static int max_idx(void){ int m=ios_major(); if(m>=17)return 89; if(m==16)return 83; return 68; }
static int pick_idx(void){
    if(g_idx>=0) return g_idx;
    char b[16]; rd("ddhw_model.txt",b,sizeof(b)); int i=atoi(b);
    int m=ios_major();
    if(i<0||i>=kMachinesCount||kMinIos[i]>m){
        int cand[128]; int n=0;
        for(int k=0;k<kMachinesCount;k++) if(kMinIos[k]<=m) cand[n++]=k;
        if(n==0){ g_idx=0; return 0; }
        unsigned int seed=(unsigned int)(unsigned long)&seed^(unsigned int)time(0);
        seed=seed*1103515245u+12345u;
        i=cand[(seed>>16)%n];
        char nb[16]; snprintf(nb,sizeof(nb),"%d",i); wr("ddhw_model.txt",nb);
    }
    g_idx=i; return g_idx;
}
static const char *pick_name(void){
    if(g_name_done) return g_name;
    rd("ddhw_name.txt", g_name, sizeof(g_name));
    if(strlen(g_name)<2){ unsigned int s=(unsigned int)(unsigned long)&s^(unsigned int)time(0); s=s*1103515245u+12345u; snprintf(g_name,sizeof(g_name),"%s",kNames[(s>>16)%kNameCount]); wr("ddhw_name.txt",g_name); }
    g_name_done=1; return g_name;
}
static id nsstr(const char *s){ return ((id(*)(id,SEL,const char*))objc_msgSend)((id)objc_getClass("NSString"),sel_registerName("stringWithUTF8String:"),s); }
static const char *utf8(id s){ if(!s)return ""; const char *u=((const char*(*)(id,SEL))objc_msgSend)(s,sel_registerName("UTF8String")); return u?u:""; }

static id h_model(id s,SEL c){ (void)s;(void)c; return nsstr("iPad"); }
static id h_lmodel(id s,SEL c){ (void)s;(void)c; return nsstr("iPad"); }
static id h_name(id s,SEL c){ (void)s;(void)c; return nsstr(pick_name()); }
static void h_dev(id s,SEL c,id v){ (void)v; ((void(*)(id,SEL,id))o_dev)(s,c,nsstr(pick_name())); }

// ---- hw.machine：按 DDHW 同思路，解析 __LINKEDIT bind 表重绑 sysctl/sysctlbyname ----
typedef const char *(*Fname)(unsigned int); typedef const void *(*Fhdr)(unsigned int); typedef long (*Fslide)(unsigned int);
typedef int (*Fprot)(unsigned int,unsigned long long,unsigned long long,int,int);
static Fname f_name=0; static Fhdr f_hdr=0; static Fslide f_slide=0; static Fprot f_prot=0; static unsigned int *p_task=0;
static int (*real_sysctlbyname)(const char*,void*,size_t*,void*,size_t)=0;
static int (*real_sysctl)(int*,unsigned int,void*,size_t*,void*,size_t)=0;

static const char *spoof_val(const char *name){
    int i=pick_idx();
    if(!name) return 0;
    if(!strcmp(name,"hw.machine")||!strcmp(name,"hw.product")) return kMachines[i%kMachinesCount];
    if(!strcmp(name,"hw.model")) return kModels[i%kModelsCount];
    return 0;
}
static int fill(const char *v,void *oldp,size_t *oldlenp){
    size_t need=strlen(v)+1;
    if(oldp&&oldlenp){ if(*oldlenp<need){*oldlenp=need;return -1;} memcpy(oldp,v,need); *oldlenp=need; return 0; }
    if(oldlenp)*oldlenp=need;
    return 0;
}
static int fake_sysctlbyname(const char *name,void *oldp,size_t *oldlenp,void *newp,size_t newlen){
    const char *v=spoof_val(name);
    if(v) return fill(v,oldp,oldlenp);
    if(!real_sysctlbyname) real_sysctlbyname=(int(*)(const char*,void*,size_t*,void*,size_t))dlsym((void*)-2,"sysctlbyname");
    if(!real_sysctlbyname) return -1;
    return real_sysctlbyname(name,oldp,oldlenp,newp,newlen);
}
static int fake_sysctl(int *name,unsigned int namelen,void *oldp,size_t *oldlenp,void *newp,size_t newlen){
    // CTL_HW=6, HW_MACHINE=1, HW_MODEL=2, HW_MACHINE_ARCH=11
    if(name && namelen>=2 && name[0]==6){
        const char *k=0;
        if(name[1]==1) k="hw.machine"; else if(name[1]==2) k="hw.model"; else if(name[1]==11) k="hw.machine";
        if(k){ const char *v=spoof_val(k); if(v) return fill(v,oldp,oldlenp); }
    }
    if(!real_sysctl) real_sysctl=(int(*)(int*,unsigned int,void*,size_t*,void*,size_t))dlsym((void*)-2,"sysctl");
    if(!real_sysctl) return -1;
    return real_sysctl(name,namelen,oldp,oldlenp,newp,newlen);
}

struct mh64s{unsigned int magic,cputype,cpusubtype,filetype,ncmds,sizeofcmds,flags,reserved;};
struct lcs{unsigned int cmd,cmdsize;};
struct segs{unsigned long long vmaddr,vmsize,fileoff,filesize;};
static int patch_slot(void *addr,const char *sym){
    if(!sym) return 0;
    void *repl=0;
    if(!strcmp(sym,"sysctlbyname")) repl=(void*)fake_sysctlbyname;
    else if(!strcmp(sym,"sysctl")) repl=(void*)fake_sysctl;
    if(!repl) return 0;
    unsigned long long pg=(unsigned long long)addr & ~0x3fffULL;
    if(f_prot(*p_task,pg,0x4000,0,1|2|0x10)) return 0;
    *(void**)addr=repl;
    f_prot(*p_task,pg,0x4000,0,1|0x10);
    return 1;
}
static unsigned int rd_uleb(const unsigned char **pp){ unsigned int r=0; int b; do{ b=*(*pp)++; r=(r<<7)|(b&0x7f);}while(b&0x80); return r; }
static int patch_bind_stream(const unsigned char *p,const unsigned char *end,const struct segs *sg,int nseg,long slide){
    char sym[256]; int seg=0; unsigned long long off=0; int cnt=0;
    while(p<end){
        unsigned char b=*p++; int op=b&0xF0, imm=b&0x0F;
        if(op==0x00){ /* DONE */ }
        else if(op==0x10||op==0x30){ }
        else if(op==0x20){ rd_uleb(&p); }
        else if(op==0x40){ int n=0; while(p<end && *p && n<255) sym[n++]=*p++; sym[n]=0; if(p<end)p++; }
        else if(op==0x50||op==0x60){ }
        else if(op==0x70){ seg=imm; off=rd_uleb(&p); }
        else if(op==0x80){ off+=rd_uleb(&p); }
        else if(op==0x90){ if(seg<nseg) cnt+=patch_slot((void*)(sg[seg].vmaddr+slide+off),sym); }
        else if(op==0xA0){ if(seg<nseg) cnt+=patch_slot((void*)(sg[seg].vmaddr+slide+off),sym); off+=rd_uleb(&p); }
        else if(op==0xB0){ if(seg<nseg){ cnt+=patch_slot((void*)(sg[seg].vmaddr+slide+off),sym); off+=imm*8; } }
        else if(op==0xC0){ unsigned int c=rd_uleb(&p), sk=rd_uleb(&p); for(unsigned int i=0;i<c;i++){ if(seg<nseg) cnt+=patch_slot((void*)(sg[seg].vmaddr+slide+off),sym); off+=8+sk; } }
        else break;
    }
    return cnt;
}
static int patch_image(const void *hdr,long slide){
    if(!hdr) return 0; const struct mh64s *mh=(const struct mh64s*)hdr; if(mh->magic!=0xfeedfacf) return 0;
    struct segs sg[64]; int nseg=0; unsigned int bind_off=0,bind_size=0,lazy_off=0,lazy_size=0;
    const char *pos=(const char*)hdr+sizeof(struct mh64s);
    for(unsigned int i=0;i<mh->ncmds;i++){
        const struct lcs *c=(const struct lcs*)pos; if(c->cmdsize<8) break;
        if(c->cmd==0x19 && nseg<64){ const struct segs *q=(const struct segs*)(pos+24); sg[nseg++]=*q; }
        if(c->cmd==0x80000022){ const unsigned int *q=(const unsigned int*)(pos+8); bind_off=q[2]; bind_size=q[3]; lazy_off=q[6]; lazy_size=q[7]; }
        pos+=c->cmdsize;
    }
    int cnt=0;
    const unsigned char *base=(const unsigned char*)hdr;
    if(bind_off && bind_size) cnt+=patch_bind_stream(base+bind_off, base+bind_off+bind_size, sg, nseg, slide);
    if(lazy_off && lazy_size) cnt+=patch_bind_stream(base+lazy_off, base+lazy_off+lazy_size, sg, nseg, slide);
    return cnt;
}
static void *patch_thread(void *a){
    (void)a;
    for(int k=0;k<6;k++){
        f_name=(Fname)dlsym((void*)-2,"_dyld_get_image_name");
        f_hdr=(Fhdr)dlsym((void*)-2,"_dyld_get_image_header");
        f_slide=(Fslide)dlsym((void*)-2,"_dyld_get_image_vmaddr_slide");
        f_prot=(Fprot)dlsym((void*)-2,"mach_vm_protect");
        p_task=(unsigned int*)dlsym((void*)-2,"mach_task_self_");
        if(f_name&&f_hdr&&f_slide&&f_prot&&p_task) break;
        usleep(1000000);
    }
    if(!(f_name&&f_hdr&&f_slide&&f_prot&&p_task)){ logl("[iPadSpoof] hw_skip"); return 0; }
    int total=0;
    for(unsigned int i=0;i<4096;i++){ const char *nm=f_name(i); if(!nm)continue; if(!strstr(nm,"WeChat.app/WeChat")&&!strstr(nm,"App.framework/App"))continue; total+=patch_image(f_hdr(i),f_slide(i)); }
    char b[128]; snprintf(b,sizeof(b),"[iPadSpoof] hw_patched=%d idx=%d machine=%s",total,pick_idx(),kMachines[pick_idx()%kMachinesCount]); logl(b);
    return 0;
}

static void hook_dev(void){
    Class c=objc_getClass("UIDevice"); if(!c)return;
    Method m;
    m=class_getInstanceMethod(c,sel_registerName("model")); if(m){ if(!o_model)o_model=method_getImplementation(m); method_setImplementation(m,(IMP)h_model); }
    m=class_getInstanceMethod(c,sel_registerName("localizedModel")); if(m){ if(!o_lmodel)o_lmodel=method_getImplementation(m); method_setImplementation(m,(IMP)h_lmodel); }
    m=class_getInstanceMethod(c,sel_registerName("name")); if(m){ if(!o_name)o_name=method_getImplementation(m); method_setImplementation(m,(IMP)h_name); }
    Class a=objc_getClass("ManualAuthAesReqData");
    if(a){ m=class_getInstanceMethod(a,sel_registerName("setDeviceName:")); if(m){ if(!o_dev)o_dev=method_getImplementation(m); method_setImplementation(m,(IMP)h_dev); } }
}
static void *rehook(void *a){ (void)a; for(;;){ usleep(3000000); hook_dev(); } return 0; }

__attribute__((constructor)) static void init(void){
    pick_idx();
    hook_dev();
    void *t=0; pthread_create(&t,0,rehook,0);
    void *t2=0; pthread_create(&t2,0,patch_thread,0);
    char b[128]; snprintf(b,sizeof(b),"[iPadSpoof] loaded idx=%d machine=%s name=%s",pick_idx(),kMachines[pick_idx()%kMachinesCount],pick_name()); logl(b);
}
__attribute__((visibility("default"))) const char *ipadspoof_machine(void){ return kMachines[pick_idx()%kMachinesCount]; }
