// NMSensors - CPU temperature of AMD Zen processors for VirtualSMC (read-only monitoring, no power management).
//
// Tctl comes from the SMU's THM_TCON_CUR_TMP register (SMN 0x00059800), read through the root complex's SMN index/data
// pair at PCI config 0x60/0x64 - the same register Linux k10temp and SMCAMDProcessor read. Unlike AMDRyzenCPUPowerManagement
// this touches no MSR, registers no CPU power-management callbacks and looks up no private kernel symbols: it only answers
// the CPU temperature keys when an application reads them. Integer arithmetic only (no floating point in the kernel).
#include <IOKit/IOService.h>
#include <IOKit/IOLib.h>
#include <IOKit/pci/IOPCIDevice.h>
#include <libkern/OSByteOrder.h>
#include <VirtualSMCSDK/kern_vsmcapi.hpp>

#include <mach/kmod.h>

#define NMLOG(fmt, ...) IOLog("NMSensors: " fmt "\n", ##__VA_ARGS__)

// the module descriptor every kext needs (Xcode generates it; this build declares it, as NVRMFB does)
extern "C" kern_return_t _start(kmod_info_t *ki, void *d); extern "C" kern_return_t _stop(kmod_info_t *ki, void *d);
extern "C" { KMOD_EXPLICIT_DECL(local.nmsensors.NMSensors, "1.0.0", _start, _stop) }
extern "C" kern_return_t _start(kmod_info_t *ki, void *d) { return KERN_SUCCESS; }
extern "C" kern_return_t _stop(kmod_info_t *ki, void *d)  { return KERN_SUCCESS; }

static constexpr uint8_t  kSmnIndex = 0x60, kSmnData = 0x64;
static constexpr uint32_t kThmTconCurTmp = 0x00059800;
static constexpr uint32_t kCurTempRangeSel = 1u << 19;   // set: the reading is offset by 49 degrees C (-49..206 range)

class NMSensors : public IOService {
    OSDeclareDefaultStructors(NMSensors)
public:
    bool start(IOService *provider) override;
    void stop(IOService *provider) override;
    uint16_t tctlSp78();                 // SMC sp78 value, already in SMC byte order
private:
    IOPCIDevice *fPci = nullptr;
    IOLock *fLock = nullptr;
    IONotifier *fNotifier = nullptr;
    VirtualSMCAPI::Plugin fPlugin { "NMSensors", parseModuleVersion("1.0.0"), VirtualSMCAPI::Version };
    static bool vsmcNotification(void *sensors, void *refCon, IOService *vsmc, IONotifier *notifier);
};
OSDefineMetaClassAndStructors(NMSensors, IOService)

// one key value: refreshed from the sensor whenever it is read
class NMTempValue : public VirtualSMCValue {
    NMSensors *fOwner;
protected:
    SMC_RESULT readAccess() override {
        *reinterpret_cast<uint16_t *>(data) = fOwner->tctlSp78();
        return SmcSuccess;
    }
public:
    explicit NMTempValue(NMSensors *owner) : fOwner(owner) {}
};

uint16_t NMSensors::tctlSp78()
{
    IOLockLock(fLock);
    fPci->configWrite32(kSmnIndex, kThmTconCurTmp);
    const uint32_t v = fPci->configRead32(kSmnData);
    IOLockUnlock(fLock);
    // bits 31:21 = temperature in 1/8 degree C; sp78 counts 1/256 degree C in 15 bits with a separate sign bit
    int32_t t256 = (int32_t)((v >> 21) & 0x7FF) * 32;
    if (v & kCurTempRangeSel) t256 -= 49 * 256;
    if (t256 < 0) t256 = 0;
    if (t256 > 0x7FFF) t256 = 0x7FFF;
    return OSSwapInt16((uint16_t)t256);
}

static bool cpuIsZen()
{
    uint32_t a, b, c, d;
    __asm__ volatile("cpuid" : "=a"(a), "=b"(b), "=c"(c), "=d"(d) : "a"(0));
    const bool amd = b == 0x68747541 && d == 0x69746e65 && c == 0x444d4163;   // "AuthenticAMD"
    __asm__ volatile("cpuid" : "=a"(a), "=b"(b), "=c"(c), "=d"(d) : "a"(1));
    const uint32_t family = ((a >> 8) & 0xF) + (((a >> 8) & 0xF) == 0xF ? ((a >> 20) & 0xFF) : 0);
    return amd && (family == 0x17 || family == 0x19 || family == 0x1A);
}

bool NMSensors::vsmcNotification(void *sensors, void *refCon, IOService *vsmc, IONotifier *notifier)
{
    if (!sensors || !vsmc) return false;
    NMSensors *me = static_cast<NMSensors *>(sensors);
    const IOReturn r = vsmc->callPlatformFunction(VirtualSMCAPI::SubmitPlugin, true, sensors, &me->fPlugin, nullptr, nullptr);
    if (r == kIOReturnSuccess) { NMLOG("keys submitted to VirtualSMC"); return true; }
    if (r != kIOReturnUnsupported) NMLOG("VirtualSMC refused the plugin (0x%x)", r);
    return false;
}

bool NMSensors::start(IOService *provider)
{
    if (!IOService::start(provider)) return false;
    if (!cpuIsZen()) { NMLOG("not an AMD Zen CPU - not starting"); return false; }
    fPci = OSDynamicCast(IOPCIDevice, provider);
    if (!fPci) return false;
    fLock = IOLockAlloc();
    if (!fLock) return false;
    const uint32_t first = OSSwapInt16(tctlSp78());
    NMLOG("root complex %04x:%04x, Tctl %u.%02u C at start", fPci->configRead16(kIOPCIConfigVendorID),
          fPci->configRead16(kIOPCIConfigDeviceID), first >> 8, ((first & 0xFF) * 100) >> 8);
    // CPU proximity, die and package keys that monitoring applications (iStat Menus, Stats, BuhoCleaner) read
    static const SMC_KEY keys[] = {
        SMC_MAKE_IDENTIFIER('T', 'C', '0', 'P'), SMC_MAKE_IDENTIFIER('T', 'C', '0', 'D'),
        SMC_MAKE_IDENTIFIER('T', 'C', '0', 'E'), SMC_MAKE_IDENTIFIER('T', 'C', '0', 'F'),
        SMC_MAKE_IDENTIFIER('T', 'C', '0', 'H'), SMC_MAKE_IDENTIFIER('T', 'C', 'X', 'C'),
    };
    static const SMC_DATA zero[2] = { 0, 0 };
    bool ok = true;
    for (unsigned i = 0; i < sizeof keys / sizeof keys[0]; i++)
        ok &= VirtualSMCAPI::addKey(keys[i], fPlugin.data,
                                    VirtualSMCAPI::valueWithData(zero, sizeof zero, SmcKeyTypeSp78, new NMTempValue(this)));
    if (!ok) { NMLOG("could not add the temperature keys"); return false; }
    fNotifier = VirtualSMCAPI::registerHandler(vsmcNotification, this);
    if (!fNotifier) { NMLOG("VirtualSMC is not available"); return false; }
    registerService();
    return true;
}

void NMSensors::stop(IOService *provider)
{
    // VirtualSMC keeps the submitted keys for the rest of the boot; nothing here may be torn down safely
    IOService::stop(provider);
}
