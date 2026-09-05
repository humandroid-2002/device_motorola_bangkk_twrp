## Custom Recovery device tree for the Motorola Moto G84 5G

The Motorola Moto G84 5G (codenamed "bangkk") is a mid-range smartphone from Motorola.

It was announced in August 2023 and released in September 2023.

## Device specifications

| Feature                        | Specification                                                     |
| -----------------------------: | :---------------------------------------------------------------- |
| Chipset                        | Qualcomm Snapdragon 695 5G (6 nm)                                 |
| CPU                            | Octa-core (2x2.2 GHz Kryo 660 Gold & 6x1.7 GHz Kryo 660 Silver)   |
| GPU                            | Adreno 619                                                        |
| Memory                         | 8GB / 12GB RAM                                                    |
| Shipped OS                     | Android 13                                                        |
| Storage                        | 256GB                                                             |
| SIM                            | Dual Nano-SIM                                                     |
| MicroSD                        | microSDXC (shared SIM slot)                                       |
| Battery                        | Li-Po 5000 mAh, 30W wired charging                                |
| Dimensions                     | 160 x 74.4 x 7.6 mm                                               |
| Display                        | 6.5 inches, 1080 x 2400, P-OLED, 120Hz                            |
| WLAN                           | Wi-Fi 802.11 a/b/g/n/ac, dual-band                                |
| Bluetooth                      | 5.1                                                               |
| USB                            | USB Type-C 2.0                                                    |
| Fingerprint                    | Under-display optical fingerprint sensor                          |

## Device picture

<img src="https://fdn2.gsmarena.com/vv/pics/motorola/motorola-moto-g84-2.jpg" width="45%"/>

---

## First-time installation
    * Download the `boot.img` file from the Releases section.  
      We currently provide unofficial builds for TWRP, SHRP, OrangeFox, and PBRP.
    * Reboot your device to bootloader mode
    * Run:
          `fastboot boot boot.img`
    * In recovery, go to Advanced Settings and select:
          `Flash Current Recovery`
      (REQUIRED)
    * Reboot back to recovery (REQUIRED)
    * Done

## Updating the recovery
    * Download the latest `boot.img` from the Releases section
    * Connect the phone via USB and copy `boot.img` to the Download folder
    * From custom recovery, select the image and choose:
          `Install Recovery Ramdisk`
    * Reboot back to recovery
    * Done

## OTA Survival / Keep Recovery After ROM Updates
    * This device uses the A/B partition scheme.
    * When installing OTA updates or flashing custom ROMs, the system may overwrite the
      `boot` and `vendor_boot` partitions with the stock recovery.
    * To preserve your custom recovery, follow these steps:

    * Boot into recovery
    * Flash your ROM or OTA `.zip`
    * (Optional) Enable:
          `Automatically reflash recovery after installation`
    * DO NOT reboot to system yet
    * If auto-reflash was not enabled:
          Go to:
          `Advanced -> Flash Current Recovery`
    * Wait for the process to complete
    * Reboot back to recovery
          This switches the device to the newly updated active slot
    * After rebooting back into recovery, you may flash:
          * Magisk
          * Custom kernels
          * Modules / add-ons
    * Format Data if Clean Install
    * Reboot to system

---

## Kernel

This device tree uses a prebuilt kernel extracted from:

`lineage-23.2-20260515-nightly-bangkk-signed.zip`

---

## Working and non-working features

### Device integration

* [x] Recovery haptics/vibration
* [x] Screen wake behavior
* [x] Brightness control
* [ ] Flashlight
* [x] Battery status
* [x] CPU temperature
* [x] EDL reboot
* [x] Flash ZIPs (Magisk, ROMs, kernels, modules, etc.)
* [ ] ⚠️ Caution: You must use a properly made and compatible AnyKernel3.zip.  
      A broken or incompatible AnyKernel zip can cause bootloops.  
      This is not a recovery issue.

### Data and encryption

* [x] FBE `/data` decryption without screen lock
* [x] FBE `/data` decryption with PIN/password
* [x] Metadata encryption support
* [x] Format Data
* [x] Internal Storage mount after decrypt/format

### Backup and flashing

* [x] Backup and restore boot-related partitions
* [x] Clean Mount/Backup/Image partition labels
* [x] Flash official and unofficial signed ROMs
* [x] Flash `system.img` from Install Image
* [x] Flash `vendor.img` from Install Image
* [x] Flash boot, vendor_boot, dtbo and vbmeta images

### Storage and connectivity

* [x] MicroSD storage
* [x] USB-OTG storage
* [x] MTP export
* [x] ADB access and sideload
* [x] exFAT and NTFS storage support
* [x] EROFS F2FS EXT4 filesystem support

---

## Copyright

```
#
# Copyright (C) 2026 The TWRP Open Source Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
#  *  Copyright (C) 2026 The OrangeFox Recovery Project
#  *
#  * This program is free software: you can redistribute it and/or modify
#  * it under the terms of the GNU General Public License as published by
#  * the Free Software Foundation, either version 3 of the License, or
#  * (at your option) any later version.
#  *
#  * This program is distributed in the hope that it will be useful,
#  * but WITHOUT ANY WARRANTY; without even the implied warranty of
#  * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  * GNU General Public License for more details.
#  *
#  * You should have received a copy of the GNU General Public License
#  * along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
```
