## About WLAN & Remote Access

Permanent recovery flashing is required until you are running LineageOS 24.0, as the WLAN kernel module has a considerably large file size.

After connecting to Wi-Fi, use another device (phone or PC) on the same network and open the recovery IP in a browser. Credits to adontoo for implementing this feature.

> **Note:** Do not use Microsoft Edge. Uploading big files will always fail.

| Feature                        | How to use                                                        |
| -----------------------------: | :---------------------------------------------------------------- |
| Wireless ADB                   | Connect the phone and PC to the same Wi-Fi, then run `adb connect IP_device:5555`. |
| Remote Web Access              | **First set or generate a password use fox terminal or adb:** `fox web password --generate` (or `fox web password <your_password>`).<br>**Then enable:** `fox web enable`, or from recovery **Wi-Fi → Apps → Remote Web Access → Enable** (enable fails without a password).<br>**PC browser:** open `http://IP_device:80` and enter the token/password. |
| TWRP Web File Manager          | **Recovery:** Wi-Fi → Apps → Web File Manager → Start.<br>**PC browser:** open `http://IP_device:8080` to upload/download files. |
| NAS (SFTP/SMB)                 | **Recovery:** Wi-Fi → Apps → Network Storage (NAS). Enter Type, Host/IP, Port, User, Password and Path/Share, then **Mount** → **Use**. |

### NAS example (Linux PC + Samba)

| Setting                        | Value                                                              |
| -----------------------------: | :---------------------------------------------------------------- |
| Type                           | `smb`                                                              |
| Host/IP                        | PC IP (e.g. `192.168.0.135`)                                       |
| Share                          | `FoxShare`                                                         |
| Username                       | PC user                                                            |
| Password                       | PC password                                                        |
| Path                           | `FoxShare`                                                         |
| Port                           | empty / `445` (or `22` for SFTP)                                   |
| Cache                          | `off` or `data`                                                    |

---

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

## Kernel

This device tree uses a prebuilt kernel extracted from:

`lineage-23.2-20261106-nightly-bangkk-signed.zip`

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
* [ ] You must use a properly made and compatible AnyKernel3.zip.  
      A broken or incompatible AnyKernel zip can make youre device unusable'.  
      This is not a recovery issue. Do not flash AnyKernel zip files if you do not know what you are doing.

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
* [x] **High-speed sideloading** via prebuilt binary (parallel XZ/BZ2, direct write, bypasses VAB/COW path)
* [x] **Auto-reflash recovery** post-ROM flash

### Storage and connectivity

* [x] **WI-FI**
* [x] **Wireless ADB** (Port 5555)
* [x] **Web-UI Dashboard** (Browser access via IP)
* [x] **NAS Mounting** (SFTP/SMB) for direct backups/flashing
* [x] **rclone integration** (UPX/LZMA compressed to fit ramdisk)
* [x] MicroSD storage
* [x] USB-OTG storage
* [x] MTP export
* [x] ADB access and sideload
* [x] exFAT and NTFS storage support
* [x] F2FS EROFS EXT4 filesystem support

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

## Credits

- [TeamWin](https://github.com/TeamWin) - TWRP device tree generator
- [OrangeFox](https://gitlab.com/OrangeFox) - OpenSource & Team Developers
- [adontoo](https://github.com/adontoo) - Web File tranfer
- [LineageOS](https://github.com/LineageOS) - Kernel modules & continuous device support
