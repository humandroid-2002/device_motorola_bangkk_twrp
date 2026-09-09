#
#	This file is part of the SHRP Recovery Project
#	Copyright (C) 2024-2025 The SHRP Recovery Project
#
#	SHRP is free software: you can redistribute it and/or modify
#	it under the terms of the GNU General Public License as published by
#	the Free Software Foundation, either version 3 of the License, or
#	(at your option) any later version.
#
#	SHRP is distributed in the hope that it will be useful,
#	but WITHOUT ANY WARRANTY; without even the implied warranty of
#	MERCHANTIBILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
#	GNU General Public License for more details.
#

SHRP_DEVICE_CODE            := bangkk
SHRP_PATH                   := device/bangkk/$(SHRP_DEVICE_CODE)
SHRP_MAINTAINER             := YamamaY
SHRP_DEVICE_TYPE            := A/B
SHRP_REC_TYPE               := SAR
SHRP_REC                    := /dev/block/bootdevice/by-name/boot
SHRP_HAS_RECOVERY_PARTITION := true
SHRP_AB                     := true
SHRP_EDL_MODE               := 1
SHRP_EXTERNAL               := /external_sd
SHRP_OTG                    := /usb_otg
SHRP_FLASH                  := 0
SHRP_EXPRESS                := true
SHRP_EXPRESS_USE_DATA       := true
SHRP_DARK                   := true
SHRP_OFFICIAL               := true
IS_OFFICIAL                 := 1
