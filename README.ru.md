# OpenCore EFI: MSI B550 + Ryzen 5 5600G + RTX 2070, macOS 26 Tahoe

[English version](README.md)

Конфигурация OpenCore одного настольного компьютера: macOS 26 Tahoe с NVIDIA RTX 2070 через
[драйвер NullMoth](https://github.com/nullmoth/nvidia-macos-driver), рядом Windows на своём диске. Загрузка тихая
(яблоко и полоса прогресса, без текста), в меню только macOS и Windows, Windows видит родной SMBIOS платы.

Сделано с помощью ИИ-ассистента (Claude, Anthropic), проверено на одной этой машине. Это образец, а не готовая EFI
«скопировал и работает»: другим платам, процессорам и видеокартам нужны свои правки.

## Железо

| Часть | Модель |
|---|---|
| Плата | MSI B550 GAMING GEN3 (MS-7B86, чипсет AMD 500-й серии) |
| Процессор | AMD Ryzen 5 5600G (6 ядер, 12 потоков; встроенная графика не используется) |
| Видеокарта | NVIDIA GeForce RTX 2070 (TU106, 8 ГБ, BAR1 256 МБ) |
| Wi-Fi / Bluetooth | Intel AX210 |
| Ethernet | Realtek RTL8111 |
| Мониторы | 2560x1440 100 Гц, 1920x1080 60 Гц (оба на RTX 2070) |
| macOS | 26.7.1 (25G241), SMBIOS iMac20,1 |

## Что в репозитории

```
EFI/BOOT/.contentVisibility, .contentFlavour   скрывают запасной загрузчик в меню
EFI/OC/.contentVisibility                      то же для папки OpenCore
EFI/OC/config.plist                            конфигурация (серийники заменены заглушками)
EFI/OC/ACPI/SSDT-CPUR.aml, SSDT-EC-USBX-DESKTOP.aml
acpi/*.dsl                                     их исходники (дизассемблированы)
tools/cpuname.sh                               настоящее имя процессора в «Об этом Mac» без правки кода
tools/btfix.sh                                 исправление падений Bluetooth с BlueToolFixup на macOS 26
tools/nmsensors/                               исходники NMSensors.kext: температура CPU для VirtualSMC
```

Бинарных файлов нет — их берут у авторов:

| Файл | Версия | Где взять |
|---|---|---|
| `EFI/BOOT/BOOTx64.efi`, `EFI/OC/OpenCore.efi` | OpenCore 1.0.8 **RELEASE** | [OpenCorePkg](https://github.com/acidanthera/OpenCorePkg/releases) |
| `Drivers/OpenRuntime.efi`, `OpenCanopy.efi`, `OpenHfsPlus.efi`, `ResetNvramEntry.efi` | 1.0.8 | OpenCorePkg |
| `Tools/OpenShell.efi` | 1.0.8 | OpenCorePkg |
| `Resources/` (тема меню, шрифты) | — | [OcBinaryData](https://github.com/acidanthera/OcBinaryData) |
| Lilu | 1.7.2 | [acidanthera/Lilu](https://github.com/acidanthera/Lilu/releases) |
| VirtualSMC, SMCSuperIO | 1.3.8 | [acidanthera/VirtualSMC](https://github.com/acidanthera/VirtualSMC/releases) |
| RestrictEvents | 1.1.6 | [acidanthera/RestrictEvents](https://github.com/acidanthera/RestrictEvents/releases) |
| BlueToolFixup | 2.7.2 | [acidanthera/BrcmPatchRAM](https://github.com/acidanthera/BrcmPatchRAM/releases) |
| AMFIPass | 1.4.1 | [OpenCore Legacy Patcher](https://github.com/dortania/OpenCore-Legacy-Patcher) |
| itlwm | 2.3.0 | [OpenIntelWireless/itlwm](https://github.com/OpenIntelWireless/itlwm/releases) |
| IntelBluetoothFirmware, IntelBTPatcher | 2.5.0 | [OpenIntelWireless/IntelBluetoothFirmware](https://github.com/OpenIntelWireless/IntelBluetoothFirmware/releases) |
| RealtekRTL8111 | 3.0.0 | [Mieze/RTL8111_driver_for_OS_X](https://github.com/Mieze/RTL8111_driver_for_OS_X/releases) |
| NMSensors | 1.0.0 | собрать из `tools/nmsensors` (см. ниже) |
| NootedRed | — | есть в списке, но выключен: не нужен, когда экран на видеокарте NVIDIA |

Нужна сборка OpenCore **RELEASE**: DEBUG печатает журнал на экран ещё до меню, и тихой загрузки не будет. Проверяйте
конфигурацию `ocvalidate` из того же выпуска OpenCore.

## Перед первой загрузкой

1. **SMBIOS.** Сгенерируйте свои серийный номер, MLB и UUID для iMac20,1 (например,
   [GenSMBIOS](https://github.com/corpnewt/GenSMBIOS)) и впишите в `PlatformInfo > Generic` (`SystemSerialNumber`,
   `MLB`, `SystemUUID`). В `ROM` — MAC-адрес вашего Ethernet. Сейчас там заглушки из примера OpenCore
   (`W00000000001`, `M0000000000000001`, нули, `112233445566`).
2. **Число ядер.** Патчи ядра `algrey | Force cpuid_cores_per_package` содержат число ядер этого процессора (6).
   Поставьте своё, как описано в [AMD Vanilla patches](https://github.com/AMD-OSX/AMD_Vanilla).
3. **Драйвер NVIDIA.** Установите [драйвер NullMoth](https://github.com/nullmoth/nvidia-macos-driver) (здесь 2.3.4,
   раньше 2.0.1). Аргументы загрузки, `Kernel > Block > IONDRVSupport` и значение SIP взяты из его
   [docs/HOW-IT-WORKS.md](https://github.com/nullmoth/nvidia-macos-driver/blob/main/docs/HOW-IT-WORKS.md). Исправления,
   которые стоят на этой машине, — в форке
   [artpetrow-cmyk/nvidia-macos-driver](https://github.com/artpetrow-cmyk/nvidia-macos-driver): ветка
   `rtx2070-macos26-2.3.4` на 2.3.4, `rtx2070-macos26` на 2.0.1.

## Почему так настроено

- **Тихая загрузка.** В `boot-args` нет `-v`. Включён `PollAppleHotKeys`: в меню Cmd+V — загрузка с текстом,
  Shift+Enter — безопасный режим (он не грузит kext'ы из `/Library/Extensions`; это путь назад после неудачной
  установки драйвера).
- **В меню только macOS и Windows.** `HideAuxiliary` прячет восстановление и инструменты (показать — пробел).
  `.contentVisibility` = `Disabled` в `EFI/BOOT` и `EFI/OC` убирает лишние пункты «EFI». `LauncherOption` = `Full`
  регистрирует OpenCore отдельным пунктом загрузки в прошивке.
- **Windows.** В `ScanPolicy` (0x12F0503) есть бит ESP (0x400), поэтому виден Windows Boot Manager на EFI-разделе.
  `UpdateSMBIOSMode` = `Custom` вместе с `Kernel > Quirks > CustomSMBIOSGuid` дают macOS SMBIOS iMac, а Windows
  оставляют родной SMBIOS платы — активация Windows не страдает.
- **SIP** `csr-active-config` = `0x0A43`, в том числе выключен authenticated-root (0x800). Копия Metal-плагина
  NullMoth в `/System` (нужна GPU-процессу Safari) и оба инструмента ниже пишут на живой системный том, а для этого
  нужен этот бит. Защита системы от этого слабее; `SecureBootModel` = `Disabled`.
- **SSDT-CPUR** — неизменённый образец. Вариант, где процессоры объявлены внутри `If (_OSI ("Darwin"))` на уровне
  таблицы, вешал macOS примерно на 30 % полосы загрузки: ACPI-интерпретатор macOS отбрасывает именованные объекты,
  созданные внутри такого блока.
- **RestrictEvents** работает только с `revpatch=sbvmm` — см. «Имя процессора».

## Имя процессора в «Об этом Mac»

`revpatch=cpuname` из RestrictEvents правит код AppleSystemInfo в памяти. В macOS 26 этот код лежит в запечатанном
криптексе ОС: когда исправленная страница подгружается заново, проверка печати APFS не проходит, и «Об этом Mac» /
«Информация о системе» падают с SIGBUS.

`tools/cpuname.sh` меняет не код, а данные: строку, которую macOS показывает для этого типа процессора из SMBIOS и
числа ядер («6-Core Intel Core i5»), в `AppleSystemInfo.framework/Resources/Processors.loctable`, во всех языках, на
живом системном томе, после чего создаёт новый загрузочный снимок.

```
sudo bash tools/cpuname.sh "AMD Ryzen 5 5600G"   # заменить и перезагрузиться
bash tools/cpuname.sh --check                    # что показывает загруженная система
sudo bash tools/cpuname.sh --revert              # вернуть файл Apple
```

Перед первым изменением скрипт сохраняет оригинал Apple рядом с собой. После каждого обновления macOS запускать
заново.

## Падения Bluetooth (BlueToolFixup на macOS 26)

С BlueToolFixup `bluetoothd` падал с SIGBUS при подключении гарнитуры, и Bluetooth зависал. Диск тут ни при чём:
BlueToolFixup правит страницы `bluetoothd` в памяти, а APFS в macOS 26 при подгрузке пересчитывает хэш всего блока
16 КБ запечатанного файла, и он не сходится.

`tools/btfix.sh` переписывает `bluetoothd` и `BlueTool` на живом системном томе собственными байтами Apple
(читает их через отдельное монтирование, где страницы не исправлены; проверяет подпись и CDHash) и создаёт новый
загрузочный снимок.

```
sudo bash tools/btfix.sh            # применить и перезагрузиться
sudo bash tools/btfix.sh --revert   # снова загружаться с последнего запечатанного снимка
```

После каждого обновления macOS запускать заново. Опубликованный скрипт — тот же, что работает на этой машине, только
сообщения переведены на английский и убраны запасные копии файлов для одной сборки macOS.

## NMSensors.kext

Небольшой плагин VirtualSMC: температура процессора Zen (Tctl из SMU, SMN 0x00059800 — тот же регистр, что читает
`k10temp` в Linux). Только чтение: никаких MSR, обратных вызовов управления питанием и закрытых символов ядра.
Ставится в `Kernel > Add` сразу после VirtualSMC.

```
VSMC=<исходники VirtualSMC-1.3.8> LILU=<исходники Lilu-1.7.2>/Lilu bash tools/nmsensors/build.sh
```

## Известные проблемы

- Нет звука через HDMI/DisplayPort (драйвер NullMoth его пока не поддерживает) и встроенного звука (AppleHDA в
  macOS 26 нет).
- Не перезапускайте WindowServer (`killall WindowServer`): с драйвером NVIDIA машина замирает с чёрными экранами,
  помогает только жёсткая перезагрузка.
- Обновление macOS заменяет запечатанную систему: после него заново `cpuname.sh`, `btfix.sh` и копия плагина драйвера
  NVIDIA в `/System`.

## Благодарности

- [NullMoth Systems](https://nullmothsystems.com/ru/) ([драйвер на GitHub](https://github.com/nullmoth/nvidia-macos-driver)) — за драйвер NVIDIA, без которого эта машина вообще бы не
  работала. Поддержать автора: [buymeacoffee.com/nullmoth](https://buymeacoffee.com/nullmoth).
- [Acidanthera](https://github.com/acidanthera) — OpenCore, Lilu, VirtualSMC, RestrictEvents и BlueToolFixup.
- [AMD-OSX](https://github.com/AMD-OSX/AMD_Vanilla) — патчи ядра для AMD.
- [OpenIntelWireless](https://github.com/OpenIntelWireless) (zxystd) — itlwm и kext'ы Bluetooth Intel.
- [Mieze](https://github.com/Mieze/RTL8111_driver_for_OS_X) — драйвер RTL8111.
- [dhinakg](https://github.com/dhinakg) — AMFIPass, [corpnewt](https://github.com/corpnewt/GenSMBIOS) — GenSMBIOS.
- [Dortania](https://dortania.github.io/OpenCore-Install-Guide/) — руководства и образцы SSDT.

## Лицензия

Файлы, написанные для этого репозитория (`tools/`, эта инструкция), — под лицензией BSD 3-Clause ([LICENSE](LICENSE)).
`config.plist` сделан на основе `Sample.plist` из OpenCore (BSD 3-Clause, Acidanthera); SSDT — образцы OpenCore и
Dortania. Kext'ы и бинарники OpenCore из таблицы выше остаются под своими лицензиями и здесь не распространяются.
