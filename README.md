# OpenCore EFI: MSI B550 + Ryzen 5 5600G + RTX 2070 on macOS 26 Tahoe

[Русская версия](README.ru.md)

The OpenCore configuration of one desktop that runs macOS 26 Tahoe with an NVIDIA RTX 2070 through the
[NullMoth NVIDIA driver](https://github.com/nullmoth/nvidia-macos-driver), next to Windows on its own disk.
It boots quietly (Apple logo and progress bar, no text), shows only macOS and Windows in the picker, and Windows
keeps the board's own SMBIOS.

Made with an AI assistant (Claude, Anthropic) and tested on this one machine. Use it as a reference, not as a
drop-in EFI: other boards, CPUs and cards need their own changes.

## Hardware

| Part | Model |
|---|---|
| Board | MSI B550 GAMING GEN3 (MS-7B86, AMD 500-series chipset) |
| CPU | AMD Ryzen 5 5600G (6 cores, 12 threads; the integrated GPU is not used) |
| GPU | NVIDIA GeForce RTX 2070 (TU106, 8 GB, 256 MB BAR1) |
| Wi-Fi / Bluetooth | Intel AX210 |
| Ethernet | Realtek RTL8111 |
| Displays | 2560x1440 100 Hz, 1920x1080 60 Hz (both on the RTX 2070) |
| macOS | 26.7.1 (25G241), SMBIOS iMac20,1 |

## What is in this repository

```
EFI/BOOT/.contentVisibility, .contentFlavour   hide the fallback loader's entry in the picker
EFI/OC/.contentVisibility                      the same for OpenCore's own folder
EFI/OC/config.plist                            the configuration (serials replaced by placeholders)
EFI/OC/ACPI/SSDT-CPUR.aml, SSDT-EC-USBX-DESKTOP.aml
acpi/*.dsl                                     their source (disassembled)
tools/cpuname.sh                               real CPU name in About This Mac without code patching
tools/btfix.sh                                 Bluetooth crash fix for BlueToolFixup on macOS 26
tools/nmsensors/                               NMSensors.kext source: CPU temperature for VirtualSMC
```

No binaries are included. Get them from their authors:

| File | Version | Source |
|---|---|---|
| `EFI/BOOT/BOOTx64.efi`, `EFI/OC/OpenCore.efi` | OpenCore 1.0.8 **RELEASE** | [OpenCorePkg](https://github.com/acidanthera/OpenCorePkg/releases) |
| `Drivers/OpenRuntime.efi`, `OpenCanopy.efi`, `OpenHfsPlus.efi`, `ResetNvramEntry.efi` | 1.0.8 | OpenCorePkg |
| `Tools/OpenShell.efi` | 1.0.8 | OpenCorePkg |
| `Resources/` (picker theme, fonts) | — | [OcBinaryData](https://github.com/acidanthera/OcBinaryData) |
| Lilu | 1.7.2 | [acidanthera/Lilu](https://github.com/acidanthera/Lilu/releases) |
| VirtualSMC, SMCSuperIO | 1.3.8 | [acidanthera/VirtualSMC](https://github.com/acidanthera/VirtualSMC/releases) |
| RestrictEvents | 1.1.6 | [acidanthera/RestrictEvents](https://github.com/acidanthera/RestrictEvents/releases) |
| BlueToolFixup | 2.7.2 | [acidanthera/BrcmPatchRAM](https://github.com/acidanthera/BrcmPatchRAM/releases) |
| AMFIPass | 1.4.1 | [OpenCore Legacy Patcher](https://github.com/dortania/OpenCore-Legacy-Patcher) |
| itlwm | 2.3.0 | [OpenIntelWireless/itlwm](https://github.com/OpenIntelWireless/itlwm/releases) |
| IntelBluetoothFirmware, IntelBTPatcher | 2.5.0 | [OpenIntelWireless/IntelBluetoothFirmware](https://github.com/OpenIntelWireless/IntelBluetoothFirmware/releases) |
| RealtekRTL8111 | 3.0.0 | [Mieze/RTL8111_driver_for_OS_X](https://github.com/Mieze/RTL8111_driver_for_OS_X/releases) |
| NMSensors | 1.0.0 | build from `tools/nmsensors` (see below) |
| NootedRed | — | listed but disabled; not needed when the display is on the NVIDIA card |

Use the OpenCore **RELEASE** build: the DEBUG build prints its log on screen before the picker, which defeats the
quiet boot. Check the configuration with `ocvalidate` from the same OpenCore release.

## Before the first boot

1. **SMBIOS.** Generate your own iMac20,1 serial, MLB and UUID (for example with
   [GenSMBIOS](https://github.com/corpnewt/GenSMBIOS)) and put them into `PlatformInfo > Generic`
   (`SystemSerialNumber`, `MLB`, `SystemUUID`). Set `ROM` to the MAC address of your Ethernet port. The file holds
   OpenCore's sample placeholders (`W00000000001`, `M0000000000000001`, zeros, `112233445566`).
2. **CPU core count.** The `algrey | Force cpuid_cores_per_package` kernel patches carry this CPU's core count (6).
   Set yours, as described in the [AMD Vanilla patches](https://github.com/AMD-OSX/AMD_Vanilla).
3. **The NVIDIA driver.** Install the [NullMoth driver](https://github.com/nullmoth/nvidia-macos-driver) (2.3.4 is
   used here; 2.0.1 before it). The boot arguments, `Kernel > Block > IONDRVSupport` and the SIP value come from its
   [docs/HOW-IT-WORKS.md](https://github.com/nullmoth/nvidia-macos-driver/blob/main/docs/HOW-IT-WORKS.md). The fixes
   used on this machine are in the fork
   [artpetrow-cmyk/nvidia-macos-driver](https://github.com/artpetrow-cmyk/nvidia-macos-driver): branch
   `rtx2070-macos26-2.3.4` on 2.3.4, `rtx2070-macos26` on 2.0.1.

## Configuration choices

- **Quiet boot.** No `-v` in `boot-args`. `PollAppleHotKeys` is on, so in the picker Cmd+V boots verbose and
  Shift+Enter boots safe mode (safe mode does not load kexts from `/Library/Extensions` — the way back after a bad
  driver install).
- **Only macOS and Windows in the picker.** `HideAuxiliary` hides recovery and tools (press Space to show them).
  `.contentVisibility` = `Disabled` in `EFI/BOOT` and `EFI/OC` hides the extra "EFI" entries.
  `LauncherOption` = `Full` registers OpenCore as a boot option of its own in the firmware.
- **Windows.** `ScanPolicy` (0x12F0503) includes the ESP bit (0x400), so the Windows Boot Manager on the EFI
  partition is listed. `UpdateSMBIOSMode` = `Custom` with `Kernel > Quirks > CustomSMBIOSGuid` gives macOS the iMac
  SMBIOS and leaves Windows the board's own one, so Windows activation is not affected.
- **SIP** `csr-active-config` = `0x0A43`, which includes authenticated-root disabled (0x800). The NullMoth driver's
  copy of its Metal plugin in `/System` (needed for Safari's GPU process) and both tools below write to the live
  system volume, which needs that bit. It lowers the system's protection; `SecureBootModel` is `Disabled`.
- **SSDT-CPUR** is the unmodified sample. A variant with its processor objects inside a table-level
  `If (_OSI ("Darwin"))` hung macOS at about 30 % of the boot bar: macOS's ACPI interpreter drops named objects
  created inside such a block.
- **RestrictEvents** runs with `revpatch=sbvmm` only — see "CPU name" below.

## CPU name in About This Mac

RestrictEvents' `revpatch=cpuname` patches AppleSystemInfo's code in memory. On macOS 26 that code lives in the
sealed OS cryptex; when the patched page is paged in again the APFS seal check fails and About This Mac / System
Information crash with SIGBUS.

`tools/cpuname.sh` changes data instead: the string macOS shows for this SMBIOS processor type and core count
("6-Core Intel Core i5") in `AppleSystemInfo.framework/Resources/Processors.loctable`, in every language, on the live
system volume, then blesses a new snapshot.

```
sudo bash tools/cpuname.sh "AMD Ryzen 5 5600G"   # change it, then reboot
bash tools/cpuname.sh --check                    # what the booted system shows
sudo bash tools/cpuname.sh --revert              # put Apple's file back
```

It saves Apple's original next to itself before the first change. Rerun after every macOS update.

## Bluetooth crash (BlueToolFixup on macOS 26)

With BlueToolFixup, `bluetoothd` crashed with SIGBUS when a headset connected, and Bluetooth stayed hung. The cause
is not disk corruption: BlueToolFixup patches pages of `bluetoothd` in memory, and macOS 26's APFS re-hashes the
whole 16 KB block of a sealed file on page-in, which then mismatches.

`tools/btfix.sh` rewrites `bluetoothd` and `BlueTool` on the live system volume with Apple's own bytes (read through
a separate mount, so they are unpatched; the signature and CDHash are checked) and blesses a new snapshot.

```
sudo bash tools/btfix.sh            # apply, then reboot
sudo bash tools/btfix.sh --revert   # boot the last sealed snapshot again
```

Rerun after every macOS update. The published script is the one used on this machine with its messages translated
to English and the fallback copies for one macOS build removed.

## NMSensors.kext

A small VirtualSMC plugin that reports the Zen CPU temperature (Tctl from the SMU, SMN 0x00059800, the register Linux
`k10temp` reads). It is read-only: no MSRs, no power-management callbacks, no private kernel symbols. Add it after
VirtualSMC in `Kernel > Add`.

```
VSMC=<VirtualSMC-1.3.8 source> LILU=<Lilu-1.7.2 source>/Lilu bash tools/nmsensors/build.sh
```

## Known issues

- No audio over HDMI/DisplayPort (the NullMoth driver does not support it yet) and no onboard audio
  (AppleHDA is gone in macOS 26).
- Do not restart WindowServer (`killall WindowServer`): with the NVIDIA driver the machine freezes with black
  screens and needs a hard reset.
- A macOS update replaces the sealed system: rerun `cpuname.sh`, `btfix.sh` and the NVIDIA driver's `/System`
  plugin copy afterwards.

## Thanks

- [NullMoth Systems](https://nullmothsystems.com) ([driver on GitHub](https://github.com/nullmoth/nvidia-macos-driver)) for the NVIDIA driver that makes this machine work at
  all — support the author at [buymeacoffee.com/nullmoth](https://buymeacoffee.com/nullmoth).
- [Acidanthera](https://github.com/acidanthera) for OpenCore, Lilu, VirtualSMC, RestrictEvents and BlueToolFixup.
- [AMD-OSX](https://github.com/AMD-OSX/AMD_Vanilla) for the AMD kernel patches.
- [OpenIntelWireless](https://github.com/OpenIntelWireless) (zxystd) for itlwm and the Intel Bluetooth kexts.
- [Mieze](https://github.com/Mieze/RTL8111_driver_for_OS_X) for the RTL8111 driver.
- [dhinakg](https://github.com/dhinakg) for AMFIPass, [corpnewt](https://github.com/corpnewt/GenSMBIOS) for GenSMBIOS.
- [Dortania](https://dortania.github.io/OpenCore-Install-Guide/) for the guides and the SSDT samples.

## License

The files written for this repository (`tools/`, this guide) are under the BSD 3-Clause license ([LICENSE](LICENSE)).
`config.plist` is derived from OpenCore's `Sample.plist` (BSD 3-Clause, Acidanthera); the SSDTs are OpenCore and
Dortania samples. The kexts and OpenCore binaries listed above keep their own licenses and are not redistributed here.
